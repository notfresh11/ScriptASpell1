# scripts/dungeon/dungeon_generator.gd
extends Node3D

@export var max_main_pieces: int = 10
@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

# Preîncărcăm cele 7 piese modulare
const ENTRANCE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/entrance_piece.tscn")
const HALLWAY_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/hallway_piece.tscn")
const CORNER_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/corner_piece.tscn")
const T_JUNCTION_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/t_junction_piece.tscn")
const FOUR_WAY_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/four_way_piece.tscn")
const ROOM_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/room_piece.tscn")
const DEAD_END_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/dead_end_piece.tscn")

@onready var pieces_node: Node3D = $Pieces
@onready var players_node: Node3D = $Players
@onready var back_button: Button = $CanvasLayer/Control/CenterContainer/VBox/BackButton

# Grid stocare piese: { Vector2i(x, y): { "path": String, "rotation_steps": int, "ports": Array, "instance": Node3D } }
var grid: Dictionary = {}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	back_button.pressed.connect(_on_back_pressed)

	if multiplayer.is_server():
		# Generăm structura hărții exclusiv pe server
		generate_dungeon()

		# Așteptăm un moment scurt pentru propagarea datelor pe rețea, apoi spawnăm jucătorii
		await get_tree().create_timer(0.2).timeout
		spawn_all_players()

# --- DETECTOR DIRECȚII ---
func get_dir_vector(dir: int) -> Vector2i:
	match dir:
		0: return Vector2i(0, -1) # North
		1: return Vector2i(1, 0)  # East
		2: return Vector2i(0, 1)  # South
		3: return Vector2i(-1, 0) # West
	return Vector2i.ZERO

func rotate_ports_array(base_ports: Array, steps: int) -> Array:
	var rotated = [false, false, false, false]
	for i in range(4):
		rotated[(i + steps) % 4] = base_ports[i]
	return rotated

# --- ALGORITMUL DE GENERARE PROCEDURALĂ ---
func generate_dungeon() -> void:
	print("Începe generarea procedurală a dungeon-ului...")

	# 1. Plasăm piesa de intrare la (0, 0) cu rotație 0 (deschisă doar spre Nord)
	var entrance_instance: Node3D = ENTRANCE_SCENE.instantiate()
	entrance_instance.name = "Piece_0_0"
	entrance_instance.position = Vector3(0, 0, 0)
	pieces_node.add_child(entrance_instance)

	grid[Vector2i(0, 0)] = {
		"path": ENTRANCE_SCENE.resource_path,
		"rotation_steps": 0,
		"ports": [true, false, false, false],
		"instance": entrance_instance
	}

	# Coadă pentru conexiuni pendinte: [{ "from": Vector2i, "to": Vector2i, "from_dir": int }]
	var queue: Array = []
	queue.append({
		"from": Vector2i(0, 0),
		"to": Vector2i(0, -1),
		"from_dir": 0 # Am plecat spre Nord din (0,0)
	})

	var main_pieces_count: int = 1

	# 2. Generăm arborele principal de piese
	while queue.size() > 0 and main_pieces_count < max_main_pieces:
		var connection = queue.pop_front()
		var target_cell: Vector2i = connection["to"]

		# Dacă celula țintă este deja ocupată, continuăm
		if target_cell in grid:
			continue

		# Căutăm candidați compatibili conform regulilor stricte
		var candidates: Array = get_valid_pieces_for(target_cell)
		if candidates.is_empty():
			continue # Fără potrivire validă pentru această celulă

		# Alegem un candidat aleatoriu și îl plasăm
		var chosen = candidates[randi() % candidates.size()]
		var piece_scene: PackedScene = load(chosen["path"])
		var piece_instance: Node3D = piece_scene.instantiate()

		piece_instance.name = "Piece_%d_%d" % [target_cell.x, target_cell.y]
		# FIX REPLICARE MULTIPLAYER: Setăm poziția și rotația ÎNAINTE de add_child() ca MultiplayerSpawner să le trimită corect clienților!
		piece_instance.position = Vector3(target_cell.x * 10.0, 0.0, target_cell.y * 10.0)
		piece_instance.rotation_degrees.y = -chosen["rotation_steps"] * 90.0

		pieces_node.add_child(piece_instance)

		grid[target_cell] = {
			"path": chosen["path"],
			"rotation_steps": chosen["rotation_steps"],
			"ports": chosen["ports"],
			"instance": piece_instance
		}

		main_pieces_count += 1

		# Adăugăm noile ieșiri deschise ale piesei în coadă
		for dir in range(4):
			if chosen["ports"][dir]:
				var neighbor_cell: Vector2i = target_cell + get_dir_vector(dir)
				if not neighbor_cell in grid:
					queue.append({
						"from": target_cell,
						"to": neighbor_cell,
						"from_dir": dir
					})

	# 3. Sigilarea hărții: punem Dead Ends în toate porturile rămase deschise către celule goale
	var open_connections_to_seal: Array = []
	for cell in grid:
		var info = grid[cell]
		for dir in range(4):
			if info["ports"][dir]:
				var neighbor_cell: Vector2i = cell + get_dir_vector(dir)
				if not neighbor_cell in grid:
					open_connections_to_seal.append({
						"from": cell,
						"to": neighbor_cell,
						"from_dir": dir
					})

	for conn in open_connections_to_seal:
		var target_cell: Vector2i = conn["to"]
		if target_cell in grid:
			continue

		var rot_steps: int = conn["from_dir"]

		var dead_end_instance: Node3D = DEAD_END_SCENE.instantiate()
		dead_end_instance.name = "Piece_%d_%d_Sealed" % [target_cell.x, target_cell.y]
		# FIX REPLICARE MULTIPLAYER: Setăm poziția și rotația ÎNAINTE de add_child() ca MultiplayerSpawner să le trimită corect clienților!
		dead_end_instance.position = Vector3(target_cell.x * 10.0, 0.0, target_cell.y * 10.0)
		dead_end_instance.rotation_degrees.y = -rot_steps * 90.0

		pieces_node.add_child(dead_end_instance)

		grid[target_cell] = {
			"path": DEAD_END_SCENE.resource_path,
			"rotation_steps": rot_steps,
			"ports": rotate_ports_array([false, false, true, false], rot_steps),
			"instance": dead_end_instance
		}

	print("Dungeon generat cu succes! Total piese: ", grid.size())

