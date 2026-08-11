# scripts/interactables/dungeon_door.gd
extends StaticBody3D

@export var is_exit: bool = false
@export var target_door_path: NodePath = NodePath("")

# Dacă nu avem legat direct nodul, putem folosi o poziție globală
var target_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("door")

func get_prompt() -> String:
	if is_exit:
		return "[E] Exit Dungeon"
	else:
		return "[E] Enter Dungeon"
