# scripts/dungeon/dungeon_torch.gd
extends OmniLight3D

@export var base_energy: float = 1.2
@export var flicker_speed: float = 6.0
@export var flicker_strength: float = 0.2

var time: float = 0.0

func _ready() -> void:
	time = randf() * 100.0 # Decalaj de timp pentru a nu pâlpâi toate torțele la fel!

func _process(delta: float) -> void:
	time += delta * flicker_speed
	var flicker = sin(time) * cos(time * 0.8) * 0.6 + sin(time * 1.6) * 0.4
	light_energy = base_energy + (flicker * flicker_strength)
