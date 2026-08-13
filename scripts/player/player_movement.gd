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
		if is_inside_tree():
			set_multiplayer_authority(player_id)
			if is_multiplayer_authority() and is_node_ready():
				_setup_local_player()

func _enter_tree() -> void:
	set_multiplayer_authority(player_id)

# Replicat pentru rețea ca să vadă ceilalți jucători ce avem în mână
@export var active_item_color: Color = Color(0, 0, 0, 0) :
	set(value):
		active_item_color = value
		_update_hand_visual_for_all()

@onready var camera: Camera3D = $Camera3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var raycast: RayCast3D = $Camera3D/RayCast3D
@onready var hand_container: Node3D = $Camera3D/HandContainer

# Camerele de post-procesare pentru dual viewport
@onready var retro_camera: Camera3D = $RetroScreen/SubViewportContainer/SubViewport/Camera3D_Retro
@onready var neon_camera: Camera3D = $NeonScreen/SubViewportContainer/SubViewport/Camera3D_Neon
@onready var torch_light: SpotLight3D = $Camera3D/TorchLight

@export_group("Torch Light Settings")
@export var torch_enabled_by_default: bool = true
@export var torch_base_energy: float = 1.2
@export var torch_flicker_speed: float = 8.0
@export var torch_flicker_strength: float = 0.25
@export var torch_color: Color = Color(1, 0.65, 0.3, 1)

var torch_time: float = 0.0

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

# Shop References
@onready var shop_ui: Control = $HUD/ShopUI
@onready var shop_vbox: VBoxContainer = $HUD/ShopUI/Panel/ScrollContainer/VBox
@onready var shop_close_button: Button = $HUD/ShopUI/Panel/CloseButton

# Coding References
@onready var coding_ui: Control = $HUD/CodingUI
@onready var coding_left_vbox: VBoxContainer = $HUD/CodingUI/Panel/HBox/LeftBlocks/Scroll/VBox
@onready var coding_tab_bar: TabBar = $HUD/CodingUI/Panel/HBox/RightEditor/TabBar
@onready var coding_active_vbox: VBoxContainer = $HUD/CodingUI/Panel/HBox/RightEditor/Scroll/ActiveScriptBlocks
@onready var coding_reset_btn: Button = $HUD/CodingUI/Panel/ActionButtons/ResetDefaultBtn
@onready var coding_save_btn: Button = $HUD/CodingUI/Panel/ActionButtons/SaveBtn
@onready var coding_close_btn: Button = $HUD/CodingUI/Panel/ActionButtons/CloseBtn

# Secțiunile corpului folosite în taburi
const SECTIONS: Array = ["Head", "L Hand", "R Hand", "L Foot", "R Foot", "Body", "Spell"]

# Cache styleboxes as suggested for optimization
var style_normal: StyleBoxFlat = StyleBoxFlat.new()
var style_active: StyleBoxFlat = StyleBoxFlat.new()

# State de inventar local pentru authority-ul jucătorului
var inventory: Array = [null, null, null, null]
var active_slot_index: int = 0

# Sistemul de coding și shop
var owned_blocks: Array = ["IF", "ELSE", "WAIT", "LOOK_MOUSE", "MOVE_FORWARD", "MOVE_BACKWARD", "MOVE_LEFT", "MOVE_RIGHT", "PICKUP", "DROP"] # Blocuri inițiale pe care le deține oricum player-ul
var compiled_scripts: Dictionary = {
	"Head": [],
	"L Hand": [],
	"R Hand": [],
	"L Foot": [],
	"R Foot": [],
	"Body": [],
	"Spell": []
}

# Starea curentă a modificărilor de cod locale
var pending_scripts: Dictionary = {}

# Visuals dynamically created
var puppet_hand_item: MeshInstance3D = null
var local_hand_item: MeshInstance3D = null

