# scripts/dungeon/dungeon_generator.gd
extends Node3D

@export var pieces_per_floor: int = 20 # Numărul de piese per nivel/etaj
@export var max_floors: int = 3 # Numărul maxim de etaje ale dungeon-ului
@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

# Preîncărcăm piesele modulare noi (Kenney) + Entrance/DeadEnd + Loot
const ENTRANCE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/entrance_piece.tscn")
const CORRIDOR_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/corridor_piece.tscn")
const ROOM_LARGE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/room_large_piece.tscn")
const STAIRS_STRAIGHT_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/stairs_straight_piece.tscn")
const STAIRS_ZIGZAG_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/stairs_zigzag_piece.tscn")
const DEAD_END_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/dead_end_piece.tscn")
const LOOT_SCENE: PackedScene = preload("res://scenes/interactables/loot_item.tscn")

@onready var pieces_node: Node3D = $Pieces
@onready var players_node: Node3D = $Players
@onready var loot_node: Node3D = $Loot

# Piese instanțiate
var spawned_pieces: Array[Node3D] = []

# Lista AABB-urilor lumii pentru piesele deja plasate (folosite la detectarea suprapunerilor)
var placed_aabbs: Array[AABB] = []

# Structura pentru un socket deschis: { "piece": Node3D, "marker": Marker3D, "floor": int }
var open_sockets: Array[Dictionary] = []

const FLIP_180_Y: Transform3D = Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)

func _ready() -> void:
	if get_parent() == get_tree().root:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if has_node("CanvasLayer/Control/CenterContainer/VBox/BackButton"):
			$CanvasLayer/Control/CenterContainer/VBox/BackButton.pressed.connect(_on_back_pressed)

		if multiplayer.is_server():
			generate_dungeon()
			await get_tree().create_timer(0.2).timeout
			spawn_all_players()
	else:
		if has_node("CanvasLayer"):
			$CanvasLayer.queue_free()

# Obține toate nodurile Marker3D (Exits) ale unei piese instanțiate
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

# Calculează transformarea relativă a unui nod față de nodul rădăcină (fără a necesita SceneTree / global_transform)
func get_relative_transform(node: Node3D, root_node: Node3D) -> Transform3D:
	var xform = Transform3D.IDENTITY
	var curr: Node = node
	while curr != null and curr != root_node:
		if curr is Node3D:
			xform = (curr as Node3D).transform * xform
		curr = curr.get_parent()
	return xform

# Calculează AABB-ul local al unei piese combinând formele sale de coliziune, CSG-uri și Mesh-uri
func get_piece_local_aabb(piece_instance: Node3D) -> AABB:
	if piece_instance.has_meta("aabb"):
		return piece_instance.get_meta("aabb")

	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false

	var stack: Array[Node] = piece_instance.get_children()
	while not stack.is_empty():
		var node = stack.pop_back()
		stack.append_array(node.get_children())

		var node_aabb: AABB = AABB()
		var found_node_aabb: bool = false

		if node is CSGBox3D:
			var size = (node as CSGBox3D).size
			node_aabb = AABB(-size / 2.0, size)
			found_node_aabb = true
		elif node is MeshInstance3D and (node as MeshInstance3D).mesh:
			node_aabb = (node as MeshInstance3D).mesh.get_aabb()
			found_node_aabb = true
		elif node is CollisionShape3D and (node as CollisionShape3D).shape:
			var shape = (node as CollisionShape3D).shape
			if shape is BoxShape3D:
				var size = (shape as BoxShape3D).size
				node_aabb = AABB(-size / 2.0, size)
				found_node_aabb = true

		if found_node_aabb and node is Node3D:
			var local_xform: Transform3D = get_relative_transform(node as Node3D, piece_instance)
			var transformed_aabb = transform_aabb(node_aabb, local_xform)
			if not has_aabb:
				combined_aabb = transformed_aabb
				has_aabb = true
			else:
				combined_aabb = combined_aabb.merge(transformed_aabb)

	if not has_aabb:
		combined_aabb = AABB(Vector3(-5.0, 0.0, -5.0), Vector3(10.0, 4.0, 10.0))

	return combined_aabb

