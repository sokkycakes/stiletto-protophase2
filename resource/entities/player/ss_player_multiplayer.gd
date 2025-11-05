extends Node

# Multiplayer player controller
# Handles input authority and synchronization for networked players

# Node references
@onready var player_root = get_parent()
@onready var body = player_root.get_node_or_null("Body")
@onready var controls = player_root.get_node_or_null("User Input")
@onready var view_control = player_root.get_node_or_null("View Control")
@onready var camera = player_root.get_node_or_null("Interpolated Camera/Arm/Arm Anchor/Camera")
@onready var player_mesh = player_root.get_node_or_null("Body/PlayerMesh")
@onready var player_model = player_root.get_node_or_null("Body/PlayerModel/Rig_SokkyComm/Skeleton3D/SokkyComm")
@onready var multiplayer_synchronizer = player_root.get_node_or_null("MultiplayerSynchronizer")

# Player state
var player_name: String = "Player"
var is_local_player: bool = false
var peer_id: int = 1

# Interpolation settings for remote players
const INTERPOLATION_SPEED = 10.0
const POSITION_THRESHOLD = 0.1
const ROTATION_THRESHOLD = 0.05

# Interpolation targets for remote players
var last_sync_position: Vector3
var last_sync_velocity: Vector3

func _ready():
	# Wait for scene to be fully ready
	await get_tree().process_frame

	# Verify critical nodes exist
	if not _verify_node_structure():
		print("ERROR: Critical nodes missing in multiplayer player scene!")
		return

	# Determine if this is the local player
	peer_id = player_root.get_multiplayer_authority()
	is_local_player = (peer_id == multiplayer.get_unique_id())

	print("=== PLAYER INITIALIZATION ===")
	print("Player root authority: ", peer_id)
	print("Local multiplayer ID: ", multiplayer.get_unique_id())
	print("Is local player: ", is_local_player)
	print("Is server: ", multiplayer.is_server())

	# Set player name
	player_name = "Player_" + str(peer_id)
	player_root.name = player_name

	# Add player to both groups for maximum compatibility
	player_root.add_to_group("players")
	player_root.add_to_group("player")

	# Simplified layer system:
	# - Layer 2: Local player's own model (hidden from their camera)
	# - Layer 3: All remote players' models (visible to everyone)
	_setup_player_visibility_layer()

	# Configure for local vs remote players
	if is_local_player:
		print("Setting up as LOCAL player")
		_setup_local_player()
	else:
		print("Setting up as REMOTE player")
		_setup_remote_player()

	# MultiplayerSynchronizer handles synchronization automatically
	# No manual signal connections needed

	print("Player initialized: ", player_name, " (Local: ", is_local_player, ")")
	print("==============================")

func _verify_node_structure() -> bool:
	# Check critical nodes and print debug info
	var missing_nodes = []

	if not body:
		missing_nodes.append("Body")
	if not controls:
		missing_nodes.append("User Input")
	if not view_control:
		missing_nodes.append("View Control")
	if not camera:
		missing_nodes.append("Interpolated Camera/Arm/Arm Anchor/Camera")
	if not player_model:
		missing_nodes.append("Body/PlayerModel/Rig_SokkyComm/Skeleton3D/SokkyComm")
	if not multiplayer_synchronizer:
		missing_nodes.append("MultiplayerSynchronizer")

	if missing_nodes.size() > 0:
		print("Missing nodes: ", missing_nodes)
		print("Available child nodes:")
		for child in player_root.get_children():
			print("  - ", child.name, " (", child.get_class(), ")")
		return false

	# Check view control structure
	if view_control:
		var horizontal_view = view_control.get_node_or_null("horizontal_view")
		var vertical_view = view_control.get_node_or_null("vertical_view")

		if not horizontal_view:
			print("Warning: horizontal_view not found in View Control")
		if not vertical_view:
			print("Warning: vertical_view not found in View Control")

	return true

func _get_horizontal_view_node() -> Node3D:
	# Try different possible paths for horizontal view
	if not body:
		return null

	var horizontal_view = body.get_node_or_null("Horizontal View")
	if horizontal_view:
		return horizontal_view

	# Try alternative paths
	if view_control:
		horizontal_view = view_control.get_node_or_null("horizontal_view")
		if horizontal_view:
			return horizontal_view

	return null

func _get_vertical_view_node() -> Node3D:
	# Try different possible paths for vertical view
	var horizontal_view = _get_horizontal_view_node()
	if not horizontal_view:
		return null

	var vertical_view = horizontal_view.get_node_or_null("Vertical View")
	if vertical_view:
		return vertical_view

	# Try alternative paths
	if view_control:
		vertical_view = view_control.get_node_or_null("vertical_view")
		if vertical_view:
			return vertical_view

	return null