func _ready() -> void:
	add_to_group("players")
	_init_styles()
	_setup_input_actions()
	_setup_hand_visuals()

	# Configurare evenimente UI Shop
	if shop_close_button:
		shop_close_button.pressed.connect(func(): open_shop(false))

	# Configurare evenimente UI Coding
	if coding_close_btn:
		coding_close_btn.pressed.connect(func(): toggle_coding_menu())
	if coding_reset_btn:
		coding_reset_btn.pressed.connect(_on_coding_reset_pressed)
	if coding_save_btn:
		coding_save_btn.pressed.connect(_on_coding_save_pressed)
	if coding_tab_bar:
		coding_tab_bar.tab_changed.connect(_on_coding_tab_changed)

	# Inițializăm scripturile implicite
	_init_default_scripts()

	if is_multiplayer_authority():
		_setup_local_player()
		if torch_light:
			torch_light.visible = torch_enabled_by_default
			torch_light.light_color = torch_color
	else:
		camera.current = false
		if has_node("RetroScreen"): $RetroScreen.queue_free()
		if has_node("NeonScreen"): $NeonScreen.queue_free()
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
	local_hand_item.layers = 2 # Setează doar pe Layer 2 (Neon / High-Res)
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
		"drop": [KEY_Q],
		"toggle_flashlight": [KEY_F],
		"toggle_coding": [KEY_B]
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
	if has_node("RetroScreen"): $RetroScreen.visible = true
	if has_node("NeonScreen"): $NeonScreen.visible = true

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Dacă avem UI activ, ignorăm rotirea camerei
	var ui_active = false
	if shop_ui and shop_ui.visible: ui_active = true
	if coding_ui and coding_ui.visible: ui_active = true
	if ui_active:
		return

	# Verificăm dacă interpreterul permite LOOK_MOUSE în cadrul activ
	var head_res = _execute_interpreter_section("Head")
	var look_mouse_allowed = "LOOK_MOUSE" in head_res

	# Rotire cameră prin mișcarea mouse-ului - în _input ca să nu fie blocat de elemente UI/HUD
	if look_mouse_allowed and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(80), deg_to_rad(80))

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Tasta B deschide/închide editorul de coding sau închide shopul
	if event.is_action_pressed("toggle_coding"):
		if shop_ui and shop_ui.visible:
			open_shop(false)
		elif coding_ui:
			toggle_coding_menu()

	# Schimbare Slot-uri active (Hotkeys 1-4)
	if event.is_action_pressed("hotkey_1"): _select_slot(0)
	elif event.is_action_pressed("hotkey_2"): _select_slot(1)
	elif event.is_action_pressed("hotkey_3"): _select_slot(2)
	elif event.is_action_pressed("hotkey_4"): _select_slot(3)

	# Pick Up Item (Taste E) - validăm prin interpreter
	if event.is_action_pressed("pickup"):
		var l_hand_res = _execute_interpreter_section("L Hand")
		if "PICKUP" in l_hand_res:
			_try_pickup()

	# Drop Item (Taste Q) - validăm prin interpreter
	if event.is_action_pressed("drop"):
		var r_hand_res = _execute_interpreter_section("R Hand")
		if "DROP" in r_hand_res:
			_try_drop()

	# Toggle Torch (Taste F) - validăm prin interpreter (Tasta F devine Spell)
	if event.is_action_pressed("toggle_flashlight"):
		# În mod implicit, F era lanterna, dar acum aprinde și Spell (F)
		# Dacă avem Spell configurat, se rulează acțiunile sale (Night Vision, Glow etc.)
		# De asemenea, lăsăm comportamentul de a comuta vizibilitatea lanternei dacă nu e niciun spell special,
		# sau le combinăm într-un mod amuzant
		if torch_light:
			torch_light.visible = not torch_light.visible

# Proprietăți dinamice modificate de cod
var current_speed_multiplier: float = 1.0
var night_vision_active: bool = false
var glow_active: bool = false
var gravity_multiplier: float = 1.0

