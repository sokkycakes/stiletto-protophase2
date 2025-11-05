extends Node3D

# Lag parameters
@export_group("Position Lag")
@export var pos_lag_speed: float = 10.0  # How quickly position catches up
@export var pos_lag_scale: float = 0.1   # How much position lag is applied
@export var pos_lag_max: float = 0.5     # Maximum position lag distance

@export_group("Rotation Lag")
@export var rot_lag_speed: float = 15.0  # How quickly rotation catches up
@export var rot_lag_scale: float = 0.15  # How much rotation lag is applied
@export var rot_lag_max: float = 0.5     # Maximum rotation lag in radians

@export_group("Velocity Lag")
@export var vel_lag_scale: float = 0.05  # How much velocity affects lag
@export var vel_lag_max: float = 0.2     # Maximum velocity-based lag

var target_node: Node3D
var base_transform: Transform3D
var last_global_transform: Transform3D
var current_offset: Transform3D = Transform3D.IDENTITY

func _ready():
	# Find the viewmodel node (starts with v_)
	for child in get_children():
		if child.name.begins_with("v_"):
			target_node = child
			base_transform = target_node.transform
			last_global_transform = global_transform
			break

func _process(delta: float):
	if not target_node:
		return
		
	# Get current transform in global space
	var current_global_transform = global_transform
	
	# Calculate the transform delta in local space
	var transform_delta = last_global_transform.affine_inverse() * current_global_transform
	
	# Extract position and rotation components
	var pos_delta = transform_delta.origin
	var rot_delta = transform_delta.basis.get_euler()
	
	# Convert position delta to local space
	var local_pos_delta = Vector3(
		-pos_delta.z,  # Forward/back movement maps to Z
		pos_delta.y,   # Up/down movement maps to Y
		-pos_delta.x   # Left/right movement maps to X
	)
	
	# Get velocity-based lag
	var velocity = local_pos_delta / delta
	var vel_lag = -velocity * vel_lag_scale
	vel_lag = vel_lag.clamp(Vector3(-vel_lag_max, -vel_lag_max, -vel_lag_max), 
						   Vector3(vel_lag_max, vel_lag_max, vel_lag_max))
	
	# Calculate target offset
	var target_pos = -local_pos_delta * pos_lag_scale + vel_lag
	target_pos = target_pos.clamp(
		Vector3(-pos_lag_max, -pos_lag_max, -pos_lag_max),
		Vector3(pos_lag_max, pos_lag_max, pos_lag_max)
	)
	
	var target_rot = -rot_delta * rot_lag_scale
	target_rot = target_rot.clamp(
		Vector3(-rot_lag_max, -rot_lag_max, -rot_lag_max),
		Vector3(rot_lag_max, rot_lag_max, rot_lag_max)
	)
	
	# Create target transform
	var target_transform = Transform3D(Basis.from_euler(target_rot), target_pos)
	
	# Smoothly update current offset
	current_offset = current_offset.interpolate_with(target_transform, rot_lag_speed * delta)
	
	# Apply the offset to the viewmodel while maintaining its base transform
	target_node.transform = base_transform * current_offset
	
	# Store current transform for next frame
	last_global_transform = current_global_transform
