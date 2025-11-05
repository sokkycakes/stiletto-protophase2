@tool
extends Node3D

class_name PlayerSpawner

# Scene to spawn.  Drag your player .tscn here in the Inspector.
@export var player_scene: PackedScene

# Spawn automatically when the spawner enters the scene tree.
@export var spawn_on_ready := true

# If true, the spawner node frees itself after spawning the player.
@export var self_destruct := false

# Pass-through view orientation for GoldGdt-based players.
@export_range(-89, 89) var start_view_pitch: float = 0.0
@export var start_view_yaw: float = 0.0

func _ready() -> void:
	# Ensure editor-only visuals are shown/hid appropriately.
	_update_sprite3d_visibility()
	# Prevent runtime spawning inside the editor.
	if Engine.is_editor_hint():
		return
	if spawn_on_ready:
		spawn_player()

# Show Sprite3D helpers only in editor, hide them at runtime.
func _update_sprite3d_visibility() -> void:
	for child in get_children():
		if child is Sprite3D:
			child.visible = Engine.is_editor_hint()
			# Note: No editor_only property in Godot 4 runtime; simply hide in-game.

func spawn_player() -> Node:
	"""Instantiates `player_scene`, adds it to the active scene and returns it."""
	if player_scene == null:
		push_error("[PlayerSpawner] No player_scene assigned!")
		return null

	var player: Node = player_scene.instantiate()

	# Apply start view orientation variables if present on player.
	if player.has_method("_override_view_rotation"):
		# Assign exported variables if they exist.
		if _object_has_property(player, "start_view_pitch"):
			player.start_view_pitch = start_view_pitch
		if _object_has_property(player, "start_view_yaw"):
			player.start_view_yaw = start_view_yaw
		# Call override to immediately rotate view.
		player.call("_override_view_rotation", Vector2(deg_to_rad(start_view_yaw), deg_to_rad(start_view_pitch)))

	# Also rotate a child named "PlayerModel" to match yaw so the third-person model aligns.
	var player_model: Node3D = _find_node_by_name(player, "PlayerModel")
	if player_model:
		var basis := player_model.global_transform.basis
		var euler := basis.get_euler()
		euler.y = deg_to_rad(start_view_yaw)
		basis = Basis.from_euler(euler).scaled(basis.get_scale())
		var t := player_model.global_transform
		t.basis = basis
		player_model.global_transform = t

	# Place the player exactly where this spawner is.
	if player is Node3D:
		player.global_transform = global_transform
	# Additional 2-D handling can be added if you need a 2-D spawner.

	# Add to the current active scene (root of the playable world).
	get_tree().current_scene.call_deferred("add_child", player)

	# Make player's camera current if it has one.
	call_deferred("_activate_player_camera", player)

	if self_destruct:
		queue_free()

	return player

func _activate_player_camera(player: Node) -> void:
	# Recursively search for first Camera3D or Camera2D inside the player node.
	var cam3d: Camera3D = _find_camera3d(player)
	if cam3d:
		cam3d.current = true
	else:
		var cam2d: Camera2D = _find_camera2d(player)
		if cam2d:
			cam2d.make_current()

	# Ensure any debug spectator camera is not current.
	var debug_cam := get_tree().current_scene.get_node_or_null("DebugSpectatorCamera")
	if debug_cam and debug_cam is Camera3D:
		debug_cam.current = false

# Helper: recursively find first 3D camera.
func _find_camera3d(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		var found: Camera3D = _find_camera3d(child)
		if found:
			return found
	return null

# Helper: recursively find first 2D camera.
func _find_camera2d(node: Node) -> Camera2D:
	if node is Camera2D:
		return node
	for child in node.get_children():
		var found: Camera2D = _find_camera2d(child)
		if found:
			return found
	return null 

# Helper to recursively search by node name.
func _find_node_by_name(node: Node, target_name: String) -> Node3D:
	if node.name == target_name and node is Node3D:
		return node
	for child in node.get_children():
		var found: Node3D = _find_node_by_name(child, target_name)
		if found:
			return found
	return null 

# Helper to check if an object defines a property.
func _object_has_property(obj: Object, prop_name: String) -> bool:
	for p in obj.get_property_list():
		if p.name == prop_name:
			return true
	return false 