# Cooldown pentru tasta F (Spell)
var spell_cooldown_active: bool = false

# Un flag pentru a urmări dacă s-a detectat o eroare
var has_coding_error: bool = false

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Dacă avem un UI deschis (Shop sau Coding), oprim mișcarea fizică
	var ui_active = false
	if shop_ui and shop_ui.visible: ui_active = true
	if coding_ui and coding_ui.visible: ui_active = true

	if ui_active:
		velocity.x = 0
		velocity.z = 0
		if not is_on_floor():
			velocity.y -= (gravity * gravity_multiplier) * delta
		move_and_slide()
		return

	# --- INTERPRETER TICK ---
	# Resetăm mișcarea dorită de la interpreter
	var move_vector: Vector3 = Vector3.ZERO

	# Parametrii resetați înaintea interpretării
	current_speed_multiplier = 1.0
	gravity_multiplier = 1.0

	# Rulăm interpreterul pentru fiecare secțiune activă
	# L Foot (Mers stânga/față)
	var l_foot_res = _execute_interpreter_section("L Foot")
	if "MOVE_FORWARD" in l_foot_res: move_vector += -transform.basis.z
	if "MOVE_LEFT" in l_foot_res: move_vector += -transform.basis.x
	if "SPEED" in l_foot_res: current_speed_multiplier = l_foot_res["SPEED"]
	if "BOUNCY" in l_foot_res: gravity_multiplier = 0.4

	# R Foot (Mers dreapta/spate)
	var r_foot_res = _execute_interpreter_section("R Foot")
	if "MOVE_BACKWARD" in r_foot_res: move_vector += transform.basis.z
	if "MOVE_RIGHT" in r_foot_res: move_vector += transform.basis.x
	if "SPEED" in r_foot_res: current_speed_multiplier = r_foot_res["SPEED"]
	if "BOUNCY" in r_foot_res: gravity_multiplier = 0.4

	# Body
	var body_res = _execute_interpreter_section("Body")
	if "SPEED" in body_res: current_speed_multiplier = body_res["SPEED"]
	if "BOUNCY" in body_res: gravity_multiplier = 0.4

	# Spell (F) se rulează la _unhandled_input, sau periodic dacă e Always
	var spell_res = _execute_interpreter_section("Spell")
	if "NIGHT_VISION" in spell_res: night_vision_active = true
	else: night_vision_active = false
	if "GLOW" in spell_res: glow_active = true
	else: glow_active = false
	if "BOUNCY" in r_foot_res or "BOUNCY" in l_foot_res or "BOUNCY" in body_res or "BOUNCY" in spell_res:
		gravity_multiplier = 0.4
	else:
		gravity_multiplier = 1.0

	# Adăugăm gravitația
	if not is_on_floor():
		velocity.y -= (gravity * gravity_multiplier) * delta

	# Săritură (Jump) interpretat direct din taste sau instrucțiune
	var is_jumping = Input.is_action_just_pressed("jump")
	if is_jumping and is_on_floor():
		velocity.y = JUMP_VELOCITY * (1.5 if gravity_multiplier < 1.0 else 1.0)

	# Procesare mișcare finală bazată pe interpreter
	move_vector = move_vector.normalized()
	if move_vector:
		var target_speed = SPEED * current_speed_multiplier
		velocity.x = move_vector.x * target_speed
		velocity.z = move_vector.z * target_speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	# Aplicăm efectele vizuale selectate din interpreter (Glow / Night Vision)
	_apply_interpreter_visual_effects()

