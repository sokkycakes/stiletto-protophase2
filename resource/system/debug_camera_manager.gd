extends Node

# Debug camera settings
@export var base_move_speed: float = 10.0
@export var speed_boost_multiplier: float = 3.0
@export var sensitivity: float = 0.002 # Radians per pixel
@export var speed_scroll_increment: float = 2.0
@export var min_speed: float = 1.0
@export var max_speed: float = 100.0

# Camera references
var original_camera: Camera3D
var debug_camera: Camera3D
var is_debug_active: bool = false

# New: track orientation explicitly to avoid gimbal issues
var yaw := 0.0  # Rotation around Y (left / right)
var pitch := 0.0  # Rotation around X (up / down)

# New: reference to the player node so we can toggle its scripts
var player_node: Node = null

# Remember last debug camera transform between activations
var saved_transform: Transform3D = Transform3D.IDENTITY
var has_saved_transform: bool = false

# Transform to reset to (position/orientation at first activation each session)
var home_transform: Transform3D = Transform3D.IDENTITY

# Movement state
var current_move_speed: float

func _ready() -> void:
	current_move_speed = base_move_speed
	
	# Create the debug camera
	_ensure_debug_camera()
	
	# Set initial cull mask to exclude viewmodel layer (layer 3/bit 2)
	# Default mask is 4294967295 (all bits set), we clear bit 2
	debug_camera.cull_mask = 4294967291  # 0xFFFFFFFB
	
	# Store the original camera
	original_camera = get_viewport().get_camera_3d()

func _input(event: InputEvent) -> void:
	# Ensure camera reference is valid (handles scene changes)
	_ensure_debug_camera()
	# Handle camera toggle
	if event.is_action_pressed("toggle_debug_camera"):
		toggle_debug_camera()
	
	# Only process camera controls if debug camera is active
	if not is_debug_active or not debug_camera.is_current():
		return
		
	# Mouse look
	if event is InputEventMouseMotion:
		# Update yaw / pitch based on relative mouse motion
		yaw -= event.relative.x * sensitivity
		pitch -= event.relative.y * sensitivity
		pitch = clamp(pitch, -PI/2, PI/2)
		
		debug_camera.rotation = Vector3(pitch, yaw, 0.0)
	
	# Speed adjustment with mouse wheel or right-click player-control toggle
	if event is InputEventMouseButton:
		# Mouse wheel for speed
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			adjust_speed(speed_scroll_increment)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			adjust_speed(-speed_scroll_increment)
		# Right mouse button toggles player control while debug cam is active
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and is_debug_active:
			_reset_camera_orientation()

func _process(delta: float) -> void:
	# Keep camera instance valid
	_ensure_debug_camera()
	# Only process movement if debug camera is active
	if not is_debug_active or not debug_camera.is_inside_tree():
		return
		
	var direction := Vector3.ZERO
	var effective_speed := current_move_speed
	
	# Check for speed boost
	if Input.is_action_pressed("pm_boost"):
		effective_speed *= speed_boost_multiplier
	
	# Movement input using existing player movement actions
	if Input.is_action_pressed("pm_moveforward"):
		direction -= debug_camera.transform.basis.z
	if Input.is_action_pressed("pm_movebackward"):
		direction += debug_camera.transform.basis.z
	if Input.is_action_pressed("pm_moveleft"):
		direction -= debug_camera.transform.basis.x
	if Input.is_action_pressed("pm_moveright"):
		direction += debug_camera.transform.basis.x
	if Input.is_action_pressed("pm_swimup") or Input.is_action_pressed("pm_jump"):
		direction += Vector3.UP
	if Input.is_action_pressed("pm_swimdown") or Input.is_action_pressed("pm_duck"):
		direction += Vector3.DOWN

	debug_camera.global_position += direction.normalized() * effective_speed * delta

func toggle_debug_camera() -> void:
	if is_debug_active:
		# Switch back to original camera
		if original_camera and is_instance_valid(original_camera):
			original_camera.make_current()
		# Save current debug camera transform so we can restore next time
		saved_transform = debug_camera.global_transform
		has_saved_transform = true
		is_debug_active = false
		print("Debug camera deactivated")
	else:
		# Switch to debug camera
		_ensure_debug_camera()
		var current_camera = get_viewport().get_camera_3d()
		# Capture home position the first time we activate in a session
		if not has_saved_transform:
			if current_camera and is_instance_valid(current_camera):
				home_transform = current_camera.global_transform
			else:
				home_transform = debug_camera.global_transform
		if has_saved_transform:
			debug_camera.global_transform = saved_transform
			pitch = debug_camera.rotation.x
			yaw = debug_camera.rotation.y
		elif current_camera and is_instance_valid(current_camera):
			debug_camera.global_transform = current_camera.global_transform
			pitch = debug_camera.rotation.x
			yaw = debug_camera.rotation.y
			original_camera = current_camera
		debug_camera.make_current()
		is_debug_active = true
		print("Debug camera activated - Speed: %.1f" % current_move_speed)

func adjust_speed(delta_speed: float) -> void:
	current_move_speed = clamp(current_move_speed + delta_speed, min_speed, max_speed)
	print("Debug camera speed: %.1f" % current_move_speed)

func get_debug_camera() -> Camera3D:
	return debug_camera

func is_debug_camera_active() -> bool:
	return is_debug_active 

func _reset_camera_orientation() -> void:
	if debug_camera and is_instance_valid(debug_camera):
		debug_camera.global_transform = home_transform
		pitch = debug_camera.rotation.x
		yaw = debug_camera.rotation.y
		print("Debug camera reset to home position")

func _ensure_debug_camera() -> void:
	if debug_camera == null or not is_instance_valid(debug_camera):
		debug_camera = Camera3D.new()
		debug_camera.name = "DebugSpectatorCamera"
		debug_camera.current = false
		debug_camera.cull_mask = 4294967291
		var parent = get_tree().current_scene if get_tree().current_scene else get_tree().root
		parent.add_child(debug_camera)
	# If the scene changed and the camera is no longer in the tree, re-attach it
	elif not debug_camera.is_inside_tree():
		# Remove from old parent if it still has one
		if debug_camera.get_parent():
			debug_camera.get_parent().remove_child(debug_camera)
		var parent = get_tree().current_scene if get_tree().current_scene else get_tree().root
		parent.add_child(debug_camera) 
