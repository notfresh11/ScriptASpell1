# scripts/ui/testing_platform.gd
extends Node3D

@export var player_scene: PackedScene = preload("res://scenes/player/explorer_player.tscn")

@onready var spawn_points: Node3D = $SpawnPoints
@onready var players_node: Node3D = $Players
@onready var back_button: Button = $CanvasLayer/Control/CenterContainer/VBox/BackButton
@onready var red_platform: Area3D = $RedPlatform
@onready var expedition_label: Label = $CanvasLayer/LobbyTrackerContainer/Panel/Margin/ExpeditionLabel

# Set de jucători prezenți pe platforma roșie (ID-uri)
var players_on_platform: Array[int] = []

func _ready() -> void:
	# Eliberăm cursorul mouse-ului la încărcarea scenei
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Doar serverul (Host) se ocupă de spawnarea fizică a jucătorilor în rețea
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_player_connected)
		multiplayer.peer_disconnected.connect(_on_player_disconnected)

		# Conectăm semnalele de detecție pentru platforma roșie pe server
		red_platform.body_entered.connect(_on_platform_body_entered)
		red_platform.body_exited.connect(_on_platform_body_exited)

		# Spawnăm jucătorii care sunt deja conectați
		for player_id in NetworkManager.players:
			spawn_player(player_id)

		# Actualizăm statusul inițial
		update_tracker_ui()

	back_button.pressed.connect(_on_back_pressed)

func spawn_player(player_id: int) -> void:
	var player_instance = player_scene.instantiate()
	player_instance.name = str(player_id)
	player_instance.player_id = player_id

	# Determinăm punctul de spawn (pe rând pentru fiecare player)
	var spawn_index: int = players_node.get_child_count() % spawn_points.get_child_count()
	var spawn_point: Marker3D = spawn_points.get_child(spawn_index)

	# Adăugăm mai întâi nodul în arbore pentru a evita avertismentul global_position !is_inside_tree()
	players_node.add_child(player_instance, true)
	player_instance.global_position = spawn_point.global_position

func _on_player_connected(id: int) -> void:
	spawn_player(id)
	if multiplayer.is_server():
		update_tracker_ui()

func _on_player_disconnected(id: int) -> void:
	if players_node.has_node(str(id)):
		players_node.get_node(str(id)).queue_free()

	if multiplayer.is_server():
		players_on_platform.erase(id)
		update_tracker_ui()

# --- RED PLATFORM DETECTION (SERVER ONLY) ---
func _on_platform_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if body.has_method("get_multiplayer_authority"):
		var p_id: int = body.player_id
		if not p_id in players_on_platform:
			players_on_platform.append(p_id)
			update_tracker_ui()
			check_for_expedition_start()

func _on_platform_body_exited(body: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if body.has_method("get_multiplayer_authority"):
		var p_id: int = body.player_id
		players_on_platform.erase(p_id)
		update_tracker_ui()

func update_tracker_ui() -> void:
	var ready_count: int = players_on_platform.size()
	var total_count: int = NetworkManager.players.size()
	rpc("sync_tracker_ui", ready_count, total_count)

@rpc("call_local", "reliable")
func sync_tracker_ui(ready_count: int, total_count: int) -> void:
	if expedition_label:
		if ready_count == total_count and total_count > 0:
			expedition_label.text = "All players ready! Initializing procedural dungeon..."
			expedition_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			expedition_label.text = "Step on the Red Platform to start Expedition (%d/%d players ready)" % [ready_count, total_count]
			expedition_label.add_theme_color_override("font_color", Color.RED)

func check_for_expedition_start() -> void:
	var ready_count: int = players_on_platform.size()
	var total_count: int = NetworkManager.players.size()

	if ready_count == total_count and total_count > 0:
		# Așteptăm o secundă pentru feedback vizual înainte de tranziție
		await get_tree().create_timer(1.5).timeout
		# Deconectăm semnalele pentru a nu repeta apelul în timpul tranziției
		if red_platform.body_entered.is_connected(_on_platform_body_entered):
			red_platform.body_entered.disconnect(_on_platform_body_entered)

		rpc("load_procedural_dungeon")

@rpc("call_local", "reliable")
func load_procedural_dungeon() -> void:
	get_tree().change_scene_to_file("res://scenes/dungeon/dungeon_generator.tscn")

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
