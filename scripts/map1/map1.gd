# scripts/map1/map1.gd
extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

@onready var spawn_points: Node3D = $SpawnPoints
@onready var players_node: Node3D = $Players
@onready var dungeon_generator: Node3D = $DungeonGenerator
@onready var exterior_door: StaticBody3D = $ExteriorDoor
@onready var interior_door: StaticBody3D = $InteriorDoor
@onready var back_button: Button = $CanvasLayer/Control/CenterContainer/VBox/BackButton

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	back_button.pressed.connect(_on_back_pressed)

	if multiplayer.is_server():
		# 1. Inițiază generarea dungeon-ului pe server
		if dungeon_generator:
			dungeon_generator.generate_dungeon()

			# Legăm ușa de la intrarea în dungeon (generată static în map1.tscn) cu cea din exterior
			# Configurăm legătura de teleportare între uși
			# Pentru ușa exterioară: destinația este ușa din interior (punem playerul un pic în fața ei ca să nu se blokeze)
			exterior_door.target_position = interior_door.global_position + Vector3(0, 0.5, 1.5)

			# Pentru ușa interioară: destinația este ușa din exterior (punem playerul în fața ușii de afară)
			interior_door.target_position = exterior_door.global_position + Vector3(0, 0.5, 1.5)

			# Sincronizăm coordonatele către toți clienții
			rpc("sync_door_targets", exterior_door.target_position, interior_door.target_position)

		# 2. Spawnăm toți jucătorii din lobby pe harta exterioară
		for player_id in NetworkManager.players:
			spawn_player(player_id)

func spawn_player(player_id: int) -> void:
	var player_instance = player_scene.instantiate()
	player_instance.name = str(player_id)
	player_instance.player_id = player_id

	var spawn_index: int = players_node.get_child_count() % spawn_points.get_child_count()
	var spawn_point: Marker3D = spawn_points.get_child(spawn_index)

	players_node.add_child(player_instance)
	player_instance.global_position = spawn_point.global_position

@rpc("call_local", "reliable")
func sync_door_targets(ext_target: Vector3, int_target: Vector3) -> void:
	if exterior_door:
		exterior_door.target_position = ext_target
	if interior_door:
		interior_door.target_position = int_target

# --- BACK MENU ---
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
