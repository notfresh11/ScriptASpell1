# scripts/dungeon/dungeon_generator.gd
extends Node3D

@export var max_floors: int = 3 # Numărul de etaje verticale ale dungeon-ului
@export var pieces_per_floor: int = 10 # Numărul de piese de pe FIECARE etaj orizontal
@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

# Ponderi de plasare tweakabile din Inspector
@export_group("Piece Weights")
@export var hallway_weight: float = 35.0
@export var corner_weight: float = 25.0
@export var t_junction_weight: float = 15.0
@export var four_way_weight: float = 10.0
@export var room_weight: float = 20.0

@export_group("Loop Settings")
@export var loop_chance: float = 0.15 # 15% șansă de a forma buclă/circuit dacă 2 ieșiri se întâlnesc

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

# Verificare suprapunere fizică (Overlap Check pe distanță 3D)
func check_piece_overlap(new_pos: Vector3) -> bool:
	for existing in spawned_pieces:
		# Verificăm dacă suntem pe același etaj Y (diferență Y < 4.0m) și la distanță 2D < 7.0m
		var y_diff = abs(new_pos.y - existing.global_position.y)
		if y_diff < 4.0:
			var pos_2d_new = Vector2(new_pos.x, new_pos.z)
			var pos_2d_existing = Vector2(existing.global_position.x, existing.global_position.z)
			if pos_2d_new.distance_to(pos_2d_existing) < 7.0:
				return true
	return false

# Selecție ponderată
func select_weighted_horizontal_scene(candidates: Array, depth_ratio: float) -> PackedScene:
	if candidates.is_empty():
		return null
	var total_w = 0.0
	var weights = []
	for sc in candidates:
		var w = 10.0
		if sc == HALLWAY_SCENE: w = lerp(hallway_weight * 1.5, hallway_weight * 0.5, depth_ratio)
		elif sc == CORNER_SCENE: w = corner_weight
		elif sc == T_JUNCTION_SCENE: w = lerp(t_junction_weight * 0.5, t_junction_weight * 1.5, depth_ratio)
		elif sc == FOUR_WAY_SCENE: w = lerp(four_way_weight * 0.3, four_way_weight * 1.8, depth_ratio)
		elif sc == ROOM_SCENE: w = lerp(room_weight * 0.2, room_weight * 2.5, depth_ratio)
		weights.append(w)
		total_w += w

	var roll = randf() * total_w
	var accum = 0.0
	for i in range(candidates.size()):
		accum += weights[i]
		if roll <= accum:
			return candidates[i]
	return candidates[0]

