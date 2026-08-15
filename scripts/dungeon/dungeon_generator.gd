# scripts/dungeon/dungeon_generator.gd
extends Node3D

@export var pieces_per_floor: int = 30 # Numărul de piese per etaj
@export var max_floors: int = 3 # 3 etaje (Floor 0, Floor 1, Floor 2)
@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

# Coridoare înguste (NARROW)
const CORRIDOR_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor.tscn")
const CORRIDOR_CORNER_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_corner.tscn")
const CORRIDOR_END_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_end.tscn")
const CORRIDOR_INTERSECTION_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_intersection.tscn")
const CORRIDOR_JUNCTION_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_junction.tscn")

# Coridoare late (WIDE) & Tranziție
const CORRIDOR_TRANSITION_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_transition.tscn")
const CORRIDOR_WIDE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_wide.tscn")
const CORRIDOR_WIDE_CORNER_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_wide_corner.tscn")
const CORRIDOR_WIDE_END_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_wide_end.tscn")
const CORRIDOR_WIDE_INTERSECTION_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_wide_intersection.tscn")
const CORRIDOR_WIDE_JUNCTION_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Corridors/corridor_wide_junction.tscn")

# Camere (ROOMS) & Entrance
const ENTRANCE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Rooms/Entrance.tscn")
const ROOM_CORNER_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Rooms/room_corner.tscn")
const ROOM_LARGE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Rooms/room_large.tscn")
const ROOM_LARGE_2_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Rooms/room_large_2.tscn")
const ROOM_SMALL_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Rooms/room_small.tscn")
const ROOM_SMALL_2_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Rooms/room_small_2.tscn")
const ROOM_WIDE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Rooms/room_wide.tscn")
const ROOM_WIDE_2_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Rooms/room_wide_2.tscn")

# Scări (STAIRS)
const STAIRS_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Stairs/stairs.tscn")
const STAIRS_WIDE_SCENE: PackedScene = preload("res://scenes/dungeon/pieces/Stairs/stairs_wide.tscn")

# Loot
const LOOT_SCENE: PackedScene = preload("res://scenes/interactables/loot_item.tscn")

@onready var pieces_node: Node3D = $Pieces
@onready var players_node: Node3D = $Players
@onready var loot_node: Node3D = $Loot

# Piese instanțiate
var spawned_pieces: Array[Node3D] = []

# Bounding box-urile (AABB în coordonate globale) ale pieselor plasate
var placed_aabbs: Array[AABB] = []

# Structura pentru un socket deschis: { "piece": Node3D, "marker": Marker3D, "floor": int, "type": String }
var open_sockets: Array[Dictionary] = []

# Număr de scări plasate per etaj
var stairs_placed_count: int = 0

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

func get_socket_type(marker: Marker3D) -> String:
	if marker.has_meta("socket_type"):
		return str(marker.get_meta("socket_type"))
	if "Wide" in marker.name or "WIDE" in marker.name:
		return "WIDE"
	return "NARROW"

func get_relative_transform(node: Node3D, root_node: Node3D) -> Transform3D:
	var xform = Transform3D.IDENTITY
	var curr: Node = node
	while curr != null and curr != root_node:
		if curr is Node3D:
			xform = (curr as Node3D).transform * xform
		curr = curr.get_parent()
	return xform

func get_socket_global_transform(socket_data: Dictionary) -> Transform3D:
	var piece: Node3D = socket_data["piece"]
	var marker: Marker3D = socket_data["marker"]
	var marker_local = get_relative_transform(marker, piece)
	return piece.global_transform * marker_local

func get_piece_local_aabb(piece_instance: Node3D) -> AABB:
	if piece_instance.has_meta("aabb"):
		return piece_instance.get_meta("aabb")

	var combined_aabb: AABB = AABB()
	var has_aabb: bool = false

	var stack: Array[Node] = [piece_instance]
	while not stack.is_empty():
		var node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)

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
		combined_aabb = AABB(Vector3(-3.5, 0.0, -3.5), Vector3(7.0, 4.0, 7.0))

	return combined_aabb

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

func aabbs_intersect_inset(aabb1: AABB, aabb2: AABB, inset: float = 0.3) -> bool:
	var inset_vec = Vector3(inset, inset, inset)
	if aabb1.size.x <= 2 * inset or aabb1.size.y <= 2 * inset or aabb1.size.z <= 2 * inset:
		return aabb1.intersects(aabb2)
	if aabb2.size.x <= 2 * inset or aabb2.size.y <= 2 * inset or aabb2.size.z <= 2 * inset:
		return aabb1.intersects(aabb2)

	var shrunk1 = AABB(aabb1.position + inset_vec, aabb1.size - 2 * inset_vec)
	var shrunk2 = AABB(aabb2.position + inset_vec, aabb2.size - 2 * inset_vec)
	return shrunk1.intersects(shrunk2)