# --- INTERPRETER IMPLEMENTATION ---
func _execute_interpreter_section(section: String) -> Dictionary:
	var results: Dictionary = {}
	var script_blocks = compiled_scripts.get(section, [])

	var i = 0
	var if_condition_met = true

	while i < script_blocks.size():
		var block = script_blocks[i]
		var type = block["type"]
		var param = block.get("param", "")

		# Verificăm dacă structura codului are erori (ex: IF singur la sfârșit sau IF urmat de alt IF fără acțiuni, sau ELSE fără IF în spate)
		# Asta va declanșa Chaos Engine!
		if type == "IF":
			if i == script_blocks.size() - 1:
				_trigger_chaos_engine("Syntax Error: IF block has no instruction body")
				break

			# Evaluăm condiția
			if_condition_met = _evaluate_condition(param)
			if not if_condition_met:
				# Sărim peste următoarea instrucțiune directă (care este corpul IF-ului)
				i += 1

		elif type == "ELSE":
			# Else rulează doar dacă precedenta condiție IF a fost falsă
			if i == 0:
				_trigger_chaos_engine("Syntax Error: ELSE block must follow an IF block")
				break

			if if_condition_met:
				# Sărim peste instrucțiunea din ELSE
				i += 1

		elif type == "WAIT":
			# La nivel de fizică / MVP, wait-ul din loop este simulat printr-un cooldown sau lăsat ca un delay
			pass

		elif type == "LOOK_MOUSE":
			results["LOOK_MOUSE"] = true
		elif type == "MOVE_FORWARD":
			results["MOVE_FORWARD"] = true
		elif type == "MOVE_BACKWARD":
			results["MOVE_BACKWARD"] = true
		elif type == "MOVE_LEFT":
			results["MOVE_LEFT"] = true
		elif type == "MOVE_RIGHT":
			results["MOVE_RIGHT"] = true
		elif type == "PICKUP":
			results["PICKUP"] = true
		elif type == "DROP":
			results["DROP"] = true
		elif type == "SPEED":
			var mult = 1.0
			if param == "1x": mult = 1.0
			elif param == "2x": mult = 2.0
			elif param == "3x": mult = 3.0
			results["SPEED"] = mult
		elif type == "NIGHT_VISION":
			results["NIGHT_VISION"] = true
		elif type == "GLOW":
			results["GLOW"] = true
		elif type == "BOUNCY":
			results["BOUNCY"] = true

		i += 1

	return results

func _evaluate_condition(cond: String) -> bool:
	match cond:
		"Always": return true
		"W_pressed": return Input.is_action_pressed("move_forward")
		"S_pressed": return Input.is_action_pressed("move_backward")
		"A_pressed": return Input.is_action_pressed("move_left")
		"D_pressed": return Input.is_action_pressed("move_right")
		"E_pressed": return Input.is_action_pressed("pickup")
		"Q_pressed": return Input.is_action_pressed("drop")
		"F_pressed": return Input.is_action_pressed("toggle_flashlight")
		"Mouse_Moved":
			# Simulat ca mișcare mouse activă
			return Input.get_last_mouse_velocity().length() > 0.05
		"Health_Low":
			return false # În MVP nu avem viață directă implementată, considerat false
	return false

func _apply_interpreter_visual_effects() -> void:
	# Glow effect pe lanternă
	if is_instance_valid(torch_light):
		if glow_active:
			torch_light.light_energy = torch_base_energy * 3.0
			torch_light.spot_angle = 70.0
		else:
			# Lăsăm procesarea de flicker standard
			pass

	# Night vision effect (verde neon overlay)
	if is_multiplayer_authority() and has_node("RetroScreen/SubViewportContainer"):
		var container = $RetroScreen/SubViewportContainer
		var mat = container.material
		if mat is ShaderMaterial:
			if night_vision_active:
				# Forțăm dither-ul în verde neon
				mat.set_shader_parameter("vignette_intensity", 0.8)
			else:
				mat.set_shader_parameter("vignette_intensity", 0.4)

# Timer / Cooldown pentru erorile de Chaos Engine pentru a evita crearea a mii de cuburi pe secundă
var chaos_error_cooldown: float = 0.0

