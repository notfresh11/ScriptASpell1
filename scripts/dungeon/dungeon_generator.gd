# scripts/dungeon/dungeon_generator.gd
extends Node3D

@export var num_pieces: int = 25 # Numărul de piese dintr-o sesiune de dungeon
@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

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

# Grid 3D de ocupare: cheia este Vector3i(grid_x, grid_y, grid_z)
# Fiecare celulă are 10m latură pe X/Z și 4m înălțime pe Y!
var grid_occupied: Dictionary = {}

# Piese instanțiate
var spawned_pieces: Array[Node3D] = []

# Direcții cardinale
const NORTH = Vector3i(0, 0, -1)
const SOUTH = Vector3i(0, 0, 1)
const EAST  = Vector3i(1, 0, 0)
const WEST  = Vector3i(-1, 0, 0)

const CELL_SIZE = Vector3(10.0, 4.0, 10.0)

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

func grid_to_world(grid_pos: Vector3i) -> Vector3:
	return Vector3(
		grid_pos.x * CELL_SIZE.x,
		grid_pos.y * CELL_SIZE.y,
		grid_pos.z * CELL_SIZE.z
	)

# Inspection dinamică a Marker3D (Exits) din scenele instanțiate
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

# Rotire vector direcție 2D/3D în jurul Y cu un număr de rotații de 90 grade
func rotate_dir(dir: Vector3i, rot_count: int) -> Vector3i:
	var res = dir
	for i in range(rot_count % 4):
		res = Vector3i(-res.z, res.y, res.x)
	return res

# Returnează lista direcțiilor socket-urilor citind direct din nodurile Marker3D ale scenei
func get_socket_directions_from_scene(piece_scene: PackedScene) -> Array[Vector3i]:
	var dummy = piece_scene.instantiate()
	var markers = get_piece_exit_markers(dummy)
	var dirs: Array[Vector3i] = []
	for m in markers:
		var local_pos = m.position
		var dir_x = round(local_pos.x / 5.0)
		var dir_z = round(local_pos.z / 5.0)
		dirs.append(Vector3i(dir_x, 0, dir_z))
	dummy.queue_free()
	return dirs

# Determină rotațiile valide pentru a conecta o intrare din `incoming_dir`
func get_socket_rotations_for_entrance(piece_scene: PackedScene, incoming_dir: Vector3i) -> Array[int]:
	var required_socket_dir = -incoming_dir
	var base_exits = get_socket_directions_from_scene(piece_scene)

	var valid_rots: Array[int] = []
	for rot in range(4):
		for b_exit in base_exits:
			if rotate_dir(b_exit, rot) == required_socket_dir:
				if not valid_rots.has(rot):
					valid_rots.append(rot)
	return valid_rots

# Returnează lista ieșirilor unei piese la o rotație dată
func get_exits_for_piece(piece_scene: PackedScene, rot_count: int) -> Array[Vector3i]:
	var base_exits = get_socket_directions_from_scene(piece_scene)
	var rotated_exits: Array[Vector3i] = []
	for b_exit in base_exits:
		rotated_exits.append(rotate_dir(b_exit, rot_count))
	return rotated_exits