# --- ALGORITMUL DE GENERARE STRUCTURATĂ PE ETAJE (DESCENDENT) ---
func generate_dungeon() -> void:
	print("Începe generarea procedurală pe etaje (%d etaje, %d piese/etaj)..." % [max_floors, pieces_per_floor])

	spawned_pieces.clear()

	for child in pieces_node.get_children():
		child.queue_free()

	# Piesa de Intrare (Entrance) rămâne FIXĂ sus la (0, 0, 0)
	var entrance_instance: Node3D = ENTRANCE_SCENE.instantiate()
	entrance_instance.name = "Piece_Entrance"
	entrance_instance.position = Vector3.ZERO
	entrance_instance.rotation_degrees = Vector3.ZERO
	pieces_node.add_child(entrance_instance, true)
	spawned_pieces.append(entrance_instance)

	var current_open_exit: Dictionary = {}
	var entrance_markers = get_piece_exit_markers(entrance_instance)
	if not entrance_markers.is_empty():
		current_open_exit = {
			"global_transform": entrance_instance.global_transform * entrance_markers[0].transform
		}

	var horizontal_scenes = [HALLWAY_SCENE, CORNER_SCENE, T_JUNCTION_SCENE, FOUR_WAY_SCENE, ROOM_SCENE]
	var stair_scenes = [STAIRS_STRAIGHT_SCENE, STAIRS_ZIGZAG_SCENE]

	# Generăm fiecare etaj în parte
	for floor_idx in range(max_floors):
		print("--- Generare Etaj %d ---" % (floor_idx + 1))
		var floor_exits_queue: Array[Dictionary] = []
		if not current_open_exit.is_empty():
			floor_exits_queue.append(current_open_exit)

		var floor_piece_count = 0

		# 1. Generăm piesele orizontale ale etajului curent
		while not floor_exits_queue.is_empty() and floor_piece_count < pieces_per_floor:
			var exit_info = floor_exits_queue.pop_front()
			var exit_trans: Transform3D = exit_info["global_transform"]
			var exit_pos: Vector3 = exit_trans.origin
			var exit_dir: Vector3 = -exit_trans.basis.z.normalized()

			var depth_ratio = float(floor_piece_count) / float(pieces_per_floor)
			var candidates = horizontal_scenes.duplicate()
			var piece_placed = false

			while not candidates.is_empty() and not piece_placed:
				var scene = select_weighted_horizontal_scene(candidates, depth_ratio)
				candidates.erase(scene)

				var cand_inst = scene.instantiate()
				var sockets = get_piece_exit_markers(cand_inst)

				if sockets.is_empty():
					cand_inst.queue_free()
					continue

				sockets.shuffle()

				for s_in in sockets:
					var target_dir = -exit_dir
					var local_dir = -s_in.transform.basis.z.normalized()

					var angle = Vector2(local_dir.x, local_dir.z).angle_to(Vector2(target_dir.x, target_dir.z))
					var child_basis = Basis(Vector3.UP, angle)
					var child_pos = exit_pos - child_basis * s_in.position

					if check_piece_overlap(child_pos):
						continue

					# Plasare reușită pe etaj!
					cand_inst.name = "Piece_Floor%d_%d" % [floor_idx, spawned_pieces.size()]
					cand_inst.position = child_pos
					cand_inst.basis = child_basis

					pieces_node.add_child(cand_inst, true)
					spawned_pieces.append(cand_inst)
					piece_placed = true
					floor_piece_count += 1

					for s_out in sockets:
						if s_out == s_in:
							continue
						var out_basis = child_basis * s_out.transform.basis
						var out_pos = child_pos + child_basis * s_out.position
						floor_exits_queue.append({
							"global_transform": Transform3D(out_basis, out_pos)
						})
					break

				if piece_placed:
					break
				else:
					cand_inst.queue_free()

			if not piece_placed and not floor_exits_queue.is_empty():
				_seal_exit_with_dead_end(exit_trans)

		# 2. Dacă nu este ultimul etaj, adăugăm OBLIGATORIU o scară care coboară (-6m Y mai jos) spre etajul următor
		if floor_idx < max_floors - 1 and not floor_exits_queue.is_empty():
			var stair_exit_info = floor_exits_queue.pop_front()
			var exit_trans: Transform3D = stair_exit_info["global_transform"]

			stair_scenes.shuffle()
			var stair_placed = false

			for stair_scene in stair_scenes:
				var stair_inst = stair_scene.instantiate()
				var sockets = get_piece_exit_markers(stair_inst)

				# Socket-ul de sus/intrare al scării este Exit_South la Y=0.0m (sockets[1])
				var s_in = sockets[1] if sockets.size() > 1 else sockets[0]
				var target_dir = -(-exit_trans.basis.z.normalized())
				var local_dir = -s_in.transform.basis.z.normalized()

				var angle = Vector2(local_dir.x, local_dir.z).angle_to(Vector2(target_dir.x, target_dir.z))
				var child_basis = Basis(Vector3.UP, angle)
				var child_pos = exit_trans.origin - child_basis * s_in.position

				if check_piece_overlap(child_pos):
					stair_inst.queue_free()
					continue

				stair_inst.name = "Piece_Stair_Floor%d" % floor_idx
				stair_inst.position = child_pos
				stair_inst.basis = child_basis

				pieces_node.add_child(stair_inst, true)
				spawned_pieces.append(stair_inst)
				stair_placed = true

				# Ieșirea de jos a scării (Exit_North la Y=-6.0m) devine punctul de pornire pentru etajul următor!
				var s_out = sockets[0]
				var out_basis = child_basis * s_out.transform.basis
				var out_pos = child_pos + child_basis * s_out.position

				current_open_exit = {
					"global_transform": Transform3D(out_basis, out_pos)
				}
				break

			if not stair_placed and not floor_exits_queue.is_empty():
				current_open_exit = floor_exits_queue.pop_front()

		# Sigilăm restul de ieșiri nefolosite de pe acest etaj cu Dead End-uri
		for remaining in floor_exits_queue:
			_seal_exit_with_dead_end(remaining["global_transform"])

	print("Dungeon generat cu succes descendent pe %d etaje! Total piese: %d" % [max_floors, spawned_pieces.size()])

	if multiplayer.is_server():
		spawn_dungeon_loot()

# Sigilare fizică pe nodul Marker3D
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

# --- SPAWNING LOOT PROCEDURAL AȘEZAT PE PODEA ---
func spawn_dungeon_loot() -> void:
	print("Se spawnează loot pe podeaua pieselor...")
	for piece in spawned_pieces:
		if piece.name.contains("Entrance") or piece.name.contains("DeadEnd") or piece.name.contains("Stair"):
			continue

		# Poziționăm loot-ul raportat la înălțimea Y a podelei piesei curente!
		var floor_y = piece.global_position.y
		var center_pos = Vector3(piece.global_position.x, floor_y + 0.3, piece.global_position.z)

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

	# Offset fin pe XZ pe podea
	var spawn_p = pos + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
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