# --- GĂSIREA CANDIDAȚILOR COMPATIBILI (CONSTRÂNGERI ADIACENTE) ---
func get_valid_pieces_for(cell: Vector2i) -> Array:
	var candidates: Array = []

	# Constrângeri pe cele 4 direcții:
	# 1 = MUST_HAVE_PORT, -1 = MUST_NOT_HAVE_PORT, 0 = OPTIONAL
	var constraints = [0, 0, 0, 0]

	for dir in range(4):
		var neighbor_cell: Vector2i = cell + get_dir_vector(dir)
		if neighbor_cell in grid:
			var neighbor = grid[neighbor_cell]
			var neighbor_opp_port: int = (dir + 2) % 4
			if neighbor["ports"][neighbor_opp_port]:
				constraints[dir] = 1
			else:
				constraints[dir] = -1
		else:
			constraints[dir] = 0

	# Toate piesele din pool care pot fi plasate (excluzând Entrance și DeadEnd din pool-ul generat direct)
	var pool = [
		{"path": HALLWAY_SCENE.resource_path, "base_ports": [true, false, true, false]},
		{"path": CORNER_SCENE.resource_path, "base_ports": [true, true, false, false]},
		{"path": T_JUNCTION_SCENE.resource_path, "base_ports": [true, true, false, true]},
		{"path": FOUR_WAY_SCENE.resource_path, "base_ports": [true, true, true, true]},
		{"path": ROOM_SCENE.resource_path, "base_ports": [true, false, true, false]}
	]

	for item in pool:
		for rot_steps in range(4):
			var rotated_ports: Array = rotate_ports_array(item["base_ports"], rot_steps)

			var is_valid: bool = true
			for dir in range(4):
				if constraints[dir] == 1 and not rotated_ports[dir]:
					is_valid = false
					break
				if constraints[dir] == -1 and rotated_ports[dir]:
					is_valid = false
					break

			if is_valid:
				candidates.append({
					"path": item["path"],
					"rotation_steps": rot_steps,
					"ports": rotated_ports
				})

	return candidates

# --- SPAWNING MULTIPLAYER PLAYERS ---
func spawn_all_players() -> void:
	# Spawnăm fiecare player conectat la poziția (0, 1.0, 0) - centrul intrării
	for player_id in NetworkManager.players:
		var player_instance = player_scene.instantiate()
		player_instance.name = str(player_id)
		player_instance.player_id = player_id

		# FIX REPLICARE MULTIPLAYER: Adăugăm jucătorul în arbore și setăm poziția corect
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