# --- GENERARE PROCEDURALĂ BAZATĂ PE GRID 3D RIGID ---
func generate_dungeon() -> void:
	print("Începe generarea procedurală pe 3D Grid (10x10x4m)...")
	grid_occupied.clear()
	spawned_pieces.clear()

	for child in pieces_node.get_children():
		child.queue_free()

	# 1. Plasare ENTRANCE la celula (0,0,0)
	var entrance_grid_pos = Vector3i(0, 0, 0)
	var entrance_inst = ENTRANCE_SCENE.instantiate()
	entrance_inst.name = "Piece_Entrance"
	entrance_inst.position = grid_to_world(entrance_grid_pos)
	entrance_inst.rotation_degrees = Vector3.ZERO
	pieces_node.add_child(entrance_inst, true)
	spawned_pieces.append(entrance_inst)

	grid_occupied[entrance_grid_pos] = entrance_inst

	# Stivă de conectat (Frontier/Queue de ieșiri deschise)
	var open_frontiers: Array[Dictionary] = [
		{ "grid_pos": entrance_grid_pos, "dir": NORTH }
	]

	var available_flat_scenes = [HALLWAY_SCENE, CORNER_SCENE, T_JUNCTION_SCENE, FOUR_WAY_SCENE, ROOM_SCENE]
	var stair_scenes = [STAIRS_STRAIGHT_SCENE, STAIRS_ZIGZAG_SCENE]

	var pieces_placed_count = 1

	while not open_frontiers.is_empty() and pieces_placed_count < num_pieces:
		var frontier = open_frontiers.pop_front()
		var source_cell: Vector3i = frontier["grid_pos"]
		var step_dir: Vector3i = frontier["dir"]

		var target_cell: Vector3i = source_cell + step_dir

		if grid_occupied.has(target_cell):
			continue

		var use_stairs = (randf() < 0.20) and abs(target_cell.y) <= 2
		var chosen_scene: PackedScene = null

		if use_stairs:
			chosen_scene = stair_scenes.pick_random()
		else:
			chosen_scene = available_flat_scenes.pick_random()

		var valid_rots = get_socket_rotations_for_entrance(chosen_scene, step_dir)
		if valid_rots.is_empty():
			chosen_scene = HALLWAY_SCENE
			valid_rots = get_socket_rotations_for_entrance(chosen_scene, step_dir)

		if valid_rots.is_empty():
			continue

		var chosen_rot = valid_rots.pick_random()

		var piece_inst = chosen_scene.instantiate()
		piece_inst.name = "Piece_%d" % pieces_placed_count

		var actual_target_cell = target_cell

		piece_inst.position = grid_to_world(actual_target_cell)
		piece_inst.rotation_degrees.y = chosen_rot * -90.0

		pieces_node.add_child(piece_inst, true)
		spawned_pieces.append(piece_inst)
		grid_occupied[actual_target_cell] = piece_inst
		pieces_placed_count += 1

		var current_exits = get_exits_for_piece(chosen_scene, chosen_rot)
		var entry_dir_used = -step_dir

		for ex_dir in current_exits:
			if ex_dir == entry_dir_used:
				continue

			# Dacă piesa este o scară, ieșirea opusă (Exit_North) duce la nivelul inferior Y - 1!
			var next_grid_cell = actual_target_cell
			if chosen_scene in stair_scenes:
				next_grid_cell.y -= 1

			open_frontiers.append({
				"grid_pos": next_grid_cell,
				"dir": ex_dir
			})

	# 2. Sigilăm TOATE ieșirile libere rămase pe grid cu DEAD END (Pereți de capăt)
	_seal_all_open_exits(open_frontiers)

	print("Dungeon generat pe grid 3D cu succes! Total piese: %d" % spawned_pieces.size())

	if multiplayer.is_server():
		spawn_dungeon_loot()

# Sigilare finală a oricărei ieșiri neconectate cu o piesă de capăt
func _seal_all_open_exits(frontiers: Array[Dictionary]) -> void:
	for frontier in frontiers:
		var source_cell: Vector3i = frontier["grid_pos"]
		var step_dir: Vector3i = frontier["dir"]
		var target_cell: Vector3i = source_cell + step_dir

		if grid_occupied.has(target_cell):
			continue

		var valid_rots = get_socket_rotations_for_entrance(DEAD_END_SCENE, step_dir)
		if valid_rots.is_empty():
			continue

		var chosen_rot = valid_rots[0]
		var dead_end_inst = DEAD_END_SCENE.instantiate()
		dead_end_inst.name = "Piece_DeadEnd_%d" % spawned_pieces.size()
		dead_end_inst.position = grid_to_world(target_cell)
		dead_end_inst.rotation_degrees.y = chosen_rot * -90.0

		pieces_node.add_child(dead_end_inst, true)
		spawned_pieces.append(dead_end_inst)
		grid_occupied[target_cell] = dead_end_inst

# --- SPAWNING LOOT PROCEDURAL AȘEZAT PE PODEA ---
func spawn_dungeon_loot() -> void:
	print("Se spawnează loot pe podeaua pieselor...")
	for piece in spawned_pieces:
		if piece.name.contains("Entrance") or piece.name.contains("DeadEnd") or piece.name.contains("Stair"):
			continue

		var floor_y = piece.global_position.y
		var center_pos = Vector3(piece.global_position.x, floor_y + 0.3, piece.global_position.z)

		if piece.name.contains("Room") or piece.scene_file_path.contains("room"):
			var count = randi_range(1, 3)
			for j in range(count):
				spawn_loot_at(center_pos)
		else:
			if randf() < 0.30:
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
		price = randi_range(80, 120)
		color = Color(0.6, 0.1, 0.8, 1)
	elif rarity_roll < 0.20:
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

	var spawn_p = pos + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
	loot_node.add_child(loot_instance, true)
	loot_instance.global_position = spawn_p
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
