@tool
class_name GoldGdt_Pawn extends Node3D

@export_group("Components")
@export var View : GoldGdt_View
@export var Camera : GoldGdt_Camera

@export_group("On Ready")
@export_range(-89, 89) var start_view_pitch : float = 0 ## How the vertical view of the pawn should be rotated on ready. The default value is 0.
@export var start_view_yaw : float = 0 ## How the horizontal view of the pawn should be rotated on ready. The default values is 0.

# --- Visibility / Layers ---
# Local-only layer used to hide THIS client's own world model from their camera
# without affecting visibility of remote players.
const LOCAL_OWN_MODEL_LAYER: int = 1 << 5

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
	
	# Configure visibility for non-networked players
	# Only apply if this pawn is NOT managed by NetworkedPlayer (to avoid double-application)
	if not _is_managed_by_networked_player():
		call_deferred("_configure_local_player_model_visibility")
		call_deferred("_configure_local_camera_visibility")

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

func _is_managed_by_networked_player() -> bool:
	"""Check if this pawn is managed by a NetworkedPlayer parent."""
	var parent = get_parent()
	while parent:
		# Check if parent is a NetworkedPlayer instance
		# Try multiple methods for robustness
		if parent.has_method("is_local_player"):
			# NetworkedPlayer has this method
			return true
		# Check script path as fallback
		if parent.get_script():
			var script_path = parent.get_script().get_path()
			if script_path.ends_with("NetworkedPlayer.gd"):
				return true
		parent = parent.get_parent()
	return false

func _get_player_model_root() -> Node3D:
	"""Get the PlayerModel node root."""
	var model_root := get_node_or_null("Body/PlayerModel") as Node3D
	if model_root:
		return model_root
	# Fallback: try to find by name anywhere under the pawn
	return find_child("PlayerModel", true, false) as Node3D

func _configure_local_player_model_visibility() -> void:
	"""Move the local player's own world model to a local-only render layer.
	
	This keeps the shared world-model layer visible so other players remain visible,
	while hiding only this client's own body from their camera via cull_mask.
	"""
	var model_root := _get_player_model_root()
	if not model_root:
		return
	
	# Re-layer all meshes under the player model root to a local-only layer on THIS client.
	for child in model_root.get_children():
		_set_mesh_layer_recursive(child, LOCAL_OWN_MODEL_LAYER)
	
	# Also hide the compass (if it exists)
	_configure_compass_visibility()

func _set_mesh_layer_recursive(node: Node, layer_mask: int) -> void:
	"""Recursively set layer mask on all MeshInstance3D nodes."""
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers = layer_mask
	for c in node.get_children():
		_set_mesh_layer_recursive(c, layer_mask)

func _configure_compass_visibility() -> void:
	"""Move the compass to a local-only render layer so the player can't see it."""
	# Find compass node (typically at Body/compass)
	var compass := get_node_or_null("Body/compass") as Node3D
	if not compass:
		# Fallback: try to find by name anywhere under the pawn
		compass = find_child("compass", true, false) as Node3D
	
	if compass:
		# Re-layer all meshes under the compass to a local-only layer
		_set_mesh_layer_recursive(compass, LOCAL_OWN_MODEL_LAYER)

func _configure_local_camera_visibility() -> void:
	"""Configure local player's camera to hide their own world model layer."""
	# Get the actual Camera3D node (same path as NetworkedPlayer uses)
	var camera_3d := get_node_or_null("Interpolated Camera/Arm/Arm Anchor/Camera") as Camera3D
	if not camera_3d:
		# Fallback: try to find Camera3D through GoldGdt_Camera wrapper
		if Camera and Camera.camera and Camera.camera is Camera3D:
			camera_3d = Camera.camera as Camera3D
		else:
			# Last resort: search for any Camera3D in the scene
			camera_3d = find_child("Camera", true, false) as Camera3D
	
	if not camera_3d:
		return
	
	# Ensure camera has a sane default cull mask (all layers) if unset.
	if camera_3d.cull_mask == 0:
		camera_3d.cull_mask = 0xFFFFFFFF
	
	# Hide ONLY the local-only layer for this camera; remote players remain visible
	# on the shared PLAYER_WORLD_MODEL_LAYER.
	camera_3d.cull_mask &= ~LOCAL_OWN_MODEL_LAYER
