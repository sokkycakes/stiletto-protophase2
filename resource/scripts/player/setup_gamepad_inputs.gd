extends Node

func _ready():
	# Right stick actions
	if not InputMap.has_action("right_stick_left"):
		InputMap.add_action("right_stick_left")
	if not InputMap.has_action("right_stick_right"):
		InputMap.add_action("right_stick_right")
	if not InputMap.has_action("right_stick_up"):
		InputMap.add_action("right_stick_up")
	if not InputMap.has_action("right_stick_down"):
		InputMap.add_action("right_stick_down")
		
	# Add gamepad right stick events
	var right_stick_left_event = InputEventJoypadMotion.new()
	right_stick_left_event.axis = JOY_AXIS_RIGHT_X
	right_stick_left_event.axis_value = -1.0
	InputMap.action_add_event("right_stick_left", right_stick_left_event)
	
	var right_stick_right_event = InputEventJoypadMotion.new()
	right_stick_right_event.axis = JOY_AXIS_RIGHT_X
	right_stick_right_event.axis_value = 1.0
	InputMap.action_add_event("right_stick_right", right_stick_right_event)
	
	var right_stick_up_event = InputEventJoypadMotion.new()
	right_stick_up_event.axis = JOY_AXIS_RIGHT_Y
	right_stick_up_event.axis_value = -1.0
	InputMap.action_add_event("right_stick_up", right_stick_up_event)
	
	var right_stick_down_event = InputEventJoypadMotion.new()
	right_stick_down_event.axis = JOY_AXIS_RIGHT_Y
	right_stick_down_event.axis_value = 1.0
	InputMap.action_add_event("right_stick_down", right_stick_down_event) 