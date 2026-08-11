# scripts/player/player_movement.gd
extends CharacterBody3D

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5
const MOUSE_SENSITIVITY: float = 0.003

const LOOT_SCENE: PackedScene = preload("res://scenes/interactables/loot_item.tscn")

# Preluăm gravitația din setările Godot
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ID-ul unic de multiplayer al acestui jucător
@export var player_id: int = 1 :
	set(value):
		player_id = value
		set_multiplayer_authority(player_id)
		if is_multiplayer_authority() and is_node_ready():
			_setup_local_player()

# Replicat pentru rețea ca să vadă ceilalți jucători ce avem în mână
@export var active_item_color: Color = Color(0, 0, 0, 0) :
	set(value):
		active_item_color = value
		_update_hand_visual_for_all()

@onready var camera: Camera3D = $Camera3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var hand_container: Node3D = $Camera3D/HandContainer

# UI References
@onready var hud: CanvasLayer = $HUD
@onready var pickup_prompt: Label = $HUD/PickupPrompt
@onready var active_item_label: Label = $HUD/ActiveItemLabel
@onready var hotbar_slots: Array = [
	$HUD/Hotbar/Slot1,
	$HUD/Hotbar/Slot2,
	$HUD/Hotbar/Slot3,
	$HUD/Hotbar/Slot4
]

# Cache styleboxes as suggested for optimization
var style_normal: StyleBoxFlat = StyleBoxFlat.new()
var style_active: StyleBoxFlat = StyleBoxFlat.new()

# State de inventar local pentru authority-ul jucătorului
var inventory: Array = [null, null, null, null]
var active_slot_index: int = 0

# Visuals dynamically created
var puppet_hand_item: MeshInstance3D = null
var local_hand_item: MeshInstance3D = null

func _ready() -> void:
	_init_styles()
	_setup_input_actions()
	_setup_hand_visuals()

	if is_multiplayer_authority():
		_setup_local_player()
	else:
		camera.current = false
		# Ascundem HUD-ul de pe clienții străini ca să nu se suprapună pe ecranul nostru
		if hud:
			hud.visible = false

	# Inițializăm hand visuals-ul corespunzător culorii
	_update_hand_visual_for_all()
	_update_hud()

# Înființăm stilurile de bază pentru UI
func _init_styles() -> void:
	style_normal.bg_color = Color(0.12, 0.12, 0.14, 0.6)
	style_normal.border_width_left = 2
	style_normal.border_width_top = 2
	style_normal.border_width_right = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = Color(0.25, 0.25, 0.28, 0.8)
	style_normal.corner_radius_top_left = 5
	style_normal.corner_radius_top_right = 5
	style_normal.corner_radius_bottom_right = 5
	style_normal.corner_radius_bottom_left = 5

	style_active.bg_color = Color(0.16, 0.16, 0.2, 0.8)
	style_active.border_width_left = 3
	style_active.border_width_top = 3
	style_active.border_width_right = 3
	style_active.border_width_bottom = 3
	style_active.border_color = Color(0, 0.9, 0.8, 1) # Cyan neon highlight
	style_active.corner_radius_top_left = 5
	style_active.corner_radius_top_right = 5
	style_active.corner_radius_bottom_right = 5
	style_active.corner_radius_bottom_left = 5

# Înființăm dinamic mesh-urile pentru mână (local vs puppet)
func _setup_hand_visuals() -> void:
	# Mesh-ul pentru ceilalți jucători (third-person)
	puppet_hand_item = MeshInstance3D.new()
	var p_mesh = BoxMesh.new()
	p_mesh.size = Vector3(0.25, 0.25, 0.25)
	puppet_hand_item.mesh = p_mesh
	puppet_hand_item.position = Vector3(0.4, 0.5, -0.4)
	puppet_hand_item.visible = false
	if mesh_instance:
		mesh_instance.add_child(puppet_hand_item)

	# Mesh-ul pentru camera noastră FPS (first-person)
	local_hand_item = MeshInstance3D.new()
	var l_mesh = BoxMesh.new()
	l_mesh.size = Vector3(0.15, 0.15, 0.15)
	local_hand_item.mesh = l_mesh
	local_hand_item.visible = false
	if hand_container:
		hand_container.add_child(local_hand_item)

