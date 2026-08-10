# scripts/player/player_movement.gd
extends CharacterBody3D

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5
const MOUSE_SENSITIVITY: float = 0.003

# Preluăm gravitația din setările Godot
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# ID-ul unic de multiplayer al acestui jucător
@export var player_id: int = 1 :
	set(value):
		player_id = value
		set_multiplayer_authority(player_id)
		if is_multiplayer_authority() and is_node_ready():
			_setup_local_player()

@onready var camera: Camera3D = $Camera3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	_setup_input_actions()

	if is_multiplayer_authority():
		_setup_local_player()
	else:
		camera.current = false

# Inițializăm dinamic acțiunile pentru WASD și Săgeți + Space
func _setup_input_actions() -> void:
	var actions = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_forward": [KEY_W, KEY_UP],
		"move_backward": [KEY_S, KEY_DOWN],
		"jump": [KEY_SPACE]
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
	# Ascundem propriul model 3D pentru a nu bloca vederea camerei din interior
	if mesh_instance:
		mesh_instance.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Rotim camera doar dacă mouse-ul este capturat (meniul este închis)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(80), deg_to_rad(80))

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Adăugăm gravitația
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Săritură
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Preluăm direcția de mișcare de la taste (WASD / Săgeți)
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
