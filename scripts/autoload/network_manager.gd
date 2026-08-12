# scripts/autoload/network_manager.gd
extends Node

# Semnale pentru notificarea UI-ului
signal lobby_created()
signal lobby_joined()
signal lobby_join_failed()
signal player_list_changed()
signal lobby_name_changed(new_name: String)
signal game_started()

const DEFAULT_PORT: int = 9999
const MAX_PLAYERS: int = 4

# Informații despre starea rețelei locale
var players: Dictionary = {} # Structură: { id (int): { "name": String, "ready": bool } }
var lobby_name: String = "My Amazing Lobby"
var local_player_name: String = "Player"

# Persistență date între nivele (Core Game Loop)
var team_credits: int = 0
var saved_inventories: Dictionary = {} # player_id: Array of 4 items
var saved_escaped_loot: Array = [] # list of dicts: rarity, price, color
var survivor_player_ids: Array[int] = []

# Referință la peer-ul activ
var peer: ENetMultiplayerPeer = null

func _ready() -> void:
	# Conectare la semnalele globale de rețea din Godot 4
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# --- HOST LOBBY ---
func create_lobby(port: int = DEFAULT_PORT) -> bool:
	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		print("Eroare la crearea serverului: ", error)
		return false

	multiplayer.multiplayer_peer = peer

	# Host-ul se adaugă pe sine în listă (ID-ul host-ului este întotdeauna 1)
	players[1] = {
		"name": local_player_name,
		"ready": false
	}

	lobby_created.emit()
	player_list_changed.emit()
	return true

# --- JOIN LOBBY ---
func join_lobby(ip: String, port: int = DEFAULT_PORT) -> void:
	if ip.is_empty():
		ip = "127.0.0.1"

	peer = ENetMultiplayerPeer.new()
	var error: Error = peer.create_client(ip, port)
	if error != OK:
		print("Eroare la inițierea clientului: ", error)
		lobby_join_failed.emit()
		return

	multiplayer.multiplayer_peer = peer

# --- READY / UNREADY SYSTEM ---
func toggle_ready() -> void:
	var local_id: int = multiplayer.get_unique_id()
	if local_id in players:
		var current_ready_state: bool = players[local_id]["ready"]
		rpc("set_player_ready", local_id, !current_ready_state)

@rpc("any_peer", "call_local", "reliable")
func set_player_ready(player_id: int, is_ready: bool) -> void:
	if player_id in players:
		players[player_id]["ready"] = is_ready
		player_list_changed.emit()

# --- LOBBY NAME SYSTEM ---
func change_lobby_name(new_name: String) -> void:
	if multiplayer.is_server():
		rpc("sync_lobby_name", new_name)

@rpc("any_peer", "call_local", "reliable")
func sync_lobby_name(new_name: String) -> void:
	lobby_name = new_name
	lobby_name_changed.emit(new_name)

# --- START GAME SYSTEM ---
func start_game() -> void:
	if multiplayer.is_server():
		# Verificăm dacă toată lumea e pregătită sau dacă host-ul dorește force start
		rpc("load_game_scene")

@rpc("call_local", "reliable")
func load_game_scene() -> void:
	game_started.emit()
	get_tree().change_scene_to_file("res://scenes/testing_platform.tscn")

# --- LEAVE / DISCONNECT ---
func leave_lobby() -> void:
	multiplayer.multiplayer_peer = null
	peer = null
	players.clear()
	# Resetăm la valorile implicite
	lobby_name = "My Amazing Lobby"

# --- NETWORK CALLBACKS ---

# Rulat pe toți clienții și pe server când se conectează un nou peer
func _on_player_connected(id: int) -> void:
	print("Jucător nou conectat cu ID: ", id)
	# Serverul trimite datele lobby-ului actual către noul jucător conectat
	if multiplayer.is_server():
		# Trimitem noului jucător numele lobby-ului
		rpc_id(id, "sync_lobby_name", lobby_name)
		# De asemenea, trimitem lista actuală de jucători către noul jucător
		for player_id in players:
			rpc_id(id, "register_player_on_client", player_id, players[player_id]["name"], players[player_id]["ready"])

		# Solicităm noului jucător să își înregistreze datele proprii pe server și pe ceilalți clienți
		rpc_id(id, "request_player_info")

@rpc("any_peer", "call_local", "reliable")
func request_player_info() -> void:
	var my_id: int = multiplayer.get_unique_id()
	rpc("register_player_on_client", my_id, local_player_name, false)

@rpc("any_peer", "call_local", "reliable")
func register_player_on_client(id: int, p_name: String, p_ready: bool) -> void:
	players[id] = {
		"name": p_name,
		"ready": p_ready
	}
	player_list_changed.emit()

func _on_player_disconnected(id: int) -> void:
	print("Jucător deconectat cu ID: ", id)
	if id in players:
		players.erase(id)
		player_list_changed.emit()

func _on_connected_to_server() -> void:
	print("M-am conectat cu succes la server!")
	lobby_joined.emit()

func _on_connection_failed() -> void:
	print("Conexiunea la server a eșuat!")
	lobby_join_failed.emit()
	leave_lobby()

func _on_server_disconnected() -> void:
	print("Serverul s-a deconectat.")
	lobby_join_failed.emit() # Folosim semnalul de eșec pentru a forța întoarcerea în meniu
	leave_lobby()

# --- HELPER PENTRU DETERMINAREA LOCAL IP ---
func get_local_ip() -> String:
	var ips: PackedStringArray = IP.get_local_addresses()
	for ip in ips:
		# Filtrează adresele IPv4 locale (excluzând localhost și adresele IPv6)
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			return ip
	return "127.0.0.1"

# --- PERSISTENCE AND COLO LOGIC HELPERS ---
func save_player_inventory(player_id: int, inventory: Array) -> void:
	saved_inventories[player_id] = inventory.duplicate(true)

func get_saved_inventory(player_id: int) -> Array:
	if player_id in saved_inventories:
		return saved_inventories[player_id].duplicate(true)
	return [null, null, null, null]

func save_escaped_session(survivor_ids: Array[int], loot_data: Array) -> void:
	survivor_player_ids = survivor_ids
	saved_escaped_loot = loot_data.duplicate(true)

func add_credits(amount: int) -> void:
	if multiplayer.is_server():
		rpc("sync_credits", team_credits + amount)

@rpc("call_local", "reliable")
func sync_credits(new_amount: int) -> void:
	team_credits = new_amount
	# Notificăm toate nodurile de player local să își updateze HUD-ul
	var players_nodes = get_tree().get_nodes_in_group("players")
	for p in players_nodes:
		if p.has_method("_update_hud"):
			p._update_hud()
