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

# Grid stocare piese: { Vector2i(x, y): { "path": String, "rotation_steps": int, "ports": Array, "type": String, "instance": Node3D } }
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

func get_direction_to(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var diff = to_cell - from_cell
	if diff == Vector2i(0, -1): return 0 # North
	if diff == Vector2i(1, 0): return 1  # East
	if diff == Vector2i(0, 1): return 2  # South
	if diff == Vector2i(-1, 0): return 3 # West
	return -1

func rotate_ports_array(base_ports: Array, steps: int) -> Array:
	var rotated = [false, false, false, false]
	for i in range(4):
		rotated[(i + steps) % 4] = base_ports[i]
	return rotated

# --- CĂUTARE ȘI CONSTRUIRE CALE PRINCIPALA ---
func find_main_path_coords(target_length: int) -> Array:
	var path = [Vector2i(0, 0), Vector2i(0, -1)]

	# Încercare 1: Strictă (fără coridoare care se ating singure, pentru a asigura bucle curate)
	if _dfs_path(path, target_length, 0):
		return path

	# Încercare 2: Relaxată (permite până la 1 punct de atingere pentru flexibilitate)
	path = [Vector2i(0, 0), Vector2i(0, -1)]
	if _dfs_path(path, target_length, 1):
		return path

	# Încercare 3: Foarte relaxată (permite mai multe puncte de atingere ca fallback de siguranță)
	path = [Vector2i(0, 0), Vector2i(0, -1)]
	if _dfs_path(path, target_length, 4):
		return path

	return path

func _dfs_path(path: Array, target_length: int, max_touches: int) -> bool:
	if path.size() == target_length:
		return true

	var curr = path[-1]
	var directions = [0, 1, 2, 3]
	directions.shuffle()

	for dir in directions:
		var next_cell = curr + get_dir_vector(dir)
		if next_cell in path:
			continue

		var touch_count = 0
		for d in range(4):
			var n = next_cell + get_dir_vector(d)
			if n in path and n != curr:
				touch_count += 1

		if touch_count > max_touches:
			continue

		path.append(next_cell)
		if _dfs_path(path, target_length, max_touches):
			return true
		path.pop_back()

	return false

# --- GĂSIRE COMPATIBILITATE SPECIFICĂ PENTRU CALEA PRINCIPALĂ ---
func get_valid_main_path_pieces(incoming_dir: int, outgoing_dir: int) -> Array:
	var candidates = []

	var pool = [
		{"path": HALLWAY_SCENE.resource_path, "base_ports": [true, false, true, false], "type": "hallway"},
		{"path": CORNER_SCENE.resource_path, "base_ports": [true, true, false, false], "type": "corner"},
		{"path": T_JUNCTION_SCENE.resource_path, "base_ports": [true, true, false, true], "type": "t_junction"},
		{"path": FOUR_WAY_SCENE.resource_path, "base_ports": [true, true, true, true], "type": "four_way"},
		{"path": ROOM_SCENE.resource_path, "base_ports": [true, false, true, false], "type": "room"}
	]

	for item in pool:
		for rot_steps in range(4):
			var rotated_ports: Array = rotate_ports_array(item["base_ports"], rot_steps)
			if rotated_ports[incoming_dir] and rotated_ports[outgoing_dir]:
				candidates.append({
					"path": item["path"],
					"rotation_steps": rot_steps,
					"ports": rotated_ports,
					"type": item["type"]
				})

	return candidates

func choose_main_path_piece(candidates: Array, depth_ratio: float) -> Dictionary:
	if candidates.is_empty():
		return {}

	# Definim ponderi specifice tipurilor de piese în funcție de adâncimea curentă
	var weights = {}
	if depth_ratio < 0.3:
		# Early depth: Focus puternic pe coridoare atmosferice
		weights = {
			"hallway": 55.0,
			"corner": 35.0,
			"t_junction": 5.0,
			"four_way": 2.0,
			"room": 3.0
		}
	elif depth_ratio < 0.7:
		# Mid depth: Introducem intersecții și primele camere comune de loot
		weights = {
			"hallway": 20.0,
			"corner": 20.0,
			"t_junction": 25.0,
			"four_way": 10.0,
			"room": 25.0
		}
	else:
		# Deep depth: Camere mari de loot abundent și intersecții majore
		weights = {
			"hallway": 10.0,
			"corner": 10.0,
			"t_junction": 20.0,
			"four_way": 15.0,
			"room": 45.0
		}

	var total_weight = 0.0
	var candidate_weights = []
	for cand in candidates:
		var w = weights.get(cand["type"], 10.0)
		candidate_weights.append(w)
		total_weight += w

	var roll = randf() * total_weight
	var current_sum = 0.0
	for j in range(candidates.size()):
		current_sum += candidate_weights[j]
		if roll <= current_sum:
			return candidates[j]

	return candidates[0]

func get_valid_end_pieces(incoming_dir: int) -> Array:
	var candidates = []
	var pool = [
		{"path": ROOM_SCENE.resource_path, "base_ports": [true, false, true, false], "type": "room"},
		{"path": FOUR_WAY_SCENE.resource_path, "base_ports": [true, true, true, true], "type": "four_way"},
		{"path": T_JUNCTION_SCENE.resource_path, "base_ports": [true, true, false, true], "type": "t_junction"},
		{"path": HALLWAY_SCENE.resource_path, "base_ports": [true, false, true, false], "type": "hallway"},
		{"path": CORNER_SCENE.resource_path, "base_ports": [true, true, false, false], "type": "corner"}
	]

	for item in pool:
		for rot_steps in range(4):
			var rotated_ports: Array = rotate_ports_array(item["base_ports"], rot_steps)
			if rotated_ports[incoming_dir]:
				candidates.append({
					"path": item["path"],
					"rotation_steps": rot_steps,
					"ports": rotated_ports,
					"type": item["type"]
				})

	return candidates

func choose_end_piece(candidates: Array) -> Dictionary:
	if candidates.is_empty():
		return {}

	# Camera de la finalul drumului principal ar trebui să fie una mare (Room sau FourWay)
	var weights = {
		"room": 70.0,
		"four_way": 20.0,
		"t_junction": 10.0,
		"hallway": 0.0,
		"corner": 0.0
	}

	var total_weight = 0.0
	var candidate_weights = []
	for cand in candidates:
		var w = weights.get(cand["type"], 5.0)
		candidate_weights.append(w)
		total_weight += w

	var roll = randf() * total_weight
	var current_sum = 0.0
	for j in range(candidates.size()):
		current_sum += candidate_weights[j]
		if roll <= current_sum:
			return candidates[j]

	return candidates[0]

# --- CHOOSE BRANCH PIECES ---
func choose_branch_piece(candidates: Array) -> Dictionary:
	if candidates.is_empty():
		return {}

	var weights = {
		"room": 50.0,
		"hallway": 20.0,
		"corner": 20.0,
		"t_junction": 10.0,
		"four_way": 0.0
	}

	var total_weight = 0.0
	var candidate_weights = []
	for cand in candidates:
		var w = weights.get(cand["type"], 10.0)
		candidate_weights.append(w)
		total_weight += w

	var roll = randf() * total_weight
	var current_sum = 0.0
	for j in range(candidates.size()):
		current_sum += candidate_weights[j]
		if roll <= current_sum:
			return candidates[j]

	return candidates[0]

# --- ALGORITMUL DE GENERARE PROCEDURALĂ ---
func generate_dungeon() -> void:
	print("Începe generarea procedurală a dungeon-ului...")

	# 1. Generăm coordonatele căii principale (aproximativ 18 piese pe axa de progresie)
	var main_path_length: int = 18
	var path_coords = find_main_path_coords(main_path_length)
	if path_coords.is_empty():
		print("Eroare critică: Calea principală nu a putut fi calculată. Fallback de urgență...")
		path_coords = [Vector2i(0, 0), Vector2i(0, -1)]
		main_path_length = path_coords.size()

	# 2. Plasăm piesa de intrare la (0, 0) cu rotație 0 (deschisă doar spre Nord)
	var entrance_instance: Node3D = ENTRANCE_SCENE.instantiate()
	entrance_instance.name = "Piece_0_0"
	entrance_instance.position = Vector3(0, 0, 0)
	pieces_node.add_child(entrance_instance)

	grid[Vector2i(0, 0)] = {
		"path": ENTRANCE_SCENE.resource_path,
		"rotation_steps": 0,
		"ports": [true, false, false, false],
		"type": "entrance",
		"instance": entrance_instance
	}

	# 3. Plasăm piesele intermediare de pe calea principală
	for i in range(1, path_coords.size() - 1):
		var cell = path_coords[i]
		var incoming_dir = get_direction_to(cell, path_coords[i-1])
		var outgoing_dir = get_direction_to(cell, path_coords[i+1])

		var depth_ratio = float(i) / float(path_coords.size())
		var candidates = get_valid_main_path_pieces(incoming_dir, outgoing_dir)
		var chosen = choose_main_path_piece(candidates, depth_ratio)

		var piece_scene: PackedScene = load(chosen["path"])
		var piece_instance: Node3D = piece_scene.instantiate()

		piece_instance.name = "Piece_%d_%d" % [cell.x, cell.y]
		# FIX REPLICARE MULTIPLAYER: Setăm poziția și rotația ÎNAINTE de add_child() ca MultiplayerSpawner să le trimită corect clienților!
		piece_instance.position = Vector3(cell.x * 10.0, 0.0, cell.y * 10.0)
		piece_instance.rotation_degrees.y = -chosen["rotation_steps"] * 90.0

		pieces_node.add_child(piece_instance)

		grid[cell] = {
			"path": chosen["path"],
			"rotation_steps": chosen["rotation_steps"],
			"ports": chosen["ports"],
			"type": chosen["type"],
			"instance": piece_instance
		}

	# 4. Plasăm piesa finală a căii principale (O cameră sau intersecție mare de destinație)
	if path_coords.size() > 1:
		var last_index = path_coords.size() - 1
		var cell = path_coords[last_index]
		var incoming_dir = get_direction_to(cell, path_coords[last_index - 1])

		var candidates = get_valid_end_pieces(incoming_dir)
		var chosen = choose_end_piece(candidates)

		var piece_scene: PackedScene = load(chosen["path"])
		var piece_instance: Node3D = piece_scene.instantiate()

		piece_instance.name = "Piece_%d_%d_End" % [cell.x, cell.y]
		piece_instance.position = Vector3(cell.x * 10.0, 0.0, cell.y * 10.0)
		piece_instance.rotation_degrees.y = -chosen["rotation_steps"] * 90.0

		pieces_node.add_child(piece_instance)

		grid[cell] = {
			"path": chosen["path"],
			"rotation_steps": chosen["rotation_steps"],
			"ports": chosen["ports"],
			"type": chosen["type"],
			"instance": piece_instance
		}

	# 5. Generăm ramificațiile secundare (Side Branches) din porturile rămase deschise ale căii principale
	var branch_queue: Array = []
	for cell in grid:
		if grid[cell]["type"] == "entrance" or grid[cell]["type"] == "dead_end":
			continue
		for dir in range(4):
			if grid[cell]["ports"][dir]:
				var neighbor_cell = cell + get_dir_vector(dir)
				if not neighbor_cell in grid:
					branch_queue.append({
						"from": cell,
						"to": neighbor_cell,
						"depth": 1
					})

	# Amestecăm porturile de pornire pentru a asigura distribuție ne-liniară a ramificațiilor
	branch_queue.shuffle()

	# Adâncimea maximă a ramificațiilor secundare (1-2 piese max, generând layout tip Pilgrim / Kletka)
	var max_branch_depth = 2
	while branch_queue.size() > 0 and grid.size() < max_main_pieces:
		var conn = branch_queue.pop_front()
		var target_cell: Vector2i = conn["to"]
		var depth = conn["depth"]

		if target_cell in grid:
			continue

		var candidates = get_valid_pieces_for(target_cell)
		if candidates.is_empty():
			continue # Fără potrivire validă pentru această celulă

		var chosen = choose_branch_piece(candidates)
		var piece_scene: PackedScene = load(chosen["path"])
		var piece_instance: Node3D = piece_scene.instantiate()

		piece_instance.name = "Piece_%d_%d_Branch" % [target_cell.x, target_cell.y]
		# FIX REPLICARE MULTIPLAYER: Setăm poziția și rotația ÎNAINTE de add_child() ca MultiplayerSpawner să le trimită corect clienților!
		piece_instance.position = Vector3(target_cell.x * 10.0, 0.0, target_cell.y * 10.0)
		piece_instance.rotation_degrees.y = -chosen["rotation_steps"] * 90.0

		pieces_node.add_child(piece_instance)

		grid[target_cell] = {
			"path": chosen["path"],
			"rotation_steps": chosen["rotation_steps"],
			"ports": chosen["ports"],
			"type": chosen["type"],
			"instance": piece_instance
		}

		# Adăugăm noile ieșiri deschise ale piesei în coada de ramificație (dacă nu am atins adâncimea maximă a ramurii)
		if depth < max_branch_depth:
			for dir in range(4):
				if chosen["ports"][dir]:
					var neighbor_cell: Vector2i = target_cell + get_dir_vector(dir)
					if not neighbor_cell in grid:
						branch_queue.append({
							"from": target_cell,
							"to": neighbor_cell,
							"depth": depth + 1
						})

	# 6. Sigilarea hărții: punem Dead Ends în toate porturile rămase deschise către celule goale
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
			"type": "dead_end",
			"instance": dead_end_instance
		}

	print("Dungeon generat cu succes! Total piese: ", grid.size())

	if multiplayer.is_server():
		spawn_dungeon_loot()