func _add_collisions_to_piece(piece_instance: Node3D) -> void:
	var stack: Array[Node] = [piece_instance]
	while not stack.is_empty():
		var current_node = stack.pop_back()
		for child in current_node.get_children():
			stack.append(child)

		if current_node is MeshInstance3D and (current_node as MeshInstance3D).mesh:
			var mesh_inst = current_node as MeshInstance3D
			mesh_inst.create_trimesh_collision()

func check_and_close_overlapping_sockets(socket_idx: int) -> bool:
	if socket_idx < 0 or socket_idx >= open_sockets.size():
		return false

	var target_data = open_sockets[socket_idx]
	var target_xform = get_socket_global_transform(target_data)
	var target_pos = target_xform.origin
	var target_fwd = -target_xform.basis.z

	for other_idx in range(open_sockets.size()):
		if other_idx == socket_idx:
			continue

		var other_data = open_sockets[other_idx]
		if other_data["type"] != target_data["type"]:
			continue

		var other_xform = get_socket_global_transform(other_data)
		var other_pos = other_xform.origin
		var other_fwd = -other_xform.basis.z

		if target_pos.distance_to(other_pos) < 1.2 and target_fwd.dot(other_fwd) < -0.7:
			var max_i = max(socket_idx, other_idx)
			var min_i = min(socket_idx, other_idx)
			open_sockets.remove_at(max_i)
			open_sockets.remove_at(min_i)
			return true

	return false

func try_place_piece_at_socket(target_idx: int, scene_pool: Array) -> bool:
	if target_idx < 0 or target_idx >= open_sockets.size():
		return false

	if check_and_close_overlapping_sockets(target_idx):
		return true

	var socket_data = open_sockets[target_idx]
	var target_xform = get_socket_global_transform(socket_data)
	var target_type: String = socket_data["type"]
	var floor_idx: int = socket_data["floor"]
	var parent_piece: Node3D = socket_data["piece"]
	var parent_is_room: bool = is_room_piece(parent_piece)

	var pool = scene_pool.duplicate()
	pool.shuffle()

	for scene in pool:
		var candidate_inst = scene.instantiate()
		var cand_is_room: bool = is_room_piece(candidate_inst)

		# REGULĂ STRICTĂ: Camerele nu se spawnează direct lângă alte camere!
		if parent_is_room and cand_is_room:
			candidate_inst.queue_free()
			continue

		var cand_markers = get_piece_exit_markers(candidate_inst)
		var cand_local_aabb = get_piece_local_aabb(candidate_inst)

		cand_markers.shuffle()

		for cand_marker in cand_markers:
			var cand_type = get_socket_type(cand_marker)
			if cand_type != target_type:
				continue

			# Dacă este scară, conectăm DOAR prin socket-ul de sus (Top) ca să coboare curat
			var is_stair = cand_is_stair_piece(candidate_inst)
			if is_stair and not ("top" in cand_marker.name.to_lower()):
				continue

			var cand_marker_local = get_relative_transform(cand_marker, candidate_inst)
			var cand_global_xform = target_xform * FLIP_180_Y * cand_marker_local.inverse()

			var cand_world_aabb = transform_aabb(cand_local_aabb, cand_global_xform)

			var overlaps = false
			for placed_aabb in placed_aabbs:
				if aabbs_intersect_inset(cand_world_aabb, placed_aabb, 0.3):
					overlaps = true
					break

			if not overlaps:
				candidate_inst.name = "Piece_%d_%d" % [floor_idx, spawned_pieces.size()]
				pieces_node.add_child(candidate_inst, true)
				candidate_inst.global_transform = cand_global_xform

				_add_collisions_to_piece(candidate_inst)

				spawned_pieces.append(candidate_inst)
				placed_aabbs.append(cand_world_aabb)
				open_sockets.remove_at(target_idx)

				# Calculăm noul floor_idx dacă piesa este o scară
				var next_floor_idx = floor_idx
				if cand_is_stair_piece(candidate_inst):
					next_floor_idx = floor_idx + 1

				for m in cand_markers:
					if m == cand_marker:
						continue
					open_sockets.append({
						"piece": candidate_inst,
						"marker": m,
						"floor": next_floor_idx,
						"type": get_socket_type(m)
					})
				return true

		candidate_inst.queue_free()

	_seal_single_socket(target_idx)
	return false

