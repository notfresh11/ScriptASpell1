# scripts/interactables/blue_platform.gd
extends Area3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.has_method("get_multiplayer_authority") and body.is_multiplayer_authority():
		if body.has_method("open_shop"):
			body.open_shop(true)

func _on_body_exited(body: Node3D) -> void:
	if body.has_method("get_multiplayer_authority") and body.is_multiplayer_authority():
		if body.has_method("open_shop"):
			body.open_shop(false)
