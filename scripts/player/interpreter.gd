# scripts/player/interpreter.gd
class_name Interpreter
extends Object

# Listă completă de blocuri valabile în joc (definire statică pentru UI și Shop)
# Fiecare bloc are un tip, un nume prietenos, un preț, descriere și un grup (clasic vs acțiune)
static func get_available_blocks_definition() -> Dictionary:
	return {
		"IF": {
			"name": "If Condition",
			"cost": 10,
			"desc": "Check a condition (Dropdown key). Ex: IF W_pressed",
			"type": "control",
			"has_dropdown": true,
			"dropdown_options": ["W_pressed", "S_pressed", "A_pressed", "D_pressed", "E_pressed", "Q_pressed", "F_pressed", "Mouse_Moved", "Health_Low", "Always"]
		},
		"ELSE": {
			"name": "Else",
			"cost": 15,
			"desc": "Runs if the preceding IF condition was false",
			"type": "control",
			"has_dropdown": false
		},
		"WAIT": {
			"name": "Wait Time",
			"cost": 5,
			"desc": "Wait X seconds before next block",
			"type": "control",
			"has_dropdown": true,
			"dropdown_options": ["0.5", "1.0", "2.0", "5.0"]
		},
		"LOOK_MOUSE": {
			"name": "Look with Mouse",
			"cost": 10,
			"desc": "Rotates camera/head with mouse movement",
			"type": "action",
			"has_dropdown": false
		},
		"MOVE_FORWARD": {
			"name": "Move Forward",
			"cost": 10,
			"desc": "Moves the player forward",
			"type": "action",
			"has_dropdown": false
		},
		"MOVE_BACKWARD": {
			"name": "Move Backward",
			"cost": 10,
			"desc": "Moves the player backward",
			"type": "action",
			"has_dropdown": false
		},
		"MOVE_LEFT": {
			"name": "Move Left",
			"cost": 10,
			"desc": "Moves the player left",
			"type": "action",
			"has_dropdown": false
		},
		"MOVE_RIGHT": {
			"name": "Move Right",
			"cost": 10,
			"desc": "Moves the player right",
			"type": "action",
			"has_dropdown": false
		},
		"PICKUP": {
			"name": "Pickup Loot",
			"cost": 15,
			"desc": "Pick up looking loot item",
			"type": "action",
			"has_dropdown": false
		},
		"DROP": {
			"name": "Drop Loot",
			"cost": 15,
			"desc": "Drop active hand item",
			"type": "action",
			"has_dropdown": false
		},
		"SPEED": {
			"name": "Set Speed",
			"cost": 25,
			"desc": "Multiply player speed (1x, 2x, 3x)",
			"type": "action",
			"has_dropdown": true,
			"dropdown_options": ["1x", "2x", "3x"]
		},
		"NIGHT_VISION": {
			"name": "Night Vision",
			"cost": 30,
			"desc": "Toggle green neon overlay night-vision",
			"type": "action",
			"has_dropdown": false
		},
		"GLOW": {
			"name": "Glow Body/Torch",
			"cost": 20,
			"desc": "Make flashlight emit double power",
			"type": "action",
			"has_dropdown": false
		},
		"BOUNCY": {
			"name": "Bouncy Jump",
			"cost": 25,
			"desc": "Low gravity high jumping",
			"type": "action",
			"has_dropdown": false
		}
	}

# Returnează lista implicită de blocuri pentru o secțiune
static func get_default_script(section: String) -> Array:
	match section:
		"Head":
			return [
				{"type": "IF", "param": "Mouse_Moved"},
				{"type": "LOOK_MOUSE"}
			]
		"L Hand":
			return [
				{"type": "IF", "param": "E_pressed"},
				{"type": "PICKUP"}
			]
		"R Hand":
			return [
				{"type": "IF", "param": "Q_pressed"},
				{"type": "DROP"}
			]
		"L Foot":
			return [
				{"type": "IF", "param": "W_pressed"},
				{"type": "MOVE_FORWARD"},
				{"type": "IF", "param": "A_pressed"},
				{"type": "MOVE_LEFT"}
			]
		"R Foot":
			return [
				{"type": "IF", "param": "S_pressed"},
				{"type": "MOVE_BACKWARD"},
				{"type": "IF", "param": "D_pressed"},
				{"type": "MOVE_RIGHT"}
			]
		"Body":
			return [
				{"type": "IF", "param": "Health_Low"},
				{"type": "SPEED", "param": "1x"}
			]
		"Spell":
			return [] # Gol implicit
	return []
