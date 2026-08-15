# scripts/dungeon/dungeon_generator.gd
extends Node3D

@export var pieces_per_floor: int = 30 # Numărul de piese per etaj
@export var max_floors: int = 3 # 3 etaje: Floor 0, Floor 1 (deasupra), Floor -1 (dedesubt)
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

# Lista AABB-urilor lumii pentru piesele deja plasate (folosite la detectarea suprapunerilor)
var placed_aabbs: Array[AABB] = []

# Structura pentru un socket deschis: { "piece": Node3D, "marker": Marker3D, "floor": int, "type": String }
var open_sockets: Array[Dictionary] = []

# Număr de scări plasate per etaj: { floor_index: count }
var stairs_per_floor: Dictionary = {}

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
		combined_aabb = AABB(Vector3(-4.0, 0.0, -4.0), Vector3(8.0, 4.0, 8.0))

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

func aabbs_intersect_inset(aabb1: AABB, aabb2: AABB, inset: float = 0.2) -> bool:
	var inset_vec = Vector3(inset, inset, inset)
	if aabb1.size.x <= 2 * inset or aabb1.size.y <= 2 * inset or aabb1.size.z <= 2 * inset:
		return aabb1.intersects(aabb2)
	if aabb2.size.x <= 2 * inset or aabb2.size.y <= 2 * inset or aabb2.size.z <= 2 * inset:
		return aabb1.intersects(aabb2)

	var shrunk1 = AABB(aabb1.position + inset_vec, aabb1.size - 2 * inset_vec)
	var shrunk2 = AABB(aabb2.position + inset_vec, aabb2.size - 2 * inset_vec)
	return shrunk1.intersects(shrunk2)

# Încearcă plasarea unei piese dintr-o listă de piese la un socket dat
func try_place_piece_at_socket(target_idx: int, scene_pool: Array) -> bool:
	if target_idx < 0 or target_idx >= open_sockets.size():
		return false

	var socket_data = open_sockets[target_idx]
	var target_marker: Marker3D = socket_data["marker"]
	var target_type: String = socket_data["type"]
	var floor_idx: int = socket_data["floor"]

	var pool = scene_pool.duplicate()
	pool.shuffle()

	for scene in pool:
		var candidate_inst = scene.instantiate()
		var cand_markers = get_piece_exit_markers(candidate_inst)
		var cand_local_aabb = get_piece_local_aabb(candidate_inst)

		cand_markers.shuffle()

		for cand_marker in cand_markers:
			var cand_type = get_socket_type(cand_marker)
			# Potrivire strictă a tipului de socket (NARROW cu NARROW, WIDE cu WIDE)
			if cand_type != target_type:
				continue

			var cand_global_xform = target_marker.global_transform * FLIP_180_Y * cand_marker.transform.inverse()
			var cand_world_aabb = transform_aabb(cand_local_aabb, cand_global_xform)

			var overlaps = false
			for placed_aabb in placed_aabbs:
				if aabbs_intersect_inset(cand_world_aabb, placed_aabb, 0.2):
					overlaps = true
					break

			if not overlaps:
				candidate_inst.name = "Piece_%d_%d" % [floor_idx, spawned_pieces.size()]
				candidate_inst.global_transform = cand_global_xform
				pieces_node.add_child(candidate_inst, true)

				spawned_pieces.append(candidate_inst)
				placed_aabbs.append(cand_world_aabb)
				open_sockets.remove_at(target_idx)

				for m in cand_markers:
					if m == cand_marker:
						continue
					open_sockets.append({
						"piece": candidate_inst,
						"marker": m,
						"floor": floor_idx,
						"type": get_socket_type(m)
					})
				return true

		candidate_inst.queue_free()

	return false