# Inițializăm dinamic acțiunile pentru taste
func _setup_input_actions() -> void:
	var actions = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_UP],
		"move_backward": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE],
		"hotkey_1": [KEY_1],
		"hotkey_2": [KEY_2],
		"hotkey_3": [KEY_3],
		"hotkey_4": [KEY_4],
		"pickup": [KEY_E],
		"drop": [KEY_Q]
	}

	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key in actions[action]:
				var event = InputEventKey.new()
				event.physical_keycode = key
				InputMap.action_add_event(action, event)

func _setup_local_player() -> void:
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Ascundem propriul model 3D (capsula) local
	if mesh_instance:
		mesh_instance.visible = false
	if hud:
		hud.visible = true

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Rotire cameră prin mișcarea mouse-ului - în _input ca să nu fie blocat de elemente UI/HUD
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(80), deg_to_rad(80))

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Schimbare Slot-uri active (Hotkeys 1-4)
	if event.is_action_pressed("hotkey_1"): _select_slot(0)
	elif event.is_action_pressed("hotkey_2"): _select_slot(1)
	elif event.is_action_pressed("hotkey_3"): _select_slot(2)
	elif event.is_action_pressed("hotkey_4"): _select_slot(3)

	# Pick Up Item (Taste E)
	if event.is_action_pressed("pickup"):
		_try_pickup()

	# Drop Item (Taste Q)
	if event.is_action_pressed("drop"):
		_try_drop()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Adăugăm gravitația
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Săritură
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Preluăm mișcarea WASD
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Scanăm cu RayCast-ul în fiecare cadru pentru prompt-ul de pick up
	_process_raycast()

# --- DETECTARE ȘI INTERACȚIUNE CU LOOT ---
func _process_raycast() -> void:
	if not raycast or not pickup_prompt:
		return

	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider and collider.is_in_group("loot"):
			var rarity_str = collider.rarity.to_upper()
			var price_val = collider.price
			var rarity_col = collider.item_color

			pickup_prompt.text = "[E] Pick Up %s Item ($%d)" % [rarity_str, price_val]
			pickup_prompt.self_modulate = rarity_col
			pickup_prompt.visible = true
			return

	pickup_prompt.visible = false

func _try_pickup() -> void:
	if not raycast.is_colliding():
		return

	var collider = raycast.get_collider()
	if collider and collider.is_in_group("loot"):
		# Verificăm dacă avem loc liber în inventar înainte de a cere serverului pickup-ul
		var free_slot = inventory.find(null)
		if free_slot == -1:
			print("Inventarul este plin! Nu poți colecta mai mult.")
			return

		# Trimitem cerere către server pentru procesare sigură (evitând pickup-uri multiple)
		rpc_id(1, "request_pickup", collider.get_path())

func _try_drop() -> void:
	var item_to_drop = inventory[active_slot_index]
	if item_to_drop == null:
		return

	# Calculăm poziția și viteza de aruncare în fața camerei
	var spawn_pos = global_position + Vector3(0, 1.2, 0) - camera.global_transform.basis.z * 0.8
	var throw_vel = -camera.global_transform.basis.z * 6.0 + Vector3(0, 2.0, 0)

	# Solicităm serverului să creeze obiectul fizic în lume
	rpc_id(1, "request_drop", item_to_drop["rarity"], item_to_drop["price"], item_to_drop["color"], spawn_pos, throw_vel)

	# Îndepărtăm din inventarul local al clientului
	inventory[active_slot_index] = null
	_update_hud()
	_update_active_hand_color()

