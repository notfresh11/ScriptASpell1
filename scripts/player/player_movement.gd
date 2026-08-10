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
		# Activăm input-ul și camera doar pentru jucătorul local
		set_multiplayer_authority(player_id)

@onready var camera: Camera3D = $Camera3D
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer

func _ready() -> void:
	# Dacă nu avem autoritate multiplayer, dezactivăm camera locală și procesarea de mișcare locală
	if not is_multiplayer_authority():
		camera.current = false
		set_process_unhandled_input(false)
		set_physics_process(false)
	else:
		camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Mișcare cameră cu mouse-ul
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, -deg_to_rad(80), deg_to_rad(80))

	# Apăsare tasta ESC pentru eliberarea mouse-ului (util pentru testare)
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	# Adăugăm gravitația
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Săritură
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Preluăm direcția de mișcare de la taste (WASD / Săgeți)
	var input_dir: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