func _trigger_chaos_engine(error_msg: String) -> void:
	if chaos_error_cooldown > 0.0:
		return

	# Punem o secundă de cooldown
	chaos_error_cooldown = 1.0
	has_coding_error = true
	print("CHAOS DETECTED: ", error_msg)

	# Trimitem poziția în fața jucătorului
	var spawn_pos = global_position + Vector3(0, 0.5, 0) - camera.global_transform.basis.z * 1.5

	# Apelăm RPC pe ChaosEngine autoload
	ChaosEngine.rpc_id(1, "trigger_runtime_error", player_id, error_msg, spawn_pos)

func _process(_delta: float) -> void:
	if chaos_error_cooldown > 0.0:
		chaos_error_cooldown -= _delta
	if not is_multiplayer_authority():
		return

	# Efectul de pâlpâire pentru torța medievală cu ulei
	if is_instance_valid(torch_light) and torch_light.visible:
		torch_time += _delta * torch_flicker_speed
		var flicker = sin(torch_time) * cos(torch_time * 0.7) * 0.5 + sin(torch_time * 1.5) * 0.3
		torch_light.light_energy = torch_base_energy + (flicker * torch_flicker_strength)

	# Scanăm cu RayCast-ul în fiecare cadru pentru prompt-ul de pick up
	_process_raycast()

# --- INITIALIZE SCRIPTS ---
func _init_default_scripts() -> void:
	for section in SECTIONS:
		compiled_scripts[section] = Interpreter.get_default_script(section)
	# Duplicăm în pending inițial
	pending_scripts = compiled_scripts.duplicate(true)

# --- CODING SYSTEM LOGIC (TASTA B) ---
func toggle_coding_menu() -> void:
	if not is_multiplayer_authority() or not coding_ui:
		return

	if not coding_ui.visible:
		# Închidem shop-ul dacă e deschis
		if shop_ui and shop_ui.visible:
			open_shop(false)

		coding_ui.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh_coding_ui()
	else:
		coding_ui.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_coding_tab_changed(_tab: int) -> void:
	_refresh_active_section_editor()

func _on_coding_reset_pressed() -> void:
	var active_tab = coding_tab_bar.current_tab
	var section = SECTIONS[active_tab]
	pending_scripts[section] = Interpreter.get_default_script(section)
	_refresh_active_section_editor()

func _on_coding_save_pressed() -> void:
	# Copiem pending în compiled
	compiled_scripts = pending_scripts.duplicate(true)
	print("Scripturi salvate cu succes local!")
	toggle_coding_menu()

func _refresh_coding_ui() -> void:
	_refresh_owned_blocks_list()
	_refresh_active_section_editor()

func _refresh_owned_blocks_list() -> void:
	if not coding_left_vbox:
		return

	for child in coding_left_vbox.get_children():
		child.queue_free()

	var definitions = Interpreter.get_available_blocks_definition()
	for block_id in owned_blocks:
		if block_id in definitions:
			var info = definitions[block_id]

			var block_btn = Button.new()
			block_btn.text = "+ " + info["name"]
			block_btn.add_theme_font_size_override("font_size", 12)
			if info["type"] == "control":
				block_btn.add_theme_color_override("font_color", Color(1, 0.65, 0, 1)) # Portocaliu control
			else:
				block_btn.add_theme_color_override("font_color", Color(0, 0.9, 0.8, 1)) # Cyan action

			block_btn.custom_minimum_size = Vector2(0, 35)
			# Click pe block îl adaugă în secțiunea curentă
			block_btn.pressed.connect(func(): _add_block_to_current_section(block_id))

			coding_left_vbox.add_child(block_btn)

