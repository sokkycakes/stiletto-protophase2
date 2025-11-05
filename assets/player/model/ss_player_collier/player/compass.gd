extends Node3D

@export var camera_path: NodePath = NodePath("../../Interpolated Camera/Arm/Arm Anchor/Camera")

var camera: Camera3D
# Holds the rotation offset (basis) between the compass and the camera as it was when the scene started.
var _rotation_offset: Basis

func _ready() -> void:
    # Attempt to resolve the camera from the given path first.
    if camera_path != NodePath(""):
        camera = get_node_or_null(camera_path)
    
    # Fallback: use the current active camera in the scene, if any.
    if camera == null:
        camera = get_viewport().get_camera_3d()
    
    if camera == null:
        push_warning("Compass: No camera found – rotation sync will be disabled.")
        return  # No camera => nothing more to initialise

    # Record the initial rotational difference so we can preserve any pre-set orientation.
    # We want: compass_basis_initial = camera_basis_initial * offset
    # => offset = camera_basis_initial.inverse() * compass_basis_initial
    _rotation_offset = camera.global_transform.basis.inverse() * global_transform.basis

func _process(delta: float) -> void:
    if camera == null:
        return

    # Preserve the original position but copy the camera's rotation so the compass
    # always points the same way the player is looking.
    var new_transform := global_transform
    new_transform.basis = camera.global_transform.basis * _rotation_offset
    global_transform = new_transform 