# scripts/dungeon/dungeon_generator.gd
extends Node3D

@export var max_main_pieces: int = 30
@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

# Preîncărcăm cele 7 piese modulare + Loot
const ENTRANCE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/entrance_piece.tscn")
const HALLWAY_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/hallway_piece.tscn")
const CORNER_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/corner_piece.tscn")
const T_JUNCTION_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/t_junction_piece.tscn")
const FOUR_WAY_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/four_way_piece.tscn")
const ROOM_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/room_piece.tscn")
const DEAD_END_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/dead_end_piece.tscn")
const LOOT_SCENE: PackedScene = preload("res://scenes/interactables/loot_item.tscn")

@onready var pieces_node: Node3D = $Pieces
@onready var players_node: Node3D = $Players
@onready var loot_node: Node3D = $Loot
@onready var back_button: Button = $CanvasLayer/Control/CenterContainer/VBox/BackButton

# Grid stocare piese pe coordonate discrete de celulă 2D (10x10m grid)
# Format: { Vector2i(x, y): { "scene": PackedScene, "rot_steps": int, "active_dirs": Array[int], "instance": Node3D } }
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
# Inspectează dinamic Marker3D-urile din scenă la runtime.
# Dacă utilizatorul șterge un Marker3D din editor pentru că o ieșire dă în perete,
# acel direcție NU va fi inclusă în base_dirs!
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

# --- ALGORITMUL DE GENERARE PROCEDURALĂ BAZAT PE SOCKET-URI & GRID 10x10M ---
func generate_dungeon() -> void:
	print("Începe generarea procedurală a dungeon-ului (Sistem bazat pe Socket-uri / Marker3D)...")

	grid.clear()

	# Clear old children in pieces_node if re-generating
	for child in pieces_node.get_children():
		child.queue_free()

	# Coadă de ieșiri deschise: { "cell": Vector2i, "dir": int, "depth": int }
	var open_exits_queue: Array[Dictionary] = []

	# 1. Plasăm Piesa de Intrare (Entrance) la celula (0, 0) cu rotație 0
	var entrance_base_dirs = get_piece_base_directions(ENTRANCE_SCENE)
	var entrance_active_dirs = get_active_directions(entrance_base_dirs, 0)

	var entrance_instance = ENTRANCE_SCENE.instantiate()
	entrance_instance.name = "Piece_0_0_Entrance"
	entrance_instance.position = Vector3(0.0, 0.0, 0.0)
	entrance_instance.rotation_degrees = Vector3.ZERO
	pieces_node.add_child(entrance_instance, true)

	grid[Vector2i(0, 0)] = {
		"scene": ENTRANCE_SCENE,
		"rot_steps": 0,
		"active_dirs": entrance_active_dirs,
		"instance": entrance_instance
	}

	# Adăugăm ieșirile active ale intrării în coadă
	for d in entrance_active_dirs:
		open_exits_queue.append({
			"cell": Vector2i(0, 0),
			"dir": d,
			"depth": 1
		})

	# Pool piese disponibile
	var normal_piece_scenes = [
		HALLWAY_SCENE,
		CORNER_SCENE,
		T_JUNCTION_SCENE,
		FOUR_WAY_SCENE,
		ROOM_SCENE
	]

	# Cache la base directions pentru fiecare scenă
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

		# Dacă celula țintă este deja ocupată, trecem peste
		if target_cell in grid:
			continue

		# Căutăm o piesă compatibilă
		normal_piece_scenes.shuffle()
		var piece_placed = false

		for scene in normal_piece_scenes:
			var base_dirs: Array[int] = scene_base_dirs[scene]
			var possible_rotations = [0, 1, 2, 3]
			possible_rotations.shuffle()

			for rot_steps in possible_rotations:
				var active_dirs = get_active_directions(base_dirs, rot_steps)

				# Piesa TREBUIE să aibă o deschidere/socket în direcția incoming_dir (către părinte)
				if not incoming_dir in active_dirs:
					continue

				# Verificăm dacă vreuna dintre celelalte ieșiri ale piesei dă într-o celulă ocupată necompatibilă
				var valid = true
				for d in active_dirs:
					if d == incoming_dir:
						continue
					var nbr = target_cell + get_dir_vector(d)
					if nbr in grid:
						# Celula învecinată e deja ocupată; verificăm dacă are un exit orientat spre target_cell
						var nbr_incoming = (d + 2) % 4
						var nbr_active_dirs: Array = grid[nbr]["active_dirs"]
						if not nbr_incoming in nbr_active_dirs:
							valid = false
							break

				if not valid:
					continue

				# Piesa și rotația sunt valide! Instanțiem piesa
				var piece_instance: Node3D = scene.instantiate()
				piece_instance.name = "Piece_%d_%d" % [target_cell.x, target_cell.y]
				# Poziționare exactă pe grid de 10m cu Y = 0 strictly!
				piece_instance.position = Vector3(target_cell.x * 10.0, 0.0, target_cell.y * 10.0)
				piece_instance.rotation_degrees = Vector3(0.0, -rot_steps * 90.0, 0.0)

				pieces_node.add_child(piece_instance, true)

				grid[target_cell] = {
					"scene": scene,
					"rot_steps": rot_steps,
					"active_dirs": active_dirs,
					"instance": piece_instance
				}

				piece_placed = true

				# Înregistrăm noile ieșiri deschise în coadă
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

			if piece_placed:
				break

	# 3. Sigilarea tuturor ieșirilor rămase deschise cu Dead End-uri
	# Adunăm toate ieșirile deschise din grid care dau spre celule libere
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

		# DeadEnd are base_dir = 2 (South). Calculăm rot_steps astfel încât active_dir == incoming_dir
		# (2 + rot_steps) % 4 = incoming_dir => rot_steps = (incoming_dir - 2 + 4) % 4
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
			"instance": dead_end_instance
		}

	print("Dungeon generat cu succes! Total piese plasate pe socket-uri: ", grid.size())

	if multiplayer.is_server():
		spawn_dungeon_loot()

# --- SPAWNING LOOT PROCEDURAL ---
func spawn_dungeon_loot() -> void:
	print("Se spawnează loot în piese...")
	for cell in grid:
		var info = grid[cell]
		if info["scene"] == ENTRANCE_SCENE or info["scene"] == DEAD_END_SCENE:
			continue

		var center_pos = Vector3(cell.x * 10.0, 0.5, cell.y * 10.0)

		if info["scene"] == ROOM_SCENE:
			var count = randi_range(1, 3)
			for j in range(count):
				spawn_loot_at(center_pos)
		else:
			if randf() < 0.25:
				spawn_loot_at(center_pos)

func spawn_loot_at(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return

	var loot_instance = LOOT_SCENE.instantiate()
	var rarity_roll = randf()
	var rarity = "common"
	var price = 15
	var color = Color(0.5, 0.5, 0.5, 1)

	if rarity_roll < 0.05:
		rarity = "epic"
		price = randi_range(75, 100)
		color = Color(0.6, 0.1, 0.8, 1)
	elif rarity_roll < 0.20:
		rarity = "rare"
		price = randi_range(50, 75)
		color = Color(0.9, 0.8, 0.1, 1)
	elif rarity_roll < 0.50:
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
