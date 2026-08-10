# scripts/ui/testing_platform.gd
extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

@onready var spawn_points: Node3D = $SpawnPoints
@onready var players_node: Node3D = $Players
@onready var back_button: Button = $CanvasLayer/Control/BackButton

func _ready() -> void:
	# Eliberăm cursorul mouse-ului la încărcarea scenei
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Doar serverul (Host) se ocupă de spawnarea fizică a jucătorilor în rețea
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_player_connected)
		multiplayer.peer_disconnected.connect(_on_player_disconnected)

		# Spawnăm jucătorii care sunt deja conectați
		for player_id in NetworkManager.players:
			spawn_player(player_id)

	# Permitem oricărui jucător să iasă înapoi la meniu apăsând tasta ESC / sau folosind un buton pe ecran
	back_button.pressed.connect(_on_back_pressed)

func spawn_player(player_id: int) -> void:
	var player_instance = player_scene.instantiate()
	player_instance.name = str(player_id)
	player_instance.player_id = player_id

	# Determinăm punctul de spawn (pe rând pentru fiecare player)
	var spawn_index: int = players_node.get_child_count() % spawn_points.get_child_count()
	var spawn_point: Marker3D = spawn_points.get_child(spawn_index)
	player_instance.global_position = spawn_point.global_position

	players_node.add_child(player_instance)

func _on_player_connected(id: int) -> void:
	spawn_player(id)

func _on_player_disconnected(id: int) -> void:
	if players_node.has_node(str(id)):
		players_node.get_node(str(id)).queue_free()

func _on_back_pressed() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.leave_lobby()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _input(event: InputEvent) -> void:
	# Apăsare ESC pentru a arăta/ascunde butonul de Back din meniul de test 3D
	if event.is_action_pressed("ui_cancel"):
		if $CanvasLayer/Control.visible:
			$CanvasLayer/Control.hide()
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			$CanvasLayer/Control.show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