func _refresh_active_section_editor() -> void:
	if not coding_active_vbox or not coding_tab_bar:
		return

	for child in coding_active_vbox.get_children():
		child.queue_free()

	var active_tab = coding_tab_bar.current_tab
	var section = SECTIONS[active_tab]
	var current_script = pending_scripts[section]

	if current_script.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "Empty. Click owned blocks on the left to add instructions."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		coding_active_vbox.add_child(empty_lbl)
		return

	var definitions = Interpreter.get_available_blocks_definition()
	for i in range(current_script.size()):
		var block_data = current_script[i]
		var block_type = block_data["type"]

		if not block_type in definitions:
			continue

		var info = definitions[block_type]

		var block_hbox = HBoxContainer.new()
		block_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Background color pentru block-uri
		var panel = PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style = StyleBoxFlat.new()
		if info["type"] == "control":
			style.bg_color = Color(0.2, 0.12, 0.05, 0.8) # Portocaliu închis
			style.border_color = Color(1, 0.65, 0, 1)
		else:
			style.bg_color = Color(0.05, 0.15, 0.18, 0.8) # Cyan închis
			style.border_color = Color(0, 0.9, 0.8, 1)
		style.border_width_left = 4
		style.corner_radius_top_left = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		panel.add_theme_stylebox_override("panel", style)

		var inner_hbox = HBoxContainer.new()
		inner_hbox.alignment = BoxContainer.ALIGNMENT_BEGIN

		var name_lbl = Label.new()
		name_lbl.text = "  " + info["name"] + " "
		name_lbl.add_theme_font_size_override("font_size", 12)
		inner_hbox.add_child(name_lbl)

		# Dropdown parametru dacă are opțiuni
		if info["has_dropdown"]:
			var option_btn = OptionButton.new()
			option_btn.add_theme_font_size_override("font_size", 11)
			var options = info["dropdown_options"]
			for opt in options:
				option_btn.add_item(opt)

			# Selectăm valoarea curentă din block_data dacă există, altfel prima
			var selected_param = block_data.get("param", "")
			var idx = options.find(selected_param)
			if idx != -1:
				option_btn.selected = idx
			else:
				option_btn.selected = 0
				block_data["param"] = options[0]

			# Modificare parametru
			var current_index_in_loop = i
			option_btn.item_selected.connect(func(index):
				current_script[current_index_in_loop]["param"] = options[index]
			)
			inner_hbox.add_child(option_btn)

		panel.add_child(inner_hbox)
		block_hbox.add_child(panel)

		# Butoane sus, jos, delete
		var action_hbox = HBoxContainer.new()
		action_hbox.alignment = BoxContainer.ALIGNMENT_END

		var up_btn = Button.new()
		up_btn.text = "▲"
		up_btn.disabled = (i == 0)
		up_btn.pressed.connect(func(): _move_block_in_section(section, i, -1))

		var down_btn = Button.new()
		down_btn.text = "▼"
		down_btn.disabled = (i == current_script.size() - 1)
		down_btn.pressed.connect(func(): _move_block_in_section(section, i, 1))

		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.add_theme_color_override("font_color", Color.RED)
		del_btn.pressed.connect(func(): _delete_block_from_section(section, i))

		action_hbox.add_child(up_btn)
		action_hbox.add_child(down_btn)
		action_hbox.add_child(del_btn)

		block_hbox.add_child(action_hbox)
		coding_active_vbox.add_child(block_hbox)

func _add_block_to_current_section(block_id: String) -> void:
	if not coding_tab_bar:
		return
	var active_tab = coding_tab_bar.current_tab
	var section = SECTIONS[active_tab]

	# Adăugăm un nou block gol în pending-ul secțiunii
	var definitions = Interpreter.get_available_blocks_definition()
	var info = definitions[block_id]
	var default_param = ""
	if info["has_dropdown"]:
		default_param = info["dropdown_options"][0]

	pending_scripts[section].append({
		"type": block_id,
		"param": default_param
	})

	_refresh_active_section_editor()

