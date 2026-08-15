# scripts/dungeon/dungeon_generator.gd
extends Node3D

@export var max_main_pieces: int = 30
@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

# Ponderi de plasare tweakabile din Inspector (Weighted Piece Selection)
@export_group("Piece Weights")
@export var hallway_weight: float = 35.0
@export var corner_weight: float = 25.0
@export var t_junction_weight: float = 15.0
@export var four_way_weight: float = 10.0
@export var room_weight: float = 20.0
@export var stairs_straight_weight: float = 8.0
@export var stairs_zigzag_weight: float = 8.0

@export_group("Loop Settings")
@export var loop_chance: float = 0.15 # 15% șansă de a forma buclă dacă 2 ieșiri se întâlnesc

# Preîncărcăm piesele modulare + Loot
const ENTRANCE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/entrance_piece.tscn")
const HALLWAY_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/hallway_piece.tscn")
const CORNER_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/corner_piece.tscn")
const T_JUNCTION_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/t_junction_piece.tscn")
const FOUR_WAY_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/four_way_piece.tscn")
const ROOM_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/room_piece.tscn")
const STAIRS_STRAIGHT_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/stairs_straight_piece.tscn")
const STAIRS_ZIGZAG_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/stairs_zigzag_piece.tscn")
const DEAD_END_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/dead_end_piece.tscn")
const LOOT_SCENE: PackedScene = preload("res://scenes/interactables/loot_item.tscn")

@onready var pieces_node: Node3D = $Pieces
@onready var players_node: Node3D = $Players
@onready var loot_node: Node3D = $Loot
@onready var back_button: Button = $CanvasLayer/Control/CenterContainer/VBox/BackButton

# Grid stocare piese pe coordonate discrete de celulă 2D (10x10m grid)
# Format: { Vector2i(x, y): { "scene": PackedScene, "rot_steps": int, "active_dirs": Array[int], "instance": Node3D, "depth": int } }
var grid: Dictionary = {}

func _ready() -> void:
	if get_parent() == get_tree().root:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		back_button.pressed.connect(_on_back_pressed)

		if multiplayer.is_server():
			generate_dungeon()
			await get_tree().create_timer(0.2).timeout
			spawn_all_players()
	else:
		if has_node("CanvasLayer"):
			$CanvasLayer.queue_free()

# --- DIRECȚII GRID (0=North, 1=East, 2=South, 3=West) ---
func get_dir_vector(dir: int) -> Vector2i:
	match dir:
		0: return Vector2i(0, -1) # North
		1: return Vector2i(1, 0)  # East
		2: return Vector2i(0, 1)  # South
		3: return Vector2i(-1, 0) # West
	return Vector2i.ZERO

# --- DETECTARE DINAMICĂ MARKER3D (SOCKET-URI) ---
func get_piece_exit_markers(piece_instance: Node3D) -> Array[Marker3D]:
	var markers: Array[Marker3D] = []
	var exits_container = piece_instance.get_node_or_null("Exits")
	if exits_container:
		for child in exits_container.get_children():
			if child is Marker3D:
				markers.append(child as Marker3D)
	else:
		for child in piece_instance.get_children():
			if child is Marker3D:
				markers.append(child as Marker3D)
	return markers

func get_piece_base_directions(piece_scene: PackedScene) -> Array[int]:
	var dirs: Array[int] = []
	var temp_inst = piece_scene.instantiate()
	var markers = get_piece_exit_markers(temp_inst)
	for m in markers:
		var pos = m.position
		if pos.z < -2.0:
			if not 0 in dirs: dirs.append(0) # North
		elif pos.x > 2.0:
			if not 1 in dirs: dirs.append(1) # East
		elif pos.z > 2.0:
			if not 2 in dirs: dirs.append(2) # South
		elif pos.x < -2.0:
			if not 3 in dirs: dirs.append(3) # West
	temp_inst.queue_free()
	return dirs

func get_active_directions(base_dirs: Array[int], rot_steps: int) -> Array[int]:
	var active: Array[int] = []
	for b in base_dirs:
		active.append((b + rot_steps) % 4)
	return active

# Calculul ponderilor dinamice în funcție de adâncime (Depth-Based Generation)
func get_scene_weight(scene: PackedScene, depth_ratio: float) -> float:
	match scene:
		HALLWAY_SCENE:
			# Multe coridoare la început (depth mic), mai puține adânc
			return lerp(hallway_weight * 1.5, hallway_weight * 0.5, depth_ratio)
		CORNER_SCENE:
			return corner_weight
		T_JUNCTION_SCENE:
			return lerp(t_junction_weight * 0.5, t_junction_weight * 1.5, depth_ratio)
		FOUR_WAY_SCENE:
			return lerp(four_way_weight * 0.3, four_way_weight * 1.8, depth_ratio)
		ROOM_SCENE:
			# Camere mari puține la început, foarte multe adânc în dungeon (săli de tezaur)
			return lerp(room_weight * 0.2, room_weight * 2.5, depth_ratio)
		STAIRS_STRAIGHT_SCENE:
			return stairs_straight_weight
		STAIRS_ZIGZAG_SCENE:
			return stairs_zigzag_weight
	return 10.0