func is_room_piece(piece_inst: Node3D) -> bool:
	if not piece_inst:
		return false
	var pname = piece_inst.name.to_lower()
	var spath = piece_inst.scene_file_path.to_lower()
	return ("room" in pname or "room" in spath or "entrance" in pname or "entrance" in spath)

func cand_is_stair_piece(piece_inst: Node3D) -> bool:
	if not piece_inst:
		return false
	var pname = piece_inst.name.to_lower()
	var spath = piece_inst.scene_file_path.to_lower()
	return ("stair" in pname or "stair" in spath)

func _seal_single_socket(socket_idx: int) -> void:
	if socket_idx < 0 or socket_idx >= open_sockets.size():
		return

	var socket_data = open_sockets[socket_idx]
	var target_xform = get_socket_global_transform(socket_data)
	var target_type: String = socket_data["type"]

	var dead_end_scene: PackedScene = CORRIDOR_WIDE_END_SCENE if target_type == "WIDE" else CORRIDOR_END_SCENE
	var dead_end_inst = dead_end_scene.instantiate()

	var de_markers = get_piece_exit_markers(dead_end_inst)
	if not de_markers.is_empty():
		var cand_marker = de_markers[0]
		var cand_marker_local = get_relative_transform(cand_marker, dead_end_inst)
		var cand_global_xform = target_xform * FLIP_180_Y * cand_marker_local.inverse()
		var de_local_aabb = get_piece_local_aabb(dead_end_inst)
		var de_world_aabb = transform_aabb(de_local_aabb, cand_global_xform)

		var overlaps = false
		for placed_aabb in placed_aabbs:
			if aabbs_intersect_inset(de_world_aabb, placed_aabb, 0.3):
				overlaps = true
				break

		if not overlaps:
			dead_end_inst.name = "Piece_End_%d" % spawned_pieces.size()
			pieces_node.add_child(dead_end_inst, true)
			dead_end_inst.global_transform = cand_global_xform

			_add_collisions_to_piece(dead_end_inst)

			placed_aabbs.append(de_world_aabb)
			spawned_pieces.append(dead_end_inst)
		else:
			dead_end_inst.queue_free()
	else:
		dead_end_inst.queue_free()

	open_sockets.remove_at(socket_idx)

