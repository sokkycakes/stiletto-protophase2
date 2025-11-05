@icon("res://addons/GoldGdt/src/gdticon.png")
class_name GoldGdt_View extends Node

@export var Parameters : PlayerParameters
@export var Body : GoldGdt_Body
@export var enable_roll: bool = true # New export variable to control roll

@export_subgroup("Gimbal")
@export var horizontal_view : Node3D ## Y-axis Camera Mount gimbal.
@export var vertical_view : Node3D ## X-axis Camera Mount gimbal.
@export var camera_mount : Node3D ## Used for player view aesthetics such as view tilt and bobbing.

var lock_on_target: Node3D = null
var _lock_focus: Node3D = null # The exact node we look at (AimTarget if present)

func _physics_process(_delta) -> void:
	if _lock_focus and is_instance_valid(_lock_focus):
		# --- Horizontal (Yaw) ---
		# Rotate the horizontal gimbal to look at the target, but only on the Y axis.
		var target_pos = _lock_focus.global_position
		var h_view_pos = horizontal_view.global_position
		var target_pos_flat = target_pos
		target_pos_flat.y = h_view_pos.y
		horizontal_view.look_at(target_pos_flat, Vector3.UP)

		# --- Vertical (Pitch) ---
		# Manually calculate the pitch angle to avoid corrupting the vertical_view's transform.
		var v_view_pos = vertical_view.global_position
		var direction_global = (target_pos - v_view_pos).normalized()
		
		# Convert the global direction to the horizontal_view's local space to correctly calculate pitch.
		var direction_local = horizontal_view.global_transform.basis.transposed() * direction_global
		
		# Calculate pitch from the local direction's y and z components.
		var pitch = atan2(direction_local.y, -direction_local.z)
		vertical_view.rotation = Vector3(clamp(pitch, deg_to_rad(-89), deg_to_rad(89)), 0.0, 0.0)
		vertical_view.orthonormalize()
		# Clear any unintended roll from horizontal gimbal as a safety net.
		horizontal_view.rotation.x = 0.0
		horizontal_view.rotation.z = 0.0
		horizontal_view.orthonormalize()

	# Add some view bobbing to the Camera Mount
	_camera_mount_bob()
	
	if enable_roll:
		camera_mount.rotation.z = _calc_roll(Parameters.ROLL_ANGLE, Parameters.ROLL_SPEED)*2

# Manipulates the Camera Mount gimbals.
func _handle_camera_input(look_input: Vector2) -> void:
	if lock_on_target:
		return
	horizontal_view.rotate_object_local(Vector3.DOWN, look_input.x)
	horizontal_view.orthonormalize()
	
	vertical_view.rotate_object_local(Vector3.LEFT, look_input.y)
	vertical_view.orthonormalize()
	
	vertical_view.rotation.x = clamp(vertical_view.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	vertical_view.orthonormalize()

func set_lock_on_target(target: Node3D):
	lock_on_target = target
	if lock_on_target and is_instance_valid(lock_on_target) and lock_on_target.has_node("AimTarget"):
		_lock_focus = lock_on_target.get_node("AimTarget") as Node3D
	else:
		_lock_focus = lock_on_target

# Creates a sinusoidal Camera Mount bobbing motion whilst moving.
func _camera_mount_bob() -> void:
	var bob : float
	var simvel : Vector3
	simvel = Body.velocity
	simvel.y = 0
	
	if Parameters.BOB_FREQUENCY == 0.0 or Parameters.BOB_FRACTION == 0:
		return
	
	if Body.is_on_floor():
		bob = lerp(0.0, sin(Time.get_ticks_msec() * Parameters.BOB_FREQUENCY) / Parameters.BOB_FRACTION, (simvel.length() / 2.0) / Parameters.FORWARD_SPEED)
	else:
		bob = 0.0
	camera_mount.position.y = lerp(camera_mount.position.y, bob, 0.5)

# Returns a value for how much the Camera Mount should tilt to the side.
func _calc_roll(rollangle: float, rollspeed: float) -> float:
	
	if Parameters.ROLL_ANGLE == 0.0 or Parameters.ROLL_SPEED == 0:
		return 0
	
	var side = Body.velocity.dot(horizontal_view.transform.basis.x)
	
	var roll_sign = 1.0 if side < 0.0 else -1.0
	
	side = absf(side)
	
	var value = rollangle
	
	if (side < rollspeed):
		side = side * value / rollspeed
	else:
		side = value
	
	return side * roll_sign

func set_roll_enabled(enabled: bool) -> void:
	enable_roll = enabled
	if not enabled:
		# Immediately reset roll to 0 when disabled
		camera_mount.rotation.z = 0.0