# --- SPAWNING LOOT PROCEDURAL ---
func spawn_dungeon_loot() -> void:
	print("Se spawnează loot în camere...")
	for cell in grid:
		var info = grid[cell]
		if info["type"] == "entrance" or info["type"] == "dead_end":
			continue

		var center_pos = Vector3(cell.x * 10.0, 0.5, cell.y * 10.0)

		if info["type"] == "room":
			# Spawnează între 1 și 3 iteme în camere mari
			var count = randi_range(1, 3)
			for j in range(count):
				spawn_loot_at(center_pos)
		else:
			# 20% șansă de spawn în coridoare/intersecții
			if randf() < 0.2:
				spawn_loot_at(center_pos)

func spawn_loot_at(pos: Vector3) -> void:
	if not multiplayer.is_server():
		return

	var loot_instance = LOOT_SCENE.instantiate()
	var rarity_roll = randf()
	var rarity = "common"
	var price = 15
	var color = Color(0.5, 0.5, 0.5, 1) # Grey

	if rarity_roll < 0.05:
		rarity = "epic"
		price = randi_range(75, 100)
		color = Color(0.6, 0.1, 0.8, 1) # Purple
	elif rarity_roll < 0.20:
		rarity = "rare"
		price = randi_range(50, 75)
		color = Color(0.9, 0.8, 0.1, 1) # Yellow
	elif rarity_roll < 0.50:
		rarity = "uncommon"
		price = randi_range(30, 50)
		color = Color(0.1, 0.7, 0.2, 1) # Green
	else:
		rarity = "common"
		price = randi_range(10, 30)
		color = Color(0.5, 0.5, 0.5, 1) # Grey

	var unique_id = str(randi()) + "_" + str(Time.get_ticks_msec())

	# Setăm poziția înainte de add_child
	loot_instance.position = pos + Vector3(randf_range(-1.5, 1.5), 0.5, randf_range(-1.5, 1.5))
	loot_node.add_child(loot_instance)

	# Inițializăm proprietățile sincronizate prin rețea
	loot_instance.init_loot(unique_id, rarity, price, color)

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
		{"path": HALLWAY_SCENE.resource_path, "base_ports": [true, false, true, false], "type": "hallway"},
		{"path": CORNER_SCENE.resource_path, "base_ports": [true, true, false, false], "type": "corner"},
		{"path": T_JUNCTION_SCENE.resource_path, "base_ports": [true, true, false, true], "type": "t_junction"},
		{"path": FOUR_WAY_SCENE.resource_path, "base_ports": [true, true, true, true], "type": "four_way"},
		{"path": ROOM_SCENE.resource_path, "base_ports": [true, false, true, false], "type": "room"}
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
					"ports": rotated_ports,
					"type": item["type"]
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
