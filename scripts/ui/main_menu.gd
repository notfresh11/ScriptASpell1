# scripts/ui/main_menu.gd
extends Control

# Preluăm referințele către nodurile panourilor din scenă
@onready var start_panel: PanelContainer = $StartPanel
@onready var join_panel: PanelContainer = $JoinPanel
@onready var lobby_panel: PanelContainer = $LobbyPanel
@onready var settings_panel: PanelContainer = $SettingsPanel

# Sub-referințe StartPanel
@onready var player_name_edit: LineEdit = $StartPanel/CenterContainer/VBoxContainer/PlayerNameEdit
@onready var create_lobby_button: Button = $StartPanel/CenterContainer/VBoxContainer/CreateLobbyButton
@onready var join_lobby_button: Button = $StartPanel/CenterContainer/VBoxContainer/JoinLobbyButton
@onready var settings_button: Button = $StartPanel/CenterContainer/VBoxContainer/SettingsButton
@onready var exit_button: Button = $StartPanel/CenterContainer/VBoxContainer/ExitButton

# Sub-referințe JoinPanel
@onready var join_ip_edit: LineEdit = $JoinPanel/CenterContainer/VBoxContainer/IPEdit
@onready var join_port_edit: LineEdit = $JoinPanel/CenterContainer/VBoxContainer/PortEdit
@onready var join_connect_button: Button = $JoinPanel/CenterContainer/VBoxContainer/ConnectButton
@onready var join_back_button: Button = $JoinPanel/CenterContainer/VBoxContainer/BackButton
@onready var join_status_label: Label = $JoinPanel/CenterContainer/VBoxContainer/StatusLabel

# Sub-referințe SettingsPanel
@onready var settings_back_button: Button = $SettingsPanel/CenterContainer/VBoxContainer/BackButton

# Sub-referințe LobbyPanel
@onready var lobby_name_edit: LineEdit = $LobbyPanel/MarginContainer/VBoxContainer/TopBar/LobbyNameEdit
@onready var lobby_conn_info: Label = $LobbyPanel/MarginContainer/VBoxContainer/TopBar/ConnectionInfo
@onready var slots_container: VBoxContainer = $LobbyPanel/MarginContainer/VBoxContainer/MainLayout/LeftPanel/SlotsContainer
@onready var ready_button: Button = $LobbyPanel/MarginContainer/VBoxContainer/MainLayout/RightPanel/ReadyButton
@onready var start_game_button: Button = $LobbyPanel/MarginContainer/VBoxContainer/MainLayout/RightPanel/StartGameButton
@onready var leave_lobby_button: Button = $LobbyPanel/MarginContainer/VBoxContainer/MainLayout/RightPanel/LeaveButton

