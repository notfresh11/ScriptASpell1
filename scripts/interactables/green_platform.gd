# scripts/interactables/green_platform.gd
extends Area3D

# Această platformă este reutilizabilă.
# Pe Map1, ea servește ca zonă de colectare și evacuare (escape zone).
# În Lobby, servește ca zonă de aterizare a itemelor și jucătorilor salvați.

@export var is_lobby_platform: bool = false

# Liste pe server pentru urmărirea corpurilor aflate pe platformă
var players_on_platform: Array[Node3D] = []
var loot_on_platform: Array[Node3D] = []

# Starea numărătorilor inverse pe server
var confirmation_timer: float = 0.0
var escape_timer: float = 0.0

var is_confirming: bool = false
var is_escaping: bool = false

const CONFIRMATION_TIME: float = 10.0
const ESCAPE_TIME: float = 15.0

func _ready() -> void:
	if multiplayer.is_server():
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or is_lobby_platform:
		return

	# Obținem jucătorii activi din scenă
	var active_players = get_tree().get_nodes_in_group("players")
	if active_players.is_empty():
		_reset_states()
		return

	# Verificăm dacă TOȚI jucătorii activi din lobby sunt pe platformă
	var all_on_platform = true
	for p in active_players:
		if not p in players_on_platform:
			all_on_platform = false
			break

	if all_on_platform:
		if not is_confirming and not is_escaping:
			is_confirming = true
			confirmation_timer = CONFIRMATION_TIME
			print("Toți jucătorii sunt pe platformă! Începe confirmarea plecării...")

		if is_confirming:
			confirmation_timer -= delta
			_update_hud_status("Confirmare plecare: %d s" % ceil(confirmation_timer), Color.YELLOW)
			if confirmation_timer <= 0.0:
				is_confirming = false
				is_escaping = true
				escape_timer = ESCAPE_TIME
				print("Plecarea confirmată! Începe evacuarea în 15 secunde...")
	else:
		if is_confirming:
			_reset_states()
			print("Un jucător a părăsit platforma. Confirmarea a fost anulată.")

	if is_escaping:
		escape_timer -= delta
		_update_hud_status("EVACUARE ÎN: %d s" % ceil(escape_timer), Color.RED)
		if escape_timer <= 0.0:
			_trigger_escape()

func _reset_states() -> void:
	is_confirming = false
	is_escaping = false
	confirmation_timer = 0.0
	escape_timer = 0.0
	_update_hud_status("", Color.WHITE)

func _update_hud_status(text: String, color: Color) -> void:
	# Trimitem statusul tuturor jucătorilor prin RPC
	rpc("sync_hud_status", text, color)

@rpc("call_local", "reliable")
func sync_hud_status(text: String, color: Color) -> void:
	var local_player = _get_local_player_node()
	if local_player and local_player.has_node("HUD/EscapeLabel"):
		var label = local_player.get_node("HUD/EscapeLabel")
		label.text = text
		label.add_theme_color_override("font_color", color)
		label.visible = !text.is_empty()

func _get_local_player_node() -> Node3D:
	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p.has_method("is_multiplayer_authority") and p.is_multiplayer_authority():
			return p
	return null

func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if body.is_in_group("players") and not body in players_on_platform:
		players_on_platform.append(body)
		print("Player pe platforma verde: ", body.name)
	elif body.is_in_group("loot") and not body in loot_on_platform:
		loot_on_platform.append(body)
		print("Loot pe platforma verde: ", body.name)

		# Dacă este platforma din lobby, vindem automat orice loot intră pe ea!
		if is_lobby_platform:
			# Un delay de 5.0s pentru ca jucătorii să poată vedea fizic itemele pe platformă!
			get_tree().create_timer(5.0).timeout.connect(func(): _sell_loot_item(body))

func _on_body_exited(body: Node3D) -> void:
	if not multiplayer.is_server():
		return

	if body in players_on_platform:
		players_on_platform.erase(body)
		print("Player a părăsit platforma verde: ", body.name)
	elif body in loot_on_platform:
		loot_on_platform.erase(body)
		print("Loot a părăsit platforma verde: ", body.name)

func _sell_loot_item(loot_node: Node3D) -> void:
	if not is_instance_valid(loot_node):
		return

	# Dacă jucătorul a ridicat piesa de pe platformă în cele 5 secunde, nu o mai vindem automat!
	if not loot_node in loot_on_platform:
		return

	var price = loot_node.price
	var rarity = loot_node.rarity

	# Eliminăm obiectul din listă
	loot_on_platform.erase(loot_node)

	# Adăugăm banii la NetworkManager.team_credits pe server
	NetworkManager.add_credits(price)

	# Ștergem fizic piesa din simulare
	loot_node.queue_free()

	# Trimitem notificare vizuală pe HUD către toți jucătorii
	rpc("notify_loot_sold", rarity, price)

@rpc("call_local", "reliable")
func notify_loot_sold(rarity: String, price: int) -> void:
	var local_player = _get_local_player_node()
	if local_player:
		local_player._update_hud()
		# Flash notification on the pickup prompt of the HUD for local feedback
		var prompt = local_player.get_node_or_null("HUD/PickupPrompt")
		if prompt:
			prompt.text = "SOLD %s ITEM: +$%d" % [rarity.to_upper(), price]
			prompt.self_modulate = Color(0.1, 1.0, 0.2, 1) # Bright green
			prompt.visible = true

			# Ascundem promptul după 2.5 secunde
			get_tree().create_timer(2.5).timeout.connect(func():
				if is_instance_valid(prompt) and prompt.text.begins_with("SOLD"):
					prompt.visible = false
			)

func _trigger_escape() -> void:
	print("Timpul s-a scurs! Declanșăm evacuarea...")
	_reset_states()

	# Oprim orice procesare fizică suplimentară
	set_physics_process(false)

	# Salvăm jucătorii care au supraviețuit (sunt pe platformă) și loot-ul
	var survivors_ids: Array[int] = []
	var survived_loot_data: Array = []

	for p in players_on_platform:
		if "player_id" in p:
			survivors_ids.append(p.player_id)

	# Identificăm loot-ul fizic aflat pe platformă
	for l in loot_on_platform:
		if is_instance_valid(l) and "rarity" in l:
			survived_loot_data.append({
				"rarity": l.rarity,
				"price": l.price,
				"color": l.item_color
			})

	# Toți jucătorii își pierd inventarele și încep de la zero (obligatoriu fără iteme în inventar/mână în lobby)
	var active_players = get_tree().get_nodes_in_group("players")
	for p in active_players:
		if p.has_method("rpc"):
			p.rpc("clear_inventory")
		if "player_id" in p:
			NetworkManager.save_player_inventory(p.player_id, [null, null, null, null])

	# Salvăm datele hărții în NetworkManager
	NetworkManager.save_escaped_session(survivors_ids, survived_loot_data)

	# Schimbăm scena înapoi în Lobby pentru toată lumea
	rpc("load_lobby_scene")

@rpc("call_local", "reliable")
func load_lobby_scene() -> void:
	get_tree().change_scene_to_file("res://scenes/testing_platform.tscn")
