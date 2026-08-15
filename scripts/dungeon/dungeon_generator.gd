# scripts/dungeon/dungeon_generator.gd
extends DungeonGenerator3D

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

@onready var players_node: Node3D = $Players
@onready var loot_node: Node3D = $Loot

func _ready() -> void:
	super._ready()
	done_generating.connect(_on_done_generating)

	if get_parent() == get_tree().root:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if has_node("CanvasLayer/Control/CenterContainer/VBox/BackButton"):
			$CanvasLayer/Control/CenterContainer/VBox/BackButton.pressed.connect(_on_back_pressed)

		if multiplayer.is_server():
			generate_dungeon()
	else:
		if has_node("CanvasLayer"):
			$CanvasLayer.queue_free()

func create_or_recreate_rooms_container() -> void:
	super.create_or_recreate_rooms_container()
	if rooms_container and not rooms_container.is_inside_tree():
		add_child(rooms_container)
	if has_node("PieceSpawner") and rooms_container:
		$PieceSpawner.spawn_path = rooms_container.get_path()

func generate_dungeon() -> void:
	print("Începe generarea procedurală SimpleDungeons...")
	generate_on_ready = false
	voxel_scale = Vector3(10, 4, 10)
	dungeon_size = Vector3i(10, 3, 10)
	corridor_room_scene = CORRIDOR_INTERSECTION_SCENE
	room_scenes = [
		ENTRANCE_SCENE,
		ROOM_SMALL_SCENE,
		ROOM_SMALL_2_SCENE,
		ROOM_CORNER_SCENE,
		ROOM_LARGE_SCENE,
		ROOM_LARGE_2_SCENE,
		ROOM_WIDE_SCENE,
		ROOM_WIDE_2_SCENE,
		STAIRS_SCENE,
		STAIRS_WIDE_SCENE,
		CORRIDOR_SCENE,
		CORRIDOR_CORNER_SCENE,
		CORRIDOR_WIDE_SCENE
	]

	generate()

func _on_done_generating() -> void:
	print("SimpleDungeons a finalizat generarea dungeon-ului!")
	if multiplayer.is_server():
		spawn_dungeon_loot()
		if get_parent() == get_tree().root:
			await get_tree().create_timer(0.2).timeout
			spawn_all_players()

func get_entrance_position() -> Vector3:
	if rooms_container:
		for room in rooms_container.get_children():
			if "Entrance" in room.name or "Entrance" in room.scene_file_path or "entrance" in room.name.to_lower():
				return room.global_position
		if rooms_container.get_child_count() > 0:
			return rooms_container.get_child(0).global_position
	return Vector3.ZERO

# --- SPAWNING LOOT PROCEDURAL ---
func spawn_dungeon_loot() -> void:
	if not multiplayer.is_server():
		return
	print("Se spawnează loot în camerele din dungeon...")
	if not rooms_container:
		return

	for room in rooms_container.get_children():
		if not room is DungeonRoom3D:
			continue
		var room_name_lower = room.name.to_lower()
		if "entrance" in room_name_lower or "stair" in room_name_lower or "corridor" in room_name_lower:
			continue

		var center_pos = room.global_position + Vector3(0, 0.5, 0)
		var count = randi_range(1, 3) if "room" in room_name_lower else 1
		for _j in range(count):
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
	var spawn_pos = get_entrance_position() + Vector3(0.0, 1.0, 0.0)

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