func _move_block_in_section(section: String, index: int, direction: int) -> void:
	var script_list = pending_scripts[section]
	var target_index = index + direction
	if target_index >= 0 and target_index < script_list.size():
		var temp = script_list[index]
		script_list[index] = script_list[target_index]
		script_list[target_index] = temp
		_refresh_active_section_editor()

func _delete_block_from_section(section: String, index: int) -> void:
	pending_scripts[section].remove_at(index)
	_refresh_active_section_editor()


# --- SHOP SYSTEM LOGIC ---
func open_shop(should_open: bool) -> void:
	if not is_multiplayer_authority() or not shop_ui:
		return

	if should_open:
		# Dacă editorul de coding este deschis, îl închidem
		if coding_ui and coding_ui.visible:
			toggle_coding_menu()

		shop_ui.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_populate_shop_items()
	else:
		shop_ui.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _populate_shop_items() -> void:
	if not shop_vbox:
		return

	# Curățăm produsele anterioare
	for child in shop_vbox.get_children():
		child.queue_free()

	var definitions = Interpreter.get_available_blocks_definition()
	for block_id in definitions:
		var info = definitions[block_id]

		# Nu punem la vânzare blocurile pe care jucătorul le deține deja (opțional sau le punem oricum pentru restock)
		# Dar pentru simplitatea MVP-ului, le lăsăm pe toate, sau ascundem pe cele deja deținute:
		var is_owned = block_id in owned_blocks

		var item_hbox = HBoxContainer.new()
		item_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label = Label.new()
		name_label.text = info["name"] + (" (OWNED)" if is_owned else "")
		name_label.add_theme_color_override("font_color", Color(0, 0.9, 0.8, 1) if not is_owned else Color(0.5, 0.5, 0.5, 1))
		name_label.add_theme_font_size_override("font_size", 14)

		var desc_label = Label.new()
		desc_label.text = info["desc"]
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		desc_label.add_theme_font_size_override("font_size", 11)

		info_vbox.add_child(name_label)
		info_vbox.add_child(desc_label)

		var buy_btn = Button.new()
		buy_btn.text = "$%d - BUY" % info["cost"]
		buy_btn.custom_minimum_size = Vector2(100, 30)
		buy_btn.disabled = is_owned or NetworkManager.team_credits < info["cost"]

		# Conectăm butonul de buy la cumpărare
		buy_btn.pressed.connect(func(): _buy_block(block_id, info["cost"]))

		item_hbox.add_child(info_vbox)
		item_hbox.add_child(buy_btn)

		shop_vbox.add_child(item_hbox)

func _buy_block(block_id: String, cost: int) -> void:
	if not block_id in owned_blocks:
		# Solicităm serverului să scadă banii
		rpc_id(1, "request_buy_block", block_id, cost)