func _ready() -> void:
	# 1. Inițializăm vizibilitatea panourilor
	show_panel(start_panel)

	# Generăm un nume implicit pentru jucător dacă nu există
	player_name_edit.text = "Player_" + str(randi_range(100, 999))
	NetworkManager.local_player_name = player_name_edit.text

	# 2. Conectăm semnalele butoanelor din StartPanel
	create_lobby_button.pressed.connect(_on_create_lobby_pressed)
	join_lobby_button.pressed.connect(_on_join_lobby_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	player_name_edit.text_changed.connect(_on_player_name_changed)

	# 3. Conectăm semnalele butoanelor din JoinPanel
	join_connect_button.pressed.connect(_on_join_connect_pressed)
	join_back_button.pressed.connect(_on_join_back_pressed)

	# 4. Conectăm semnalele butoanelor din SettingsPanel
	settings_back_button.pressed.connect(_on_settings_back_pressed)

	# 5. Conectăm semnalele butoanelor din LobbyPanel
	ready_button.pressed.connect(_on_ready_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	lobby_name_edit.text_submitted.connect(_on_lobby_name_submitted)

	# 6. Conectăm semnalele de la NetworkManager AutoLoad
	NetworkManager.lobby_created.connect(_on_network_lobby_created)
	NetworkManager.lobby_joined.connect(_on_network_lobby_joined)
	NetworkManager.lobby_join_failed.connect(_on_network_lobby_join_failed)
	NetworkManager.player_list_changed.connect(_on_network_player_list_changed)
	NetworkManager.lobby_name_changed.connect(_on_network_lobby_name_changed)

# --- PANEL NAVIGATION HELPERS ---
func show_panel(panel: PanelContainer) -> void:
	start_panel.visible = (panel == start_panel)
	join_panel.visible = (panel == join_panel)
	lobby_panel.visible = (panel == lobby_panel)
	settings_panel.visible = (panel == settings_panel)

# --- START PANEL ---
func _on_player_name_changed(new_name: String) -> void:
	if new_name.is_empty():
		NetworkManager.local_player_name = "Player"
	else:
		NetworkManager.local_player_name = new_name

func _on_create_lobby_pressed() -> void:
	NetworkManager.create_lobby()

func _on_join_lobby_pressed() -> void:
	join_status_label.text = ""
	show_panel(join_panel)

func _on_settings_pressed() -> void:
	show_panel(settings_panel)

func _on_exit_pressed() -> void:
	get_tree().quit()

# --- JOIN PANEL ---
func _on_join_connect_pressed() -> void:
	join_status_label.text = "Connecting..."
	var ip: String = join_ip_edit.text.strip_edges()
	var port: int = join_port_edit.text.to_int()
	if port <= 0:
		port = NetworkManager.DEFAULT_PORT

	NetworkManager.join_lobby(ip, port)

func _on_join_back_pressed() -> void:
	show_panel(start_panel)

# --- SETTINGS PANEL ---
func _on_settings_back_pressed() -> void:
	show_panel(start_panel)

# --- LOBBY PANEL ---
func _on_ready_pressed() -> void:
	NetworkManager.toggle_ready()

func _on_start_game_pressed() -> void:
	NetworkManager.start_game()

func _on_leave_lobby_pressed() -> void:
	NetworkManager.leave_lobby()
	show_panel(start_panel)

func _on_lobby_name_submitted(new_name: String) -> void:
	NetworkManager.change_lobby_name(new_name)

# --- NETWORKMANAGER CALLBACKS ---
func _on_network_lobby_created() -> void:
	show_panel(lobby_panel)
	lobby_name_edit.editable = true
	lobby_name_edit.text = NetworkManager.lobby_name
	start_game_button.visible = true
	# Arătăm IP-ul local host-ului pentru a-l trimite prietenilor
	var local_ip: String = NetworkManager.get_local_ip()
	lobby_conn_info.text = "Host IP: " + local_ip + " | Port: " + str(NetworkManager.DEFAULT_PORT)

func _on_network_lobby_joined() -> void:
	show_panel(lobby_panel)
	lobby_name_edit.editable = false
	start_game_button.visible = false
	lobby_conn_info.text = "Connected to Server"

func _on_network_lobby_join_failed() -> void:
	join_status_label.text = "Connection Failed!"
	show_panel(join_panel)

func _on_network_lobby_name_changed(new_name: String) -> void:
	lobby_name_edit.text = new_name

func _on_network_player_list_changed() -> void:
	# Ștergem sloturile de UI și le re-populăm pe baza NetworkManager.players
	var player_ids: Array = NetworkManager.players.keys()
	player_ids.sort() # Să păstrăm o ordine consecventă

	# Avem exact 4 sloturi pre-generate în LobbyPanel
	for i in range(4):
		var slot_node: PanelContainer = slots_container.get_node("Slot" + str(i + 1))
		var name_label: Label = slot_node.get_node("Margin/HBox/PlayerName")
		var status_label: Label = slot_node.get_node("Margin/HBox/ReadyStatus")

		if i < player_ids.size():
			var pid: int = player_ids[i]
			var p_info: Dictionary = NetworkManager.players[pid]

			# Marcăm dacă jucătorul este Host (ID == 1) sau Client
			var host_tag: String = " (Host)" if pid == 1 else ""
			name_label.text = p_info["name"] + host_tag

			if p_info["ready"]:
				status_label.text = "Ready"
				status_label.add_theme_color_override("font_color", Color.GREEN)
			else:
				status_label.text = "Not Ready"
				status_label.add_theme_color_override("font_color", Color.RED)
		else:
			name_label.text = "Empty Slot"
			status_label.text = "Waiting..."
			status_label.add_theme_color_override("font_color", Color.DARK_GRAY)

	# Gestionăm activarea butonului de Start Game (doar pentru host)
	if multiplayer.is_server():
		# Host-ul poate da start dacă toți clienții conectați sunt Ready
		var all_ready: bool = true
		for pid in NetworkManager.players:
			if pid != 1 and not NetworkManager.players[pid]["ready"]:
				all_ready = false
				break

		# Host-ul poate decide să pornească oricum (force ready), deci lăsăm butonul mereu activ,
		# dar îi dăm un feedback vizual (de exemplu, o culoare diferită sau dezactivat parțial,
		# dar în cazul nostru, utilizatorul a cerut "sau când da host ul force ready",
		# deci lăsăm Start Game mereu activ și accesibil pentru host!)
		start_game_button.disabled = false