func generate_dungeon() -> void:
	print("Începe generarea procedurală pe socket-uri (3 Etaje cu buffer 1m)...")
	spawned_pieces.clear()
	placed_aabbs.clear()
	open_sockets.clear()
	stairs_placed_count = 0

	for child in pieces_node.get_children():
		child.queue_free()

	# 1. Plasare ENTRANCE
	var entrance_inst = ENTRANCE_SCENE.instantiate()
	entrance_inst.name = "Piece_Entrance"
	entrance_inst.position = Vector3.ZERO
	entrance_inst.rotation_degrees = Vector3.ZERO
	pieces_node.add_child(entrance_inst, true)
	_add_collisions_to_piece(entrance_inst)
	spawned_pieces.append(entrance_inst)

	var entrance_local_aabb = get_piece_local_aabb(entrance_inst)
	var entrance_world_aabb = transform_aabb(entrance_local_aabb, entrance_inst.global_transform)
	placed_aabbs.append(entrance_world_aabb)

	for marker in get_piece_exit_markers(entrance_inst):
		open_sockets.append({
			"piece": entrance_inst,
			"marker": marker,
			"floor": 0,
			"type": get_socket_type(marker)
		})

	var wide_corridors_pool = [
		CORRIDOR_WIDE_SCENE,
		CORRIDOR_WIDE_CORNER_SCENE,
		CORRIDOR_WIDE_JUNCTION_SCENE,
		CORRIDOR_WIDE_INTERSECTION_SCENE
	]

	var narrow_and_rooms_pool = [
		CORRIDOR_SCENE, CORRIDOR_CORNER_SCENE, CORRIDOR_JUNCTION_SCENE, CORRIDOR_INTERSECTION_SCENE,
		ROOM_SMALL_SCENE, ROOM_SMALL_2_SCENE, ROOM_CORNER_SCENE, ROOM_LARGE_SCENE, ROOM_LARGE_2_SCENE, ROOM_WIDE_SCENE, ROOM_WIDE_2_SCENE
	]

	# Generăm pe etaje (Floor 0 -> Floor 1 -> Floor 2)
	for current_floor in range(max_floors):
		print("--- Generare Etaj %d ---" % current_floor)

		# A. Generare trunchi WIDE pe etajul curent
		var wide_trunk_target = 4
		var wide_trunk_count = 0
		var attempts = 0

		while wide_trunk_count < wide_trunk_target and attempts < 20:
			attempts += 1
			var floor_wide_indices: Array[int] = []
			for i in range(open_sockets.size()):
				if open_sockets[i]["floor"] == current_floor and open_sockets[i]["type"] == "WIDE":
					floor_wide_indices.append(i)

			if floor_wide_indices.is_empty():
				break

			var target_idx = floor_wide_indices.pick_random()
			if try_place_piece_at_socket(target_idx, wide_corridors_pool):
				wide_trunk_count += 1

		# B. Tranziții WIDE -> NARROW pe etajul curent
		attempts = 0
		while attempts < 15:
			attempts += 1
			var wide_socket_idx = -1
			for i in range(open_sockets.size()):
				if open_sockets[i]["floor"] == current_floor and open_sockets[i]["type"] == "WIDE":
					wide_socket_idx = i
					break

			if wide_socket_idx == -1:
				break

			if not try_place_piece_at_socket(wide_socket_idx, [CORRIDOR_TRANSITION_SCENE]):
				break

		# C. Generare piese NARROW & Camere per etaj (~30 piese per etaj)
		var floor_placed_count = 0
		attempts = 0
		while floor_placed_count < pieces_per_floor and attempts < 150:
			attempts += 1

			var floor_socket_indices: Array[int] = []
			for i in range(open_sockets.size()):
				if open_sockets[i]["floor"] == current_floor:
					floor_socket_indices.append(i)

			if floor_socket_indices.is_empty():
				break

			var target_idx = floor_socket_indices.pick_random()
			if try_place_piece_at_socket(target_idx, narrow_and_rooms_pool):
				floor_placed_count += 1

		# D. Plasare Scară către etajul următor (dacă mai avem etaje de generat)
		if current_floor < max_floors - 1:
			var stair_placed = false
			attempts = 0
			while not stair_placed and attempts < 30:
				attempts += 1
				var floor_socket_indices: Array[int] = []
				for i in range(open_sockets.size()):
					if open_sockets[i]["floor"] == current_floor:
						floor_socket_indices.append(i)

				if floor_socket_indices.is_empty():
					break

				var target_idx = floor_socket_indices.pick_random()
				var stair_pool = [STAIRS_SCENE, STAIRS_WIDE_SCENE]
				if try_place_piece_at_socket(target_idx, stair_pool):
					stair_placed = true
					stairs_placed_count += 1
					print("Scară plasată de la Etajul %d la Etajul %d" % [current_floor, current_floor + 1])

	# Sigilare socket-uri rămase deschise
	_seal_all_open_sockets()

	print("Dungeon generat cu succes! Total piese plasate: %d" % spawned_pieces.size())

	if multiplayer.is_server():
		spawn_dungeon_loot()

func _seal_all_open_sockets() -> void:
	while not open_sockets.is_empty():
		_seal_single_socket(0)

# --- SPAWNING LOOT PROCEDURAL ---
func spawn_dungeon_loot() -> void:
	print("Se spawnează loot în camerele din dungeon...")
	for piece in spawned_pieces:
		if piece.name.contains("Entrance") or piece.name.contains("End") or piece.name.contains("Stair"):
			continue

		var floor_y = piece.global_position.y
		var center_pos = Vector3(piece.global_position.x, floor_y + 0.3, piece.global_position.z)

		if piece.name.contains("Room") or piece.scene_file_path.contains("room") or piece.scene_file_path.contains("Room"):
			var count = randi_range(1, 3)
			for _j in range(count):
				spawn_loot_at(center_pos)
		else:
			if randf() < 0.20:
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
	var entrance_node = pieces_node.get_node_or_null("Piece_Entrance")
	var spawn_pos = Vector3(0.0, 1.0, 0.0)
	if entrance_node:
		spawn_pos = entrance_node.global_position + Vector3(0.0, 1.0, 0.0)

	for player_id in NetworkManager.players:
		var player_instance = player_scene.instantiate()
		player_instance.name = str(player_id)
		player_instance.player_id = player_id

		players_node.add_child(player_instance)
		player_instance.global_position = spawn_pos

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
