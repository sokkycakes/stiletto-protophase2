extends Node3D

@export var camera_path: NodePath = NodePath("../../Interpolated Camera/Arm/Arm Anchor/Camera")

var camera: Camera3D
# Holds the yaw offset between the player model and the camera as it was when the scene started.
var _yaw_offset: float = 0.0

func _ready() -> void:
	# Attempt to resolve the camera from the given path first.
	if camera_path != NodePath(""):
		camera = get_node_or_null(camera_path)

	# Fallback: use the current active camera in the scene, if any.
	if camera == null:
		camera = get_viewport().get_camera_3d()

	if camera == null:
		push_warning("PlayerModelCompass: No camera found – rotation sync will be disabled.")
		return  # No camera => nothing more to initialise

	# Record the initial yaw difference so we can preserve any pre-set orientation.
	var camera_yaw := camera.global_transform.basis.get_euler().y
	var self_yaw := global_transform.basis.get_euler().y
	_yaw_offset = self_yaw - camera_yaw

func _process(delta: float) -> void:
	if camera == null:
		return

	# Preserve the original position but copy the camera's yaw (horizontal rotation) so the model
	# always faces the same horizontal direction as the camera, ignoring pitch/roll.
	var new_transform := global_transform

	var camera_yaw := camera.global_transform.basis.get_euler().y
	var target_yaw := camera_yaw + _yaw_offset

	# Preserve current scale before we overwrite the basis.
	var current_scale := new_transform.basis.get_scale()

	# Build a new rotation basis with yaw only (no pitch/roll).
	var yaw_basis := Basis.from_euler(Vector3(0.0, target_yaw, 0.0))

	# Re-apply the original scale to the new basis.
	new_transform.basis = yaw_basis.scaled(current_scale)
	global_transform = new_transform 
