# scripts/interactables/loot_item.gd
extends RigidBody3D

@export var loot_id: String = ""
@export var rarity: String = "common"
@export var price: int = 10
@export var item_color: Color = Color(0.5, 0.5, 0.5, 1) :
	set(value):
		item_color = value
		_update_material()

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	_update_material()

func _update_material() -> void:
	if is_node_ready() and mesh_instance:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = item_color
		mat.roughness = 0.8
		mesh_instance.material_override = mat

# Funcție helper pentru a seta proprietățile dintr-o singură linie
func init_loot(p_id: String, p_rarity: String, p_price: int, p_color: Color) -> void:
	loot_id = p_id
	rarity = p_rarity
	price = p_price
	item_color = p_color
