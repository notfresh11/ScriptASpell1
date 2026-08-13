# scripts/autoload/chaos_engine.gd
extends Node

# Semnal declanșat când o eroare este interceptată
signal error_intercepted(player_id: int, error_message: String)

const GLITCH_CUBE_SCENE: PackedScene = preload("res://scenes/interactables/glitch_cube.tscn")

@rpc("any_peer", "call_local", "reliable")
func trigger_runtime_error(player_id: int, error_message: String, spawn_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return

	print("CHAOS ENGINE ACTIVE: Player ", player_id, " caused error: ", error_message)
	error_intercepted.emit(player_id, error_message)

	# Spawnează cubul fizic static cu logoul Godot în fața jucătorului pe server
	var glitch_cube = GLITCH_CUBE_SCENE.instantiate()

	var current_scene = get_tree().current_scene
	var container = null
	if current_scene:
		if current_scene.has_node("Loot"):
			container = current_scene.get_node("Loot")
		elif current_scene.has_node("DungeonGenerator/Loot"):
			container = current_scene.get_node("DungeonGenerator/Loot")

	if container:
		container.add_child(glitch_cube, true)
	else:
		if current_scene:
			current_scene.add_child(glitch_cube, true)
		else:
			get_parent().add_child(glitch_cube, true)

	glitch_cube.global_position = spawn_pos