@rpc("any_peer", "call_local")
func request_buy_block(block_id: String, cost: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: sender_id = multiplayer.get_unique_id()

	if NetworkManager.team_credits >= cost:
		NetworkManager.add_credits(-cost)
		# Răspundem clientului că a cumpărat cu succes
		if sender_id == multiplayer.get_unique_id():
			receive_bought_block(block_id)
		else:
			rpc_id(sender_id, "receive_bought_block", block_id)

@rpc("any_peer", "call_local")
func receive_bought_block(block_id: String) -> void:
	if not block_id in owned_blocks:
		owned_blocks.append(block_id)
		# Re-populăm magazinul local ca să se facă update la prețuri și stări de deținere
		if shop_ui and shop_ui.visible:
			_populate_shop_items()
		# Update HUD
		_update_hud()


# --- DETECTARE ȘI INTERACȚIUNE CU LOOT ---
func _process_raycast() -> void:
	if not raycast or not pickup_prompt:
		return

	if raycast.is_colliding():
		var collider = raycast.get_collider()
		if collider:
			if collider.is_in_group("loot"):
				var rarity_str = collider.rarity.to_upper()
				var price_val = collider.price
				var rarity_col = collider.item_color

				pickup_prompt.text = "[E] Pick Up %s Item ($%d)" % [rarity_str, price_val]
				pickup_prompt.self_modulate = rarity_col
				pickup_prompt.visible = true
				return
			elif collider.is_in_group("door"):
				pickup_prompt.text = collider.get_prompt()
				pickup_prompt.self_modulate = Color(0, 0.9, 0.8, 1) # Cyan neon accent
				pickup_prompt.visible = true
				return

	pickup_prompt.visible = false

func _try_pickup() -> void:
	if not raycast.is_colliding():
		return

	var collider = raycast.get_collider()
	if collider:
		if collider.is_in_group("loot"):
			# Verificăm dacă avem loc liber în inventar înainte de a cere serverului pickup-ul
			var free_slot = inventory.find(null)
			if free_slot == -1:
				print("Inventarul este plin! Nu poți colecta mai mult.")
				return

			# Trimitem cerere către server pentru procesare sigură (evitând pickup-uri multiple)
			rpc_id(1, "request_pickup", collider.get_path())
		elif collider.is_in_group("door"):
			# Trimitem cerere către server pentru teleportare sigură între uși
			rpc_id(1, "request_door_interact", collider.get_path())

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
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	var item_node = get_node_or_null(item_path)

	if item_node and item_node.is_in_group("loot"):
		var item_rarity = item_node.rarity
		var item_price = item_node.price
		var item_color = item_node.item_color

		# Eliminăm obiectul din lume pe server (care se propagă clienților)
		item_node.queue_free()

		# Notificăm clientul trimițător să îl adauge în inventar
		if sender_id == multiplayer.get_unique_id():
			add_to_inventory(item_rarity, item_price, item_color)
		else:
			rpc_id(sender_id, "add_to_inventory", item_rarity, item_price, item_color)

@rpc("any_peer", "call_local", "reliable")
func teleport_to(target_pos: Vector3) -> void:
	if is_multiplayer_authority():
		global_position = target_pos

@rpc("any_peer", "call_local")
func request_door_interact(door_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	var door_node = get_node_or_null(door_path)

	if door_node and door_node.is_in_group("door"):
		var target_pos = door_node.target_position
		if target_pos != Vector3.ZERO:
			if sender_id == multiplayer.get_unique_id():
				global_position = target_pos
			else:
				rpc_id(sender_id, "teleport_to", target_pos)

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

@rpc("call_local", "reliable")
func clear_inventory() -> void:
	for i in range(4):
		inventory[i] = null
	active_slot_index = 0
	active_item_color = Color(0, 0, 0, 0)
	_update_hud()
	_update_hand_visual_for_all()

@rpc("any_peer", "call_local")
func request_drop(p_rarity: String, p_price: int, p_color: Color, spawn_pos: Vector3, throw_vel: Vector3) -> void:
	if not multiplayer.is_server():
		return

	# Instanțiem piesa de loot în lumea 3D de pe server
	var loot_item = LOOT_SCENE.instantiate()

	# Găsim un container potrivit pentru loot în funcție de scena activă
	var loot_container = null
	var current_scene = get_tree().current_scene
	if current_scene:
		if current_scene.has_node("DungeonGenerator/Loot"):
			loot_container = current_scene.get_node("DungeonGenerator/Loot")
		elif current_scene.has_node("Loot"):
			loot_container = current_scene.get_node("Loot")

	if loot_container:
		loot_container.add_child(loot_item, true)
	else:
		get_parent().add_child(loot_item, true)

	# Setăm poziția GLOBALĂ după ce nodul a fost adăugat în arbore!
	loot_item.global_position = spawn_pos

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

	# Actualizăm eticheta de credite
	if hud.has_node("CreditsLabel"):
		hud.get_node("CreditsLabel").text = "Credits: $%d" % NetworkManager.team_credits

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
