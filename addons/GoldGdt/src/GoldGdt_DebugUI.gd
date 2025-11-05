extends Control

@export_group("Player Components")
@export var Controls : GoldGdt_Controls
@export var View : GoldGdt_View
@export var Body : GoldGdt_Body

@export_group("Component Info Labels")
@export var GameInfo : Label
@export var ControlsInfo : Label
@export var ViewInfo : Label
@export var BodyInfo : Label

func _process(delta):
	_write_game_ui()
	_write_input_ui()
	_write_view_ui()
	_write_body_ui()

func _write_game_ui():
	# Only update if GameInfo label is assigned
	if not GameInfo:
		return
		
	var format = "Rendering FPS: %s\nPhysics Tick Rate: %s\nPhysics Frame Time: %s"
	var str = format % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second, get_physics_process_delta_time()]
	GameInfo.text = str
	pass
	
func _write_input_ui():
	# Only update if Controls component and ControlsInfo label are assigned
	if not Controls or not ControlsInfo:
		return
		
	var format = "Movement Input: %s\nWish Direction: %s\nWish Speed: %s m/s (%s u/s)\nJump Pressed: %s\nDuck Pressed: %s\nMovement Disabled: %s\nCamera Disabled: %s"
	var str = format % [Controls.movement_input, Controls.move_dir.normalized(), round(Controls.move_dir.length()), round(Controls.move_dir.length() * 39.37), Controls.jump_on, Controls.duck_on, Controls.movement_disabled, Controls.camera_disabled]
	ControlsInfo.text = str
	pass
	
func _write_view_ui():
	# Only update if View component, Body component, and ViewInfo label are assigned
	if not View or not Body or not ViewInfo:
		return
		
	var format = "View Angles: %s\nView Offset: %s"
	var str = format % [View.camera_mount.global_rotation_degrees, Body.offset]
	ViewInfo.text = str
	pass
	
func _write_body_ui():
	# Only update if Body component and BodyInfo label are assigned
	if not Body or not BodyInfo:
		return
		
	var format = "Position: %s\nVelocity: %s\nSpeed: %s m/s (%s u/s)\nDucking: %s\nDucked: %s"
	var h_vel = Vector2(Body.velocity.x, Body.velocity.z)
	var str = format % [Body.global_position, Body.velocity, round(h_vel.length()), round(h_vel.length() * 39.37), Body.ducking, Body.ducked]
	BodyInfo.text = str
	pass