func generate_dungeon() -> void:
	print("Începe generarea procedurală avansată pe 3 etaje...")
	spawned_pieces.clear()
	placed_aabbs.clear()
	open_sockets.clear()
	stairs_per_floor.clear()

	stairs_per_floor[0] = 0
	stairs_per_floor[1] = 0
	stairs_per_floor[-1] = 0

	for child in pieces_node.get_children():
		child.queue_free()

	# 1. PASUL 1: Plasare ENTRANCE la Etajul 0 (0, 0, 0)
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
			"floor": 0,
			"type": get_socket_type(marker)
		})

	# 2. PASUL 2: Generare TRUNCHI WIDE pe Etajul 0 (Traseu adânc/variat)
	var wide_corridors_pool = [
		CORRIDOR_WIDE_SCENE,
		CORRIDOR_WIDE_CORNER_SCENE,
		CORRIDOR_WIDE_JUNCTION_SCENE,
		CORRIDOR_WIDE_INTERSECTION_SCENE
	]

	var wide_trunk_target = 8
	var wide_trunk_count = 0
	var attempts = 0

	while wide_trunk_count < wide_trunk_target and attempts < 40:
		attempts += 1
		var wide_socket_indices: Array[int] = []
		for i in range(open_sockets.size()):
			if open_sockets[i]["floor"] == 0 and open_sockets[i]["type"] == "WIDE":
				wide_socket_indices.append(i)

		if wide_socket_indices.is_empty():
			break

		var target_idx = wide_socket_indices.pick_random()
		if try_place_piece_at_socket(target_idx, wide_corridors_pool):
			wide_trunk_count += 1

	# 3. PASUL 3: Tranziții WIDE -> NARROW pe Etajul 0 (căutare dinamică safe)
	attempts = 0
	while attempts < 30:
		attempts += 1
		var wide_socket_idx = -1
		for i in range(open_sockets.size()):
			if open_sockets[i]["floor"] == 0 and open_sockets[i]["type"] == "WIDE":
				wide_socket_idx = i
				break

		if wide_socket_idx == -1:
			break

		if not try_place_piece_at_socket(wide_socket_idx, [CORRIDOR_TRANSITION_SCENE]):
			break

	# 4. PASUL 4: Generare Piese NARROW + Camere pe Etajul 0 (până la 30 piese)
	var narrow_and_rooms_pool = [
		CORRIDOR_SCENE, CORRIDOR_CORNER_SCENE, CORRIDOR_JUNCTION_SCENE, CORRIDOR_INTERSECTION_SCENE,
		ROOM_SMALL_SCENE, ROOM_SMALL_2_SCENE, ROOM_CORNER_SCENE, ROOM_LARGE_SCENE, ROOM_LARGE_2_SCENE, ROOM_WIDE_SCENE, ROOM_WIDE_2_SCENE
	]

	var floor_0_pieces = 0
	attempts = 0
	while floor_0_pieces < pieces_per_floor and attempts < 150:
		attempts += 1
		var f0_indices: Array[int] = []
		for i in range(open_sockets.size()):
			if open_sockets[i]["floor"] == 0:
				f0_indices.append(i)

		if f0_indices.is_empty():
			break

		var target_idx = f0_indices.pick_random()
		if try_place_piece_at_socket(target_idx, narrow_and_rooms_pool):
			floor_0_pieces += 1

	# 5. PASUL 5: Plasare Scări de la Etajul 0 către Etajul 1 (sus) și Etajul -1 (jos) (maxim 2 scări pe etaj)
	var stair_scenes = [STAIRS_SCENE, STAIRS_WIDE_SCENE]
	var target_floors = [1, -1]

	for dest_floor in target_floors:
		if stairs_per_floor[0] >= 2:
			break

		var placed_stair_for_dest = false
		var attempted_socket_indices: Array[int] = []

		while not placed_stair_for_dest:
			var candidate_indices: Array[int] = []
			for i in range(open_sockets.size()):
				if open_sockets[i]["floor"] == 0 and not (i in attempted_socket_indices):
					candidate_indices.append(i)

			if candidate_indices.is_empty():
				break

			candidate_indices.shuffle()
			var target_idx = candidate_indices[0]

			var socket_data = open_sockets[target_idx]
			var target_marker: Marker3D = socket_data["marker"]
			var target_type: String = socket_data["type"]

			var placed_stair = false
			var shuffled_stairs = stair_scenes.duplicate()
			shuffled_stairs.shuffle()

			for stair_scene in shuffled_stairs:
				var stair_inst = stair_scene.instantiate()
				var stair_markers = get_piece_exit_markers(stair_inst)
				var stair_local_aabb = get_piece_local_aabb(stair_inst)

				# Pentru dest_floor == 1 (URCARE), conectorul de pe Etajul 0 trebuie să fie 'Bottom'.
				# Pentru dest_floor == -1 (COBORÂRE), conectorul de pe Etajul 0 trebuie să fie 'Top'.
				var matching_cand_markers: Array[Marker3D] = []
				for m in stair_markers:
					if get_socket_type(m) != target_type:
						continue
					if dest_floor == 1 and ("Bottom" in m.name or "bottom" in m.name):
						matching_cand_markers.append(m)
					elif dest_floor == -1 and ("Top" in m.name or "top" in m.name):
						matching_cand_markers.append(m)

				matching_cand_markers.shuffle()

				for cand_marker in matching_cand_markers:
					var cand_global_xform = target_marker.global_transform * FLIP_180_Y * cand_marker.transform.inverse()
					var cand_world_aabb = transform_aabb(stair_local_aabb, cand_global_xform)

					var overlaps = false
					for placed_aabb in placed_aabbs:
						if aabbs_intersect_inset(cand_world_aabb, placed_aabb, 0.2):
							overlaps = true
							break

					if not overlaps:
						stair_inst.name = "Stair_0_to_%d" % dest_floor
						stair_inst.global_transform = cand_global_xform
						pieces_node.add_child(stair_inst, true)

						spawned_pieces.append(stair_inst)
						placed_aabbs.append(cand_world_aabb)
						open_sockets.remove_at(target_idx)
						stairs_per_floor[0] += 1
						stairs_per_floor[dest_floor] = stairs_per_floor.get(dest_floor, 0) + 1

						for m in stair_markers:
							if m == cand_marker:
								continue
							open_sockets.append({
								"piece": stair_inst,
								"marker": m,
								"floor": dest_floor,
								"type": get_socket_type(m)
							})
						placed_stair = true
						placed_stair_for_dest = true
						break

				if placed_stair:
					break
				else:
					stair_inst.queue_free()

			if not placed_stair:
				attempted_socket_indices.append(target_idx)

	# 6. PASUL 6: Generare piese pe Etajul 1 și Etajul -1 (până la 30 piese per etaj)
	for floor_idx in [1, -1]:
		var floor_piece_count = 0
		attempts = 0
		while floor_piece_count < pieces_per_floor and attempts < 150:
			attempts += 1
			var floor_socket_indices: Array[int] = []
			for i in range(open_sockets.size()):
				if open_sockets[i]["floor"] == floor_idx:
					floor_socket_indices.append(i)

			if floor_socket_indices.is_empty():
				break

			var target_idx = floor_socket_indices.pick_random()
			# Pe etajele secundare includem și piese WIDE / Tranziție pentru a extinde scările WIDE
			var secondary_pool = [
				CORRIDOR_SCENE, CORRIDOR_CORNER_SCENE, CORRIDOR_JUNCTION_SCENE, CORRIDOR_INTERSECTION_SCENE,
				CORRIDOR_TRANSITION_SCENE, CORRIDOR_WIDE_SCENE, CORRIDOR_WIDE_CORNER_SCENE, CORRIDOR_WIDE_JUNCTION_SCENE, CORRIDOR_WIDE_INTERSECTION_SCENE,
				ROOM_SMALL_SCENE, ROOM_SMALL_2_SCENE, ROOM_CORNER_SCENE, ROOM_LARGE_SCENE, ROOM_LARGE_2_SCENE, ROOM_WIDE_SCENE, ROOM_WIDE_2_SCENE
			]
			if try_place_piece_at_socket(target_idx, secondary_pool):
				floor_piece_count += 1

	# 7. PASUL 7: Sigilare socket-uri rămase deschise cu capete de coridor
	_seal_all_open_sockets()

	print("Dungeon generat pe 3 etaje cu succes! Total piese plasate: %d" % spawned_pieces.size())

	if multiplayer.is_server():
		spawn_dungeon_loot()

# Sigilare finală
func _seal_all_open_sockets() -> void:
	var sockets_to_seal = open_sockets.duplicate()
	open_sockets.clear()

	for socket_data in sockets_to_seal:
		var target_marker: Marker3D = socket_data["marker"]
		var target_type: String = socket_data["type"]

		var dead_end_scene: PackedScene = CORRIDOR_WIDE_END_SCENE if target_type == "WIDE" else CORRIDOR_END_SCENE
		var dead_end_inst = dead_end_scene.instantiate()

		var de_markers = get_piece_exit_markers(dead_end_inst)
		if de_markers.is_empty():
			dead_end_inst.queue_free()
			continue

		var cand_marker = de_markers[0]
		var cand_global_xform = target_marker.global_transform * FLIP_180_Y * cand_marker.transform.inverse()

		dead_end_inst.name = "Piece_End_%d" % spawned_pieces.size()
		dead_end_inst.global_transform = cand_global_xform
		pieces_node.add_child(dead_end_inst, true)

		spawned_pieces.append(dead_end_inst)

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