# Sortare ponderată
func select_weighted_scene(candidate_scenes: Array, depth_ratio: float) -> PackedScene:
	if candidate_scenes.is_empty():
		return null

	var total_w = 0.0
	var weights = []

	for sc in candidate_scenes:
		var w = get_scene_weight(sc, depth_ratio)
		weights.append(w)
		total_w += w

	var roll = randf() * total_w
	var accum = 0.0
	for i in range(candidate_scenes.size()):
		accum += weights[i]
		if roll <= accum:
			return candidate_scenes[i]

	return candidate_scenes[0]

# --- ALGORITMUL DE GENERARE PROCEDURALĂ BAZAT PE SOCKET-URI & GRID 10x10M ---
func generate_dungeon() -> void:
	print("Începe generarea procedurală a dungeon-ului (Socket-based + Depth + Controlled Loops)...")

	grid.clear()

	for child in pieces_node.get_children():
		child.queue_free()

	var open_exits_queue: Array[Dictionary] = []

	# 1. Entrance la (0, 0)
	var entrance_base_dirs = get_piece_base_directions(ENTRANCE_SCENE)
	var entrance_active_dirs = get_active_directions(entrance_base_dirs, 0)

	var entrance_instance = ENTRANCE_SCENE.instantiate()
	entrance_instance.name = "Piece_0_0_Entrance"
	entrance_instance.position = Vector3.ZERO
	entrance_instance.rotation_degrees = Vector3.ZERO
	pieces_node.add_child(entrance_instance, true)

	grid[Vector2i(0, 0)] = {
		"scene": ENTRANCE_SCENE,
		"rot_steps": 0,
		"active_dirs": entrance_active_dirs,
		"instance": entrance_instance,
		"depth": 0
	}

	for d in entrance_active_dirs:
		open_exits_queue.append({
			"cell": Vector2i(0, 0),
			"dir": d,
			"depth": 1
		})

	var normal_piece_scenes = [
		HALLWAY_SCENE,
		CORNER_SCENE,
		T_JUNCTION_SCENE,
		FOUR_WAY_SCENE,
		ROOM_SCENE,
		STAIRS_STRAIGHT_SCENE,
		STAIRS_ZIGZAG_SCENE
	]

	var scene_base_dirs = {}
	for sc in normal_piece_scenes:
		scene_base_dirs[sc] = get_piece_base_directions(sc)

	# 2. Procesăm coada de ieșiri deschise
	while not open_exits_queue.is_empty() and grid.size() < max_main_pieces:
		var current_exit = open_exits_queue.pop_front()
		var cell: Vector2i = current_exit["cell"]
		var exit_dir: int = current_exit["dir"]
		var depth: int = current_exit["depth"]

		var target_cell: Vector2i = cell + get_dir_vector(exit_dir)
		var incoming_dir: int = (exit_dir + 2) % 4

		# Dacă celula țintă este deja ocupată, verificăm dacă putem forma un circuit/bucle (Controlled Loops)
		if target_cell in grid:
			# Dacă e activat loop_chance și piesa din celula țintă are un socket orientat spre incoming_dir, lăsăm deschisă conexiunea!
			if randf() < loop_chance:
				var nbr_active_dirs: Array = grid[target_cell]["active_dirs"]
				if incoming_dir in nbr_active_dirs:
					print("S-a format o buclă/circuit la celula: ", target_cell)
			continue

		var depth_ratio = float(grid.size()) / float(max_main_pieces)

		# Clonăm lista de piese candidate
		var candidates = normal_piece_scenes.duplicate()
		var piece_placed = false

		while not candidates.is_empty() and not piece_placed:
			var scene = select_weighted_scene(candidates, depth_ratio)
			candidates.erase(scene)

			var base_dirs: Array[int] = scene_base_dirs[scene]
			var possible_rotations = [0, 1, 2, 3]
			possible_rotations.shuffle()

			for rot_steps in possible_rotations:
				var active_dirs = get_active_directions(base_dirs, rot_steps)

				if not incoming_dir in active_dirs:
					continue

				var valid = true
				for d in active_dirs:
					if d == incoming_dir:
						continue
					var nbr = target_cell + get_dir_vector(d)
					if nbr in grid:
						var nbr_incoming = (d + 2) % 4
						var nbr_active_dirs: Array = grid[nbr]["active_dirs"]
						if not nbr_incoming in nbr_active_dirs:
							valid = false
							break

				if not valid:
					continue

				var piece_instance: Node3D = scene.instantiate()
				piece_instance.name = "Piece_%d_%d" % [target_cell.x, target_cell.y]

				# Offset pe Y mic pentru piese de scări
				var y_offset = 0.0
				if scene == STAIRS_STRAIGHT_SCENE or scene == STAIRS_ZIGZAG_SCENE:
					y_offset = -1.0 # coborâre nivel

				piece_instance.position = Vector3(target_cell.x * 10.0, y_offset, target_cell.y * 10.0)
				piece_instance.rotation_degrees = Vector3(0.0, -rot_steps * 90.0, 0.0)

				pieces_node.add_child(piece_instance, true)

				grid[target_cell] = {
					"scene": scene,
					"rot_steps": rot_steps,
					"active_dirs": active_dirs,
					"instance": piece_instance,
					"depth": depth
				}

				piece_placed = true

				for d in active_dirs:
					if d != incoming_dir:
						var nbr = target_cell + get_dir_vector(d)
						if not nbr in grid:
							open_exits_queue.append({
								"cell": target_cell,
								"dir": d,
								"depth": depth + 1
							})
				break

	# 3. Sigilarea tuturor ieșirilor rămase deschise cu Dead End-uri
	var dead_end_base_dirs = get_piece_base_directions(DEAD_END_SCENE) # [2] (South)

	var unsealed_exits: Array[Dictionary] = []
	for cell in grid:
		var info = grid[cell]
		for d in info["active_dirs"]:
			var nbr = cell + get_dir_vector(d)
			if not nbr in grid:
				unsealed_exits.append({
					"from_cell": cell,
					"exit_dir": d,
					"target_cell": nbr
				})

	for conn in unsealed_exits:
		var target_cell: Vector2i = conn["target_cell"]
		if target_cell in grid:
			continue

		var exit_dir: int = conn["exit_dir"]
		var incoming_dir: int = (exit_dir + 2) % 4

		var rot_steps: int = (incoming_dir - 2 + 4) % 4
		var active_dirs = get_active_directions(dead_end_base_dirs, rot_steps)

		var dead_end_instance: Node3D = DEAD_END_SCENE.instantiate()
		dead_end_instance.name = "Piece_%d_%d_DeadEnd" % [target_cell.x, target_cell.y]
		dead_end_instance.position = Vector3(target_cell.x * 10.0, 0.0, target_cell.y * 10.0)
		dead_end_instance.rotation_degrees = Vector3(0.0, -rot_steps * 90.0, 0.0)

		pieces_node.add_child(dead_end_instance, true)

		grid[target_cell] = {
			"scene": DEAD_END_SCENE,
			"rot_steps": rot_steps,
			"active_dirs": active_dirs,
			"instance": dead_end_instance,
			"depth": 99
		}

	print("Dungeon generat cu succes! Total piese plasate pe socket-uri: ", grid.size())

	if multiplayer.is_server():
		spawn_dungeon_loot()