func _setup_player_visibility_layer():
	"""Set up simplified layer system for multiplayer visibility"""
	print("=== SIMPLIFIED VISIBILITY LAYER SETUP ===")
	print("Player: ", player_name, " (peer_id: ", peer_id, ")")
	print("Is local player: ", is_local_player)

	if is_local_player:
		# Local player: Put model on layer 2 (will be hidden from own camera)
		if player_model:
			player_model.layers = 1 << 1  # Layer 2 (bit 1)
			print("LOCAL PLAYER: Model set to layer 2 (bitmask: ", player_model.layers, ")")

		# Configure camera to exclude layer 2 (own model) but show layer 3 (remote players)
		if camera:
			var cull_mask = 4294967295  # Start with all layers visible
			cull_mask &= ~(1 << 1)  # Remove layer 2 (own model)
			camera.cull_mask = cull_mask
			print("LOCAL PLAYER: Camera cull mask set to: ", cull_mask, " (excludes layer 2)")
	else:
		# Remote player: Put model on layer 3 (visible to all other players)
		if player_model:
			player_model.layers = 1 << 2  # Layer 3 (bit 2)
			print("REMOTE PLAYER: Model set to layer 3 (bitmask: ", player_model.layers, ")")

		# Remote players don't need camera configuration (camera is disabled)
		print("REMOTE PLAYER: Camera disabled, no cull mask changes needed")

	print("=== END VISIBILITY SETUP ===\n")

func _setup_local_player():
	# Enable input and camera for local player
	if controls:
		controls.movement_disabled = false
		controls.camera_disabled = false

	# Enable camera
	if camera:
		camera.current = true

	# Hide player mesh for local player (first person view)
	if player_mesh:
		player_mesh.visible = false

	# Set mouse capture mode
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	print("Local player setup complete")

func _setup_remote_player():
	# Disable input for remote players
	if controls:
		controls.movement_disabled = true
		controls.camera_disabled = true

	# Disable camera for remote players
	if camera:
		camera.current = false

	# Show player mesh for remote players (debug capsule - usually disabled)
	if player_mesh:
		player_mesh.visible = false  # Keep debug mesh hidden

	# Remote player models are handled by the layer system
	# Each player's model is on their unique layer and visible to other players' cameras
	print("Remote player setup complete - model visibility handled by layer system")

# No custom physics processing needed - MultiplayerSynchronizer handles everything

# Synchronization is handled automatically by MultiplayerSynchronizer

# Input handling for local player - Removed direct ui_cancel handling
# The pause menu (autoload singleton) will handle ui_cancel input via _unhandled_input()
# This allows proper pause menu functionality instead of immediately exiting to main menu

func _return_to_menu():
	# Called by pause menu when "Return to Title" is pressed
	if not is_local_player:
		return

	# Restore mouse mode for menu navigation
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Disconnect from multiplayer
	if MultiplayerManager:
		MultiplayerManager.disconnect_from_game()

	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# RPC methods for player actions

@rpc("any_peer", "call_local", "unreliable")
func sync_player_action(action: String, data: Dictionary = {}):
	# Handle synchronized player actions (shooting, etc.)
	match action:
		"shoot":
			_handle_shoot_action(data)
		"reload":
			_handle_reload_action(data)
		"take_damage":
			_handle_damage_action(data)

func _handle_shoot_action(data: Dictionary):
	# Handle weapon firing synchronization
	print("Player ", player_name, " fired weapon")
	# TODO: Implement weapon firing effects

func _handle_reload_action(data: Dictionary):
	# Handle weapon reloading synchronization
	print("Player ", player_name, " reloaded weapon")
	# TODO: Implement reload effects

func _handle_damage_action(data: Dictionary):
	# Handle damage synchronization
	var damage = data.get("damage", 0)
	print("Player ", player_name, " took ", damage, " damage")
	# TODO: Implement damage effects

# Public methods

func get_player_name() -> String:
	return player_name

func set_player_name(new_name: String):
	player_name = new_name
	player_root.name = "Player_" + str(peer_id) + "_" + new_name

func is_local() -> bool:
	return is_local_player

func get_peer_id() -> int:
	return peer_id

# Utility methods

func get_position() -> Vector3:
	return body.position if body else Vector3.ZERO

func get_velocity() -> Vector3:
	return body.velocity if body else Vector3.ZERO

func get_view_direction() -> Vector3:
	# Try to get direction from camera
	if camera:
		return -camera.global_transform.basis.z

	# Try to get direction from vertical view
	var vertical_view = _get_vertical_view_node()
	if vertical_view:
		return -vertical_view.global_transform.basis.z

	# Try to get direction from horizontal view
	var horizontal_view = _get_horizontal_view_node()
	if horizontal_view:
		return -horizontal_view.global_transform.basis.z

	return Vector3.FORWARD

# Debug function to check synchronization status
func debug_sync_status():
	print("=== Player Sync Status ===")
	print("Player: ", player_name)
	print("Is Local: ", is_local_player)
	print("Peer ID: ", peer_id)
	print("Authority: ", get_multiplayer_authority())
	print("Body Position: ", body.position if body else "No Body")
	print("Body Velocity: ", body.velocity if body else "No Body")
	print("Synchronizer Authority: ", multiplayer_synchronizer.get_multiplayer_authority() if multiplayer_synchronizer else "No Sync")
	print("==========================")