# --- SERVER RPC: PROCESARE ACHIZIȚIE/ARUNCARE ---
@rpc("any_peer", "call_local")
func request_pickup(item_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	var item_node = get_node_or_null(item_path)

	if item_node and item_node.is_in_group("loot"):
		var item_rarity = item_node.rarity
		var item_price = item_node.price
		var item_color = item_node.item_color

		# Eliminăm obiectul din lume pe server (care se propagă clienților)
		item_node.queue_free()

		# Notificăm clientul trimițător să îl adauge în inventar
		rpc_id(sender_id, "add_to_inventory", item_rarity, item_price, item_color)

@rpc("any_peer", "call_local")
func add_to_inventory(p_rarity: String, p_price: int, p_color: Color) -> void:
	var empty_slot = inventory.find(null)
	if empty_slot != -1:
		inventory[empty_slot] = {
			"rarity": p_rarity,
			"price": p_price,
			"color": p_color
		}
		_update_hud()
		_update_active_hand_color()

@rpc("any_peer", "call_local")
func request_drop(p_rarity: String, p_price: int, p_color: Color, spawn_pos: Vector3, throw_vel: Vector3) -> void:
	if not multiplayer.is_server():
		return

	# Instanțiem piesa de loot în lumea 3D de pe server
	var loot_item = LOOT_SCENE.instantiate()
	loot_item.position = spawn_pos

	# Îl adăugăm la nodul "Loot" al generatorului de pe server
	var loot_container = get_node_or_null("/root/DungeonGenerator/Loot")
	if loot_container:
		loot_container.add_child(loot_item, true)
	else:
		get_parent().add_child(loot_item, true)

	var unique_id = str(randi()) + "_" + str(Time.get_ticks_msec())
	loot_item.init_loot(unique_id, p_rarity, p_price, p_color)

	# Aplicăm impulsul fizic
	loot_item.linear_velocity = throw_vel

# --- INVENTORY & UI HIGHLIGHT LOGIC ---
func _select_slot(index: int) -> void:
	if active_slot_index == index:
		return
	active_slot_index = index
	_update_hud()
	_update_active_hand_color()

func _update_active_hand_color() -> void:
	var current_item = inventory[active_slot_index]
	if current_item:
		active_item_color = current_item["color"]
	else:
		active_item_color = Color(0, 0, 0, 0) # Mână goală

func _update_hud() -> void:
	if not is_multiplayer_authority() or not hud:
		return

	# Actualizăm grafic cele 4 slot-uri folosind stilurile cache-uite
	for i in range(4):
		var slot_panel = hotbar_slots[i]
		var label = slot_panel.get_node("Label")
		var item = inventory[i]

		# Aplicăm Style-ul corespunzător activ/inactiv
		if i == active_slot_index:
			slot_panel.add_theme_stylebox_override("panel", style_active)
		else:
			slot_panel.add_theme_stylebox_override("panel", style_normal)

		# Actualizăm conținutul
		if item:
			label.text = "%s\n$%d" % [item["rarity"].to_upper(), item["price"]]
			label.self_modulate = item["color"]
		else:
			label.text = "Empty"
			label.self_modulate = Color(1, 1, 1, 0.4)

	# Actualizăm eticheta de Active Item de sub hotbar
	var active_item = inventory[active_slot_index]
	if active_item:
		active_item_label.text = "Holding: %s ($%d)" % [active_item["rarity"].to_upper(), active_item["price"]]
		active_item_label.self_modulate = active_item["color"]
	else:
		active_item_label.text = "Holding: Nothing"
		active_item_label.self_modulate = Color(1, 1, 1, 0.7)

# --- REPLICATE HAND MESH VISIBILITY ---
func _update_hand_visual_for_all() -> void:
	if not is_node_ready():
		return

	var has_item = active_item_color.a > 0.0

	# Mesh-ul din spate (pupeții pe care îi văd ceilalți)
	if puppet_hand_item:
		puppet_hand_item.visible = has_item
		if has_item:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = active_item_color
			mat.roughness = 0.8
			puppet_hand_item.material_override = mat

	# Mesh-ul din față (pe care îl vedem doar noi)
	if is_multiplayer_authority() and local_hand_item:
		local_hand_item.visible = has_item
		if has_item:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = active_item_color
			mat.roughness = 0.8
			local_hand_item.material_override = mat
