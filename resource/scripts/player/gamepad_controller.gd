extends Node

class_name GamepadController

@export_group("Gamepad Settings")
@export var right_stick_sensitivity: float = 12.0  # Match GoldGdt's MOUSE_SENSITIVITY
@export var deadzone: float = 0.1
@export var invert_y: bool = false

var view_control: Node
var last_right_stick_input: Vector2 = Vector2.ZERO

func _ready():
	# Get the View Control node
	view_control = get_node("/root/Node3D/ss_player/View Control")
	if view_control == null:
		push_error("GamepadController: Could not find View Control node!")

func _process(_delta):
	if view_control == null:
		return
		
	# Get right stick input
	var right_stick = Input.get_vector("right_stick_left", "right_stick_right", "right_stick_up", "right_stick_down")
	
	# Apply deadzone
	if right_stick.length() < deadzone:
		right_stick = Vector2.ZERO
	else:
		# Normalize the input after deadzone
		right_stick = right_stick.normalized() * ((right_stick.length() - deadzone) / (1.0 - deadzone))
	
	# Apply sensitivity
	right_stick *= right_stick_sensitivity
	
	# Invert Y axis if enabled
	if invert_y:
		right_stick.y = -right_stick.y
	
	# Only process input if it's different from last frame
	if right_stick != last_right_stick_input:
		# Convert to degrees per unit (similar to mouse input)
		var degrees_per_unit: float = 0.0001
		right_stick *= degrees_per_unit
		
		# Send to View Control
		view_control._handle_camera_input(right_stick)
		
		last_right_stick_input = right_stick 