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

func is_corner_piece(piece_inst: Node3D) -> bool:
	if not piece_inst:
		return false
	var pname = piece_inst.name.to_lower()
	var spath = piece_inst.scene_file_path.to_lower()
	return ("corner" in pname or "corner" in spath)

func is_straight_corridor(piece_inst: Node3D) -> bool:
	if not piece_inst:
		return false
	var pname = piece_inst.name.to_lower()
	var spath = piece_inst.scene_file_path.to_lower()
	return ("corridor" in pname or "corridor" in spath) and not ("corner" in pname or "corner" in spath or "junction" in pname or "intersection" in pname or "transition" in spath)

func find_overlapping_socket_idx(target_idx: int) -> int:
	if target_idx < 0 or target_idx >= open_sockets.size():
		return -1

	var target_data = open_sockets[target_idx]
	var target_xform = get_socket_global_transform(target_data)
	var target_pos = target_xform.origin
	var target_fwd = -target_xform.basis.z

	for other_idx in range(open_sockets.size()):
		if other_idx == target_idx:
			continue

		var other_data = open_sockets[other_idx]
		if other_data["type"] != target_data["type"]:
			continue

		var other_xform = get_socket_global_transform(other_data)
		var other_pos = other_xform.origin
		var other_fwd = -other_xform.basis.z

		if target_pos.distance_to(other_pos) < 1.2 and target_fwd.dot(other_fwd) < -0.7:
			return other_idx

	return -1

