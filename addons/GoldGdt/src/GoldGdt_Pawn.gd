@tool
class_name GoldGdt_Pawn extends Node3D

@export_group("Components")
@export var View : GoldGdt_View
@export var Camera : GoldGdt_Camera

@export_group("On Ready")
@export_range(-89, 89) var start_view_pitch : float = 0 ## How the vertical view of the pawn should be rotated on ready. The default value is 0.
@export var start_view_yaw : float = 0 ## How the horizontal view of the pawn should be rotated on ready. The default values is 0.

func _process(delta):
	# Purely for visuals, to show you the camera rotation.
	if Engine.is_editor_hint():
		if View and Camera:
			_override_view_rotation(Vector2(deg_to_rad(start_view_yaw), deg_to_rad(start_view_pitch)))

func _ready():
	self.add_to_group("player")
	# Only call _override_view_rotation if both View and Camera are assigned
	if View and Camera:
		_override_view_rotation(Vector2(deg_to_rad(start_view_yaw), deg_to_rad(start_view_pitch)))

## Forces camera rotation based on a Vector2 containing yaw and pitch, in degrees.
func _override_view_rotation(rotation : Vector2) -> void:
	# Add null checks to prevent errors when components are not assigned
	if not View or not Camera:
		return
		
	View.horizontal_view.rotation.y = rotation.x
	View.horizontal_view.orthonormalize()
	
	View.vertical_view.rotation.x = rotation.y
	View.vertical_view.orthonormalize()
	
	View.vertical_view.rotation.x = clamp(View.vertical_view.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	View.vertical_view.orthonormalize()
	
	Camera.global_rotation = View.camera_mount.global_rotation
	Camera.orthonormalize()