# Transformă un AABB folosind un Transform3D
func transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var corners = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]
	var new_aabb = AABB(xform * corners[0], Vector3.ZERO)
	for i in range(1, 8):
		new_aabb = new_aabb.expand(xform * corners[i])
	return new_aabb

# Verifică dacă două AABB-uri se suprapun având o toleranță de marjă interioară (inset)
func aabbs_intersect_inset(aabb1: AABB, aabb2: AABB, inset: float = 0.2) -> bool:
	var inset_vec = Vector3(inset, inset, inset)
	if aabb1.size.x <= 2 * inset or aabb1.size.y <= 2 * inset or aabb1.size.z <= 2 * inset:
		return aabb1.intersects(aabb2)
	if aabb2.size.x <= 2 * inset or aabb2.size.y <= 2 * inset or aabb2.size.z <= 2 * inset:
		return aabb1.intersects(aabb2)

	var shrunk1 = AABB(aabb1.position + inset_vec, aabb1.size - 2 * inset_vec)
	var shrunk2 = AABB(aabb2.position + inset_vec, aabb2.size - 2 * inset_vec)
	return shrunk1.intersects(shrunk2)

# --- GENERARE PROCEDURALĂ PE BAZĂ DE SOCKET-URI ȘI OVERLAP AABB ---
func generate_dungeon() -> void:
	print("Începe generarea procedurală Socket-to-Socket...")
	spawned_pieces.clear()
	placed_aabbs.clear()
	open_sockets.clear()

	for child in pieces_node.get_children():
		child.queue_free()

	# 1. Plasare ENTRANCE la originea lumii (0, 0, 0)
	var entrance_inst = ENTRANCE_SCENE.instantiate()
	entrance_inst.name = "Piece_Entrance"
	entrance_inst.position = Vector3.ZERO
	entrance_inst.rotation_degrees = Vector3.ZERO
	pieces_node.add_child(entrance_inst, true)
	spawned_pieces.append(entrance_inst)

	var entrance_local_aabb = get_piece_local_aabb(entrance_inst)
	var entrance_world_aabb = transform_aabb(entrance_local_aabb, entrance_inst.global_transform)
	placed_aabbs.append(entrance_world_aabb)

	for marker in get_piece_exit_markers(entrance_inst):
		open_sockets.append({
			"piece": entrance_inst,
			"marker": marker,
			"floor": 0
		})

	var available_flat_scenes = [CORRIDOR_SCENE, ROOM_LARGE_SCENE]
	var stair_scenes = [STAIRS_STRAIGHT_SCENE, STAIRS_ZIGZAG_SCENE]

	for floor_index in range(max_floors):
		var floor_piece_count = 0
		var max_attempts = pieces_per_floor * 5
		var attempts = 0

		# Generare piese orizontale pe etajul curent
		while floor_piece_count < pieces_per_floor and attempts < max_attempts:
			attempts += 1

			# Găsim un socket deschis de pe etajul curent
			var candidate_socket_indices: Array[int] = []
			for i in range(open_sockets.size()):
				if open_sockets[i]["floor"] == floor_index:
					candidate_socket_indices.append(i)

			if candidate_socket_indices.is_empty():
				break

			var target_idx = candidate_socket_indices.pick_random()
			var target_socket_data = open_sockets[target_idx]
			var target_marker: Marker3D = target_socket_data["marker"]

			var chosen_scene: PackedScene = available_flat_scenes.pick_random()
			var dummy_cand = chosen_scene.instantiate()
			var cand_markers = get_piece_exit_markers(dummy_cand)
			var cand_local_aabb = get_piece_local_aabb(dummy_cand)

			cand_markers.shuffle()
			var placed_successfully = false

			for cand_marker in cand_markers:
				# Calculăm transform-ul global al piesei candidate pentru a conecta cand_marker la target_marker
				var cand_global_xform = target_marker.global_transform * FLIP_180_Y * cand_marker.transform.inverse()
				var cand_world_aabb = transform_aabb(cand_local_aabb, cand_global_xform)

				var overlaps = false
				for placed_aabb in placed_aabbs:
					if aabbs_intersect_inset(cand_world_aabb, placed_aabb, 0.2):
						overlaps = true
						break

				if not overlaps:
					# Plasăm piesa candidată
					dummy_cand.name = "Piece_%d_%d" % [floor_index, floor_piece_count]
					dummy_cand.global_transform = cand_global_xform
					pieces_node.add_child(dummy_cand, true)

					spawned_pieces.append(dummy_cand)
					placed_aabbs.append(cand_world_aabb)
					open_sockets.remove_at(target_idx)

					# Adăugăm celelalte socket-uri deschise ale piesei candidate în coada open_sockets
					for m in cand_markers:
						if m == cand_marker:
							continue
						open_sockets.append({
							"piece": dummy_cand,
							"marker": m,
							"floor": floor_index
						})

					floor_piece_count += 1
					placed_successfully = true
					break

			if not placed_successfully:
				dummy_cand.queue_free()

		# Plasare scară către etajul următor
		if floor_index < max_floors - 1:
			var floor_socket_indices: Array[int] = []
			for i in range(open_sockets.size()):
				if open_sockets[i]["floor"] == floor_index:
					floor_socket_indices.append(i)

			floor_socket_indices.shuffle()
			var stair_placed = false

			for target_idx in floor_socket_indices:
				var target_socket_data = open_sockets[target_idx]
				var target_marker: Marker3D = target_socket_data["marker"]

				var stair_scene: PackedScene = stair_scenes.pick_random()
				var dummy_stair = stair_scene.instantiate()
				var stair_markers = get_piece_exit_markers(dummy_stair)
				var stair_local_aabb = get_piece_local_aabb(dummy_stair)

				for cand_marker in stair_markers:
					var cand_global_xform = target_marker.global_transform * FLIP_180_Y * cand_marker.transform.inverse()
					var cand_world_aabb = transform_aabb(stair_local_aabb, cand_global_xform)

					var overlaps = false
					for placed_aabb in placed_aabbs:
						if aabbs_intersect_inset(cand_world_aabb, placed_aabb, 0.2):
							overlaps = true
							break

					if not overlaps:
						dummy_stair.name = "Stairs_%d" % floor_index
						dummy_stair.global_transform = cand_global_xform
						pieces_node.add_child(dummy_stair, true)

						spawned_pieces.append(dummy_stair)
						placed_aabbs.append(cand_world_aabb)
						open_sockets.remove_at(target_idx)

						for m in stair_markers:
							if m == cand_marker:
								continue
							open_sockets.append({
								"piece": dummy_stair,
								"marker": m,
								"floor": floor_index + 1
							})

						stair_placed = true
						break

				if stair_placed:
					break
				else:
					dummy_stair.queue_free()

	# 2. Sigilăm toate socket-urile rămase deschise cu DEAD END
	_seal_all_open_sockets()

	print("Dungeon generat Socket-to-Socket cu succes! Total piese: %d" % spawned_pieces.size())

	if multiplayer.is_server():
		spawn_dungeon_loot()

# Sigilare finală a oricărei ieșiri neconectate cu o piesă de capăt
func _seal_all_open_sockets() -> void:
	var sockets_to_seal = open_sockets.duplicate()
	open_sockets.clear()

	for socket_data in sockets_to_seal:
		var target_marker: Marker3D = socket_data["marker"]
		var dead_end_inst = DEAD_END_SCENE.instantiate()
		var de_markers = get_piece_exit_markers(dead_end_inst)
		if de_markers.is_empty():
			dead_end_inst.queue_free()
			continue

		var cand_marker = de_markers[0]
		var cand_global_xform = target_marker.global_transform * FLIP_180_Y * cand_marker.transform.inverse()

		dead_end_inst.name = "Piece_DeadEnd_%d" % spawned_pieces.size()
		dead_end_inst.global_transform = cand_global_xform
		pieces_node.add_child(dead_end_inst, true)

		spawned_pieces.append(dead_end_inst)

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
			for _j in range(count):
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
	if not has_node("CanvasLayer/Control"):
		return
	if event.is_action_pressed("ui_cancel"):
		var control = get_node("CanvasLayer/Control")
		if control.visible:
			control.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			control.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