# --- SPAWNING LOOT PROCEDURAL ÎN FUNCȚIE DE ADÂNCIME ---
func spawn_dungeon_loot() -> void:
	print("Se spawnează loot în piese în funcție de adâncime...")
	for cell in grid:
		var info = grid[cell]
		if info["scene"] == ENTRANCE_SCENE or info["scene"] == DEAD_END_SCENE:
			continue

		var center_pos = Vector3(cell.x * 10.0, 0.5, cell.y * 10.0)
		var depth = info.get("depth", 1)

		if info["scene"] == ROOM_SCENE:
			var count = randi_range(1, 3)
			for j in range(count):
				spawn_loot_at(center_pos, depth)
		else:
			if randf() < 0.25:
				spawn_loot_at(center_pos, depth)

func spawn_loot_at(pos: Vector3, depth: int) -> void:
	if not multiplayer.is_server():
		return

	var loot_instance = LOOT_SCENE.instantiate()
	var rarity_roll = randf()

	# Șanse crescute de loot Epic și Rare la adâncimi mari (depth > 5)
	var epic_chance = 0.05 + (0.02 * depth)
	var rare_chance = 0.20 + (0.03 * depth)

	var rarity = "common"
	var price = 15
	var color = Color(0.5, 0.5, 0.5, 1)

	if rarity_roll < epic_chance:
		rarity = "epic"
		price = randi_range(80, 120)
		color = Color(0.6, 0.1, 0.8, 1)
	elif rarity_roll < rare_chance:
		rarity = "rare"
		price = randi_range(50, 80)
		color = Color(0.9, 0.8, 0.1, 1)
	elif rarity_roll < 0.55:
		rarity = "uncommon"
		price = randi_range(30, 50)
		color = Color(0.1, 0.7, 0.2, 1)
	else:
		rarity = "common"
		price = randi_range(10, 30)
		color = Color(0.5, 0.5, 0.5, 1)

	var unique_id = str(randi()) + "_" + str(Time.get_ticks_msec())

	loot_instance.position = pos + Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
	loot_node.add_child(loot_instance, true)
	loot_instance.init_loot(unique_id, rarity, price, color)

# --- SPAWNING MULTIPLAYER PLAYERS ---
func spawn_all_players() -> void:
	for player_id in NetworkManager.players:
		var player_instance = player_scene.instantiate()
		player_instance.name = str(player_id)
		player_instance.player_id = player_id

		players_node.add_child(player_instance)
		player_instance.global_position = Vector3(0.0, 1.0, 0.0)

# --- BACK NAVIGATION ---
func _on_back_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if $CanvasLayer/Control.visible:
			$CanvasLayer/Control.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			$CanvasLayer/Control.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