func generate_floor_backtrack(current_floor: int, target_pieces: int, min_rooms: int, current_floor_piece_count: int, current_floor_room_count: int, step_info: Dictionary) -> bool:
	step_info["steps"] += 1
	if step_info["steps"] > step_info["max_steps"]:
		return false

	# BASE CASE: Target reached for this floor
	if current_floor_piece_count >= target_pieces and current_floor_room_count >= min_rooms:
		if current_floor == max_floors - 1:
			return true # All floors generated successfully!

		# Try placing TWO STAIRS IN SEQUENCE leading to current_floor + 1
		var floor_socket_indices: Array[int] = []
		for i in range(open_sockets.size()):
			if open_sockets[i]["floor"] == current_floor:
				floor_socket_indices.append(i)

		floor_socket_indices.shuffle()
		var stair_scenes = [STAIRS_SCENE, STAIRS_WIDE_SCENE]
		stair_scenes.shuffle()

		for target_idx in floor_socket_indices:
			if target_idx >= open_sockets.size():
				continue
			var socket_data = open_sockets[target_idx]
			var socket_type = socket_data["type"]
			var socket_xform = get_socket_global_transform(socket_data)

			for stair1_scene in stair_scenes:
				var stair1_inst = stair1_scene.instantiate()
				var stair1_markers = get_piece_exit_markers(stair1_inst)
				var stair1_local_aabb = get_piece_local_aabb(stair1_inst)
				var stair1_placed_and_undone = false

				for cand1_marker in stair1_markers:
					if not ("top" in cand1_marker.name.to_lower()):
						continue
					if get_socket_type(cand1_marker) != socket_type:
						continue

					var cand1_marker_local = get_relative_transform(cand1_marker, stair1_inst)
					var cand1_global_xform = socket_xform * FLIP_180_Y * cand1_marker_local.inverse()
					var cand1_world_aabb = transform_aabb(stair1_local_aabb, cand1_global_xform)

					var overlaps1 = false
					for placed_aabb in placed_aabbs:
						if aabbs_intersect_inset(cand1_world_aabb, placed_aabb, 0.3):
							overlaps1 = true
							break

					if not overlaps1:
						stair1_inst.name = "Piece_Stair1_%d_%d" % [current_floor, spawned_pieces.size()]
						pieces_node.add_child(stair1_inst, true)
						stair1_inst.global_transform = cand1_global_xform
						_add_collisions_to_piece(stair1_inst)

						spawned_pieces.append(stair1_inst)
						placed_aabbs.append(cand1_world_aabb)
						open_sockets.remove_at(target_idx)

						# Find bottom socket of Stair 1
						var stair1_bottom_marker: Marker3D = null
						for m1 in stair1_markers:
							if m1 != cand1_marker and ("bottom" in m1.name.to_lower() or "exit" in m1.name.to_lower()):
								stair1_bottom_marker = m1
								break

						if stair1_bottom_marker != null:
							var stair1_bottom_local = get_relative_transform(stair1_bottom_marker, stair1_inst)
							var stair1_bottom_xform = cand1_global_xform * stair1_bottom_local
							var stair2_type = get_socket_type(stair1_bottom_marker)

							for stair2_scene in stair_scenes:
								var stair2_inst = stair2_scene.instantiate()
								var stair2_markers = get_piece_exit_markers(stair2_inst)
								var stair2_local_aabb = get_piece_local_aabb(stair2_inst)
								var stair2_placed_and_undone = false

								for cand2_marker in stair2_markers:
									if not ("top" in cand2_marker.name.to_lower()):
										continue
									if get_socket_type(cand2_marker) != stair2_type:
										continue

									var cand2_marker_local = get_relative_transform(cand2_marker, stair2_inst)
									var cand2_global_xform = stair1_bottom_xform * FLIP_180_Y * cand2_marker_local.inverse()
									var cand2_world_aabb = transform_aabb(stair2_local_aabb, cand2_global_xform)

									var overlaps2 = false
									for placed_aabb in placed_aabbs:
										if aabbs_intersect_inset(cand2_world_aabb, placed_aabb, 0.3):
											overlaps2 = true
											break

									if not overlaps2:
										stair2_inst.name = "Piece_Stair2_%d_%d" % [current_floor, spawned_pieces.size()]
										pieces_node.add_child(stair2_inst, true)
										stair2_inst.global_transform = cand2_global_xform
										_add_collisions_to_piece(stair2_inst)

										spawned_pieces.append(stair2_inst)
										placed_aabbs.append(cand2_world_aabb)

										var new_stair_sockets: Array[Dictionary] = []
										for m2 in stair2_markers:
											if m2 == cand2_marker:
												continue
											var next_f = current_floor + 1
											var new_sock = {
												"piece": stair2_inst,
												"marker": m2,
												"floor": next_f,
												"type": get_socket_type(m2)
											}
											open_sockets.append(new_sock)
											new_stair_sockets.append(new_sock)

										stairs_placed_count += 2

										var next_floor_ok = generate_floor_backtrack(current_floor + 1, target_pieces, min_rooms, 0, 0, step_info)
										if next_floor_ok:
											return true

										# UNDO Stair 2
										stairs_placed_count -= 2
										for _s in new_stair_sockets:
											open_sockets.pop_back()
										spawned_pieces.pop_back()
										placed_aabbs.pop_back()
										pieces_node.remove_child(stair2_inst)
										stair2_inst.queue_free()
										stair2_placed_and_undone = true
										break

								if not stair2_placed_and_undone:
									stair2_inst.queue_free()

						# UNDO Stair 1
						open_sockets.insert(target_idx, socket_data)
						spawned_pieces.pop_back()
						placed_aabbs.pop_back()
						pieces_node.remove_child(stair1_inst)
						stair1_inst.queue_free()
						stair1_placed_and_undone = true
						break

				if not stair1_placed_and_undone:
					stair1_inst.queue_free()

		return false

	# FIND OPEN SOCKETS FOR CURRENT FLOOR
	var floor_socket_indices: Array[int] = []
	for i in range(open_sockets.size()):
		if open_sockets[i]["floor"] == current_floor:
			floor_socket_indices.append(i)

	if floor_socket_indices.is_empty():
		return false # Dead end before reaching piece count target

	floor_socket_indices.shuffle()

	var wide_pool = [
		CORRIDOR_WIDE_SCENE, CORRIDOR_WIDE_CORNER_SCENE,
		CORRIDOR_WIDE_JUNCTION_SCENE, CORRIDOR_WIDE_INTERSECTION_SCENE
	]

	var room_pool = [
		ROOM_SMALL_SCENE, ROOM_SMALL_2_SCENE, ROOM_CORNER_SCENE,
		ROOM_LARGE_SCENE, ROOM_LARGE_2_SCENE, ROOM_WIDE_SCENE, ROOM_WIDE_2_SCENE
	]

	for target_socket_idx in floor_socket_indices:
		if target_socket_idx >= open_sockets.size():
			continue

		var target_socket_data = open_sockets[target_socket_idx]
		var target_xform = get_socket_global_transform(target_socket_data)
		var target_type: String = target_socket_data["type"]
		var parent_piece: Node3D = target_socket_data["piece"]
		var parent_is_room: bool = is_room_piece(parent_piece)
		var parent_is_corner: bool = is_corner_piece(parent_piece)
		var parent_is_straight: bool = is_straight_corridor(parent_piece)

		# CHECK SOCKET CLOSURE WITH FACING SOCKET
		var other_socket_idx = find_overlapping_socket_idx(target_socket_idx)
		if other_socket_idx != -1:
			var socket_a = open_sockets[target_socket_idx]
			var socket_b = open_sockets[other_socket_idx]

			var max_i = max(target_socket_idx, other_socket_idx)
			var min_i = min(target_socket_idx, other_socket_idx)
			open_sockets.remove_at(max_i)
			open_sockets.remove_at(min_i)

			var closed_ok = generate_floor_backtrack(current_floor, target_pieces, min_rooms, current_floor_piece_count, current_floor_room_count, step_info)
			if closed_ok:
				return true

			# UNDO socket closure
			open_sockets.insert(min_i, socket_b if min_i == other_socket_idx else socket_a)
			open_sockets.insert(max_i, socket_a if max_i == target_socket_idx else socket_b)

		# BUILD CANDIDATE POOL FOR THIS SOCKET
		var candidate_scenes: Array = []

		if target_type == "WIDE":
			if current_floor == 0:
				candidate_scenes = [CORRIDOR_WIDE_SCENE, CORRIDOR_WIDE_SCENE, CORRIDOR_WIDE_JUNCTION_SCENE, CORRIDOR_WIDE_CORNER_SCENE, CORRIDOR_TRANSITION_SCENE]
			else:
				candidate_scenes = [CORRIDOR_TRANSITION_SCENE, CORRIDOR_WIDE_SCENE, CORRIDOR_WIDE_CORNER_SCENE]
			candidate_scenes.shuffle()
		else:
			# NARROW socket
			var straight_corridors = [CORRIDOR_SCENE, CORRIDOR_SCENE, CORRIDOR_SCENE]
			var junctions = [CORRIDOR_JUNCTION_SCENE, CORRIDOR_INTERSECTION_SCENE]
			var corners = [CORRIDOR_CORNER_SCENE]
			var rooms = room_pool.duplicate()

			straight_corridors.shuffle()
			junctions.shuffle()
			rooms.shuffle()

			if current_floor_room_count < min_rooms:
				candidate_scenes = rooms + straight_corridors + junctions + corners
			elif parent_is_straight:
				candidate_scenes = straight_corridors + junctions + rooms + corners
			else:
				candidate_scenes = straight_corridors + junctions + corners + rooms

		for scene in candidate_scenes:
			var cand_inst = scene.instantiate()
			var cand_is_room: bool = is_room_piece(cand_inst)

			# REGULĂ STRICTĂ 1: Camerele nu se spawnează direct lângă alte camere!
			if parent_is_room and cand_is_room:
				cand_inst.queue_free()
				continue

			# REGULĂ STRICTĂ 2: Colțurile nu se spawnează direct lângă alte colțuri!
			if parent_is_corner and is_corner_piece(cand_inst):
				cand_inst.queue_free()
				continue

			var cand_markers = get_piece_exit_markers(cand_inst)
			var cand_local_aabb = get_piece_local_aabb(cand_inst)
			cand_markers.shuffle()

			var placed_and_undone = false

			for cand_marker in cand_markers:
				if get_socket_type(cand_marker) != target_type:
					continue

				if cand_is_stair_piece(cand_inst) and not ("top" in cand_marker.name.to_lower()):
					continue

				var cand_marker_local = get_relative_transform(cand_marker, cand_inst)
				var cand_global_xform = target_xform * FLIP_180_Y * cand_marker_local.inverse()
				var cand_world_aabb = transform_aabb(cand_local_aabb, cand_global_xform)

				var overlaps = false
				for placed_aabb in placed_aabbs:
					if aabbs_intersect_inset(cand_world_aabb, placed_aabb, 0.3):
						overlaps = true
						break

				if not overlaps:
					cand_inst.name = "Piece_%d_%d" % [current_floor, spawned_pieces.size()]
					pieces_node.add_child(cand_inst, true)
					cand_inst.global_transform = cand_global_xform
					_add_collisions_to_piece(cand_inst)

					spawned_pieces.append(cand_inst)
					placed_aabbs.append(cand_world_aabb)
					open_sockets.remove_at(target_socket_idx)

					var new_sockets_added: Array[Dictionary] = []
					for m in cand_markers:
						if m == cand_marker:
							continue
						var new_sock = {
							"piece": cand_inst,
							"marker": m,
							"floor": current_floor,
							"type": get_socket_type(m)
						}
						open_sockets.append(new_sock)
						new_sockets_added.append(new_sock)

					var is_room = cand_is_room and not cand_is_stair_piece(cand_inst)

					var success = generate_floor_backtrack(
						current_floor,
						target_pieces,
						min_rooms,
						current_floor_piece_count + 1,
						current_floor_room_count + (1 if is_room else 0),
						step_info
					)

					if success:
						return true

					# BACKTRACK PIECE
					for _s in new_sockets_added:
						open_sockets.pop_back()

					open_sockets.insert(target_socket_idx, target_socket_data)
					spawned_pieces.pop_back()
					placed_aabbs.pop_back()
					pieces_node.remove_child(cand_inst)
					cand_inst.queue_free()
					placed_and_undone = true
					break

			if not placed_and_undone:
				cand_inst.queue_free()

	return false

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

		dead_end_inst.name = "Piece_End_%d" % spawned_pieces.size()
		pieces_node.add_child(dead_end_inst, true)
		dead_end_inst.global_transform = cand_global_xform

		_add_collisions_to_piece(dead_end_inst)

		var de_local_aabb = get_piece_local_aabb(dead_end_inst)
		var de_world_aabb = transform_aabb(de_local_aabb, cand_global_xform)
		placed_aabbs.append(de_world_aabb)
		spawned_pieces.append(dead_end_inst)
	else:
		dead_end_inst.queue_free()

	open_sockets.remove_at(socket_idx)

func _seal_all_open_sockets() -> void:
	while not open_sockets.is_empty():
		_seal_single_socket(0)

func generate_dungeon() -> void:
	print("Începe generarea procedurală cu Backtracking (3 Etaje x ~%d piese, min 3-4 camere/etaj)..." % pieces_per_floor)

	var attempts = 0
	var success = false

	while attempts < 5 and not success:
		attempts += 1
		print("Attempt %d / 5..." % attempts)

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

		var step_info = { "steps": 0, "max_steps": 3000 }
		success = generate_floor_backtrack(0, pieces_per_floor, 3, 0, 0, step_info)

	if success:
		_seal_all_open_sockets()
		print("Dungeon generat cu succes prin Backtracking! Total piese plasate: %d" % spawned_pieces.size())
	else:
		print("WARNING: Backtracking-ul a finalizat parțial. Se sigilează structura curentă...")
		_seal_all_open_sockets()

	if multiplayer.is_server():
		spawn_dungeon_loot()

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
