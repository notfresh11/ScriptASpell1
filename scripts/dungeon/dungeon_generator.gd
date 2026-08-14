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

# Piese instanțiate
var spawned_pieces: Array[Node3D] = []

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

# --- DETECTARE DINAMICĂ MARKER3D (SOCKET-URI) ---
# Inspectează dinamic nodul "Exits" sau copiii de tip Marker3D ai piesei.
# Dacă un utilizator șterge un Marker3D din editor (deoarece ieșirea era în perete),
# acesta nu va mai fi găsit în lista de ieșiri active!
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

# Verificare suprapunere fizică (Overlap Check):
# Căutăm dacă centrul piesei noi este prea aproape de piesele existente
func check_piece_overlap(new_pos: Vector3) -> bool:
	for existing in spawned_pieces:
		if new_pos.distance_to(existing.global_position) < 7.0:
			return true
	return false

# --- ALGORITMUL DE GENERARE PROCEDURALĂ BAZAT PE SOCKET-URI ---
func generate_dungeon() -> void:
	print("Începe generarea procedurală a dungeon-ului (Sistem bazat pe Socket-uri / Marker3D)...")

	spawned_pieces.clear()

	# Coadă pentru ieșiri deschise (Open Exits Queue)
	# Element: { "global_transform": Transform3D, "depth": int }
	var open_exits: Array[Dictionary] = []

	# 1. Instanțiem Piesa de Intrare (Entrance) la originea dungeon-ului (0, 0, 0)
	var entrance_instance: Node3D = ENTRANCE_SCENE.instantiate()
	entrance_instance.name = "Piece_Entrance"
	entrance_instance.transform = Transform3D.IDENTITY
	pieces_node.add_child(entrance_instance, true)
	spawned_pieces.append(entrance_instance)

	# Extragere ieșiri disponibile de pe Piesa de Intrare
	for marker in get_piece_exit_markers(entrance_instance):
		var marker_global_transform = entrance_instance.global_transform * marker.transform
		open_exits.append({
			"global_transform": marker_global_transform,
			"depth": 1
		})

	# Pool-ul de piese disponibile pentru construcție
	var normal_pieces = [
		HALLWAY_SCENE,
		CORNER_SCENE,
		T_JUNCTION_SCENE,
		FOUR_WAY_SCENE,
		ROOM_SCENE
	]

	# 2. Procesăm coada de ieșiri deschise (Open Exits Queue)
	while not open_exits.is_empty() and spawned_pieces.size() < max_main_pieces:
		var current_exit = open_exits.pop_front()
		var parent_exit_transform: Transform3D = current_exit["global_transform"]
		var parent_exit_pos: Vector3 = parent_exit_transform.origin
		var parent_exit_dir: Vector3 = -parent_exit_transform.basis.z.normalized()
		var depth: int = current_exit["depth"]

		normal_pieces.shuffle()
		var piece_placed = false

		for scene in normal_pieces:
			var candidate_instance: Node3D = scene.instantiate()
			var candidate_sockets = get_piece_exit_markers(candidate_instance)

			if candidate_sockets.is_empty():
				candidate_instance.queue_free()
				continue

			candidate_sockets.shuffle()

			# Încercăm potrivirea pe fiecare socket de intrare posibil al piese de testat
			for s_in in candidate_sockets:
				var target_dir = -parent_exit_dir
				var local_dir = -s_in.transform.basis.z.normalized()

				var angle = Vector2(local_dir.x, local_dir.z).angle_to(Vector2(target_dir.x, target_dir.z))
				var child_basis = Basis(Vector3.UP, angle)
				var child_pos = parent_exit_pos - child_basis * s_in.position

				if check_piece_overlap(child_pos):
					continue

				# Piesa se potrivește perfect fără suprapunere!
				candidate_instance.name = "Piece_%d" % spawned_pieces.size()
				candidate_instance.position = child_pos
				candidate_instance.basis = child_basis

				# Adăugăm piesa cu transformarea deja setată corect pentru sincronizare în rețea
				pieces_node.add_child(candidate_instance, true)
				spawned_pieces.append(candidate_instance)
				piece_placed = true

				# Înregistrăm restul de ieșiri deschise ale piesei proaspăt plasate
				for s_out in candidate_sockets:
					if s_out == s_in:
						continue
					var s_out_global_basis = child_basis * s_out.transform.basis
					var s_out_global_pos = child_pos + child_basis * s_out.position
					var s_out_global_transform = Transform3D(s_out_global_basis, s_out_global_pos)
					open_exits.append({
						"global_transform": s_out_global_transform,
						"depth": depth + 1
					})
				break

			if piece_placed:
				break
			else:
				candidate_instance.queue_free()

		# Dacă nicio piesă normală nu s-a putut potrivi pe ieșire, sigilăm cu Dead End
		if not piece_placed:
			_seal_exit_with_dead_end(parent_exit_transform)

	# 3. Sigilăm toate ieșirile rămase neconectate în coadă cu piese Dead End
	for remaining in open_exits:
		var parent_exit_transform: Transform3D = remaining["global_transform"]
		_seal_exit_with_dead_end(parent_exit_transform)

	print("Dungeon generat cu succes! Total piese plasate pe socket-uri: ", spawned_pieces.size())

	if multiplayer.is_server():
		spawn_dungeon_loot()

# Sigilare fizică pe nodul Marker3D cu verificare de suprapunere:
func _seal_exit_with_dead_end(parent_exit_transform: Transform3D) -> void:
	var dead_end_instance: Node3D = DEAD_END_SCENE.instantiate()
	var sockets = get_piece_exit_markers(dead_end_instance)

	if sockets.is_empty():
		dead_end_instance.queue_free()
		return

	var s_in = sockets[0]
	var parent_exit_pos: Vector3 = parent_exit_transform.origin
	var parent_exit_dir: Vector3 = -parent_exit_transform.basis.z.normalized()

	var target_dir = -parent_exit_dir
	var local_dir = -s_in.transform.basis.z.normalized()

	var angle = Vector2(local_dir.x, local_dir.z).angle_to(Vector2(target_dir.x, target_dir.z))
	var child_basis = Basis(Vector3.UP, angle)
	var child_pos = parent_exit_pos - child_basis * s_in.position

	if check_piece_overlap(child_pos):
		dead_end_instance.queue_free()
		return

	dead_end_instance.name = "Piece_DeadEnd_%d" % spawned_pieces.size()
	dead_end_instance.position = child_pos
	dead_end_instance.basis = child_basis

	pieces_node.add_child(dead_end_instance, true)
	spawned_pieces.append(dead_end_instance)

# --- SPAWNING LOOT PROCEDURAL ---
func spawn_dungeon_loot() -> void:
	print("Se spawnează loot în piese...")
	for piece in spawned_pieces:
		if piece.name.contains("Entrance") or piece.name.contains("DeadEnd"):
			continue

		var center_pos = piece.global_position + Vector3(0, 0.5, 0)

		if piece.name.contains("Room") or piece.scene_file_path.contains("room"):
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
