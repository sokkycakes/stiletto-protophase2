extends Node3D
class_name NetworkedPlayer

## Networked wrapper around GoldGdt_Pawn that adds multiplayer synchronization
## Preserves all existing GoldGdt functionality while adding network features

# --- Core Components ---
@export var pawn_scene: PackedScene
var pawn: GoldGdt_Pawn
var pawn_body: CharacterBody3D
var pawn_controls: Node
var pawn_camera: Camera3D
var pawn_horizontal_view: Node3D
var pawn_vertical_view: Node3D
var weapon_manager: NetworkedWeaponManager

# --- Network Identity ---
var peer_id: int = -1
var player_name: String = "Player"
var team_id: int = 0

# --- Player State ---
var health: float = 100.0
var max_health: float = 100.0
var is_alive: bool = true
var respawn_time: float = 5.0

# --- Network Sync ---
var last_position: Vector3 = Vector3.ZERO
var last_rotation: Vector3 = Vector3.ZERO
var last_view_yaw: float = 0.0
var last_view_pitch: float = 0.0
var position_threshold: float = 0.1
var rotation_threshold: float = 0.05

# --- Visibility / Layers ---
# Shared world-model layer used by all player bodies/weapons in the scene assets.
const PLAYER_WORLD_MODEL_LAYER: int = 1 << 1
# Local-only layer used to hide THIS client's own world model from their camera
# without affecting visibility of remote players.
const LOCAL_OWN_MODEL_LAYER: int = 1 << 5

# --- Death Visuals ---
# Material used to indicate a dead player on their world model meshes.
const DEAD_DEV_MATERIAL: Material = preload("res://materials/dev/dead_dev.tres")

# --- Timers ---
var respawn_timer: Timer
var sync_timer: Timer

# --- Signals ---
signal health_changed(old_health: float, new_health: float)
signal player_died(killer_peer_id: int)
signal player_respawned()

func _ready() -> void:
	# Set up network authority
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
	
	# Create respawn timer
	respawn_timer = Timer.new()
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_respawn_player)
	add_child(respawn_timer)
	
	# Create sync timer for smooth network updates
	sync_timer = Timer.new()
	sync_timer.wait_time = 1.0 / 20.0  # 20 FPS sync rate
	sync_timer.timeout.connect(_sync_position)
	add_child(sync_timer)
	
	# Spawn the pawn
	_spawn_pawn()
	
	# Start sync timer
	if not is_multiplayer_authority():
		sync_timer.start()

func _physics_process(delta: float) -> void:
	if not pawn or not is_alive:
		return
	
	if pawn_body:
		global_position = pawn_body.global_position
	
	# Authority updates position for networking
	if _has_local_authority():
		_check_position_sync()

# --- Pawn Management ---

func _spawn_pawn() -> void:
	if pawn_scene:
		pawn = pawn_scene.instantiate()
	else:
		# Try to find existing GoldGdt_Pawn in scene
		for child in get_children():
			if child is GoldGdt_Pawn:
				pawn = child
				break
		
		# If no pawn found, create basic one
		if not pawn:
			pawn = preload("res://addons/GoldGdt/Pawn.tscn").instantiate()
	
	if pawn:
		add_child(pawn)
		
		# Cache key pawn components
		pawn_body = pawn.get_node_or_null("Body") as CharacterBody3D
		pawn_controls = pawn.get_node_or_null("User Input")
		pawn_camera = pawn.get_node_or_null("Interpolated Camera/Arm/Arm Anchor/Camera") as Camera3D
		pawn_horizontal_view = pawn.get_node_or_null("Body/Horizontal View") as Node3D
		pawn_vertical_view = pawn.get_node_or_null("Body/Horizontal View/Vertical View") as Node3D
		
		# Align initial network state
		var spawn_pos = pawn_body.global_position if pawn_body else pawn.global_position
		last_position = spawn_pos
		last_rotation = (pawn_body.global_rotation if pawn_body else pawn.global_rotation)
		last_view_yaw = pawn_horizontal_view.rotation.y if pawn_horizontal_view else 0.0
		last_view_pitch = pawn_vertical_view.rotation.x if pawn_vertical_view else 0.0
		
		# Disable input for non-authority players
		if not _has_local_authority():
			_disable_pawn_input()
			_disable_pawn_hud()
		else:
			# Local player: enable input/HUD and move our own world model to a local-only layer.
			_configure_local_player_model_visibility()
			_enable_pawn_input()
			_enable_pawn_hud()
			_configure_local_camera_visibility()
		
		# Set up weapon manager
		_setup_weapon_manager()
		
		# Connect to PlayerState death signal for multiplayer death handling
		var player_state = pawn.get_node_or_null("Body/PlayerState")
		if player_state:
			if player_state.has_signal("player_died"):
				print("[NetworkedPlayer] Connecting to PlayerState.player_died signal for: ", player_name)
				player_state.player_died.connect(_on_playerstate_died)
			
			if player_state.has_signal("respawn_requested"):
				print("[NetworkedPlayer] Connecting to PlayerState.respawn_requested signal for: ", player_name)
				player_state.respawn_requested.connect(_on_playerstate_respawn_requested)
		else:
			print("[NetworkedPlayer] WARNING: Could not find PlayerState node")
		
		print("Pawn spawned for player: ", player_name)
		
		if _has_local_authority():
			force_sync()

func _has_local_authority() -> bool:
	# In single-player or before a multiplayer peer is assigned,
	# treat this instance as locally authoritative to avoid engine warnings.
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()

func _get_player_model_root() -> Node3D:
	if not pawn:
		return null
	# Default path for current player characters
	var model_root := pawn.get_node_or_null("Body/PlayerModel") as Node3D
	if model_root:
		return model_root
	# Fallback: try to find by name anywhere under the pawn
	return pawn.find_child("PlayerModel", true, false) as Node3D

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

func _set_mesh_layer_recursive(node: Node, layer_mask: int) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers = layer_mask
	for c in node.get_children():
		_set_mesh_layer_recursive(c, layer_mask)

func _configure_local_camera_visibility() -> void:
	"""Configure local player's camera to hide their own world model layer."""
	if not pawn_camera:
		return
	
	# Ensure camera has a sane default cull mask (all layers) if unset.
	if pawn_camera.cull_mask == 0:
		pawn_camera.cull_mask = 0xFFFFFFFF
	
	# Hide ONLY the local-only layer for this camera; remote players remain visible
	# on the shared PLAYER_WORLD_MODEL_LAYER.
	pawn_camera.cull_mask &= ~LOCAL_OWN_MODEL_LAYER

func _disable_pawn_input() -> void:
	if not pawn:
		return
	
	# Disable input processing for remote players
	pawn.set_process(false)
	pawn.set_process_input(false)
	pawn.set_process_unhandled_input(false)
	pawn.set_physics_process(false)
	pawn.propagate_call("set_process_input", [false])
	pawn.propagate_call("set_process_unhandled_input", [false])
	
	# Disable control scripts that would react to local input
	if pawn_controls:
		pawn_controls.set_process(false)
		pawn_controls.set_process_input(false)
		pawn_controls.set_physics_process(false)

	if pawn_camera:
		pawn_camera.current = false
	
	# Stop physics simulation on remote bodies; they will be driven by sync updates
	if pawn_body:
		pawn_body.set_physics_process(false)
		pawn_body.set_process(false)
		pawn_body.set_process_input(false)
	
	# Release mouse for remote players
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _enable_pawn_input() -> void:
	if not pawn:
		return
	
	pawn.set_process(true)
	pawn.set_process_input(true)
	pawn.set_process_unhandled_input(true)
	pawn.set_physics_process(true)
	pawn.propagate_call("set_process_input", [true])
	pawn.propagate_call("set_process_unhandled_input", [true])
	
	if pawn_controls:
		pawn_controls.set_process(true)
		pawn_controls.set_process_input(true)
		pawn_controls.set_physics_process(true)
	
	if pawn_body:
		pawn_body.set_physics_process(true)
		pawn_body.set_process(true)

	if pawn_camera:
		pawn_camera.current = true
	
	# Capture mouse for local player only
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _disable_pawn_hud() -> void:
	"""Disable character-specific HUD for remote players"""
	if not pawn:
		return
	
	# Find and hide the HUD CanvasLayer
	var hud_node = pawn.get_node_or_null("HUD")
	if hud_node and hud_node is CanvasLayer:
		hud_node.visible = false
		print("[NetworkedPlayer] Disabled HUD for remote player: ", player_name)

func _enable_pawn_hud() -> void:
	"""Enable character-specific HUD for local player"""
	if not pawn:
		return
	
	# Find and show the HUD CanvasLayer
	var hud_node = pawn.get_node_or_null("HUD")
	if hud_node and hud_node is CanvasLayer:
		hud_node.visible = true
		print("[NetworkedPlayer] Enabled HUD for local player: ", player_name)

func _setup_weapon_manager() -> void:
	# Find existing weapon manager or create one
	var weapon_node: Node = pawn.get_node_or_null("WeaponManager")
	if weapon_node == null:
		weapon_node = pawn.find_child("WeaponManager", true, false)
	weapon_manager = weapon_node as NetworkedWeaponManager
	
	if not weapon_manager:
		# Convert existing WeaponManager to NetworkedWeaponManager
		var existing_wm = weapon_node as WeaponManager
		if existing_wm:
			# Create networked version
			weapon_manager = NetworkedWeaponManager.new()
			weapon_manager.name = "WeaponManager"
			
			# Copy settings from existing manager
			weapon_manager.fire_action = existing_wm.fire_action
			weapon_manager.reload_action = existing_wm.reload_action
			weapon_manager.weapon_switch_actions = existing_wm.weapon_switch_actions
			weapon_manager.camera = existing_wm.camera
			weapon_manager.muzzle_path = existing_wm.muzzle_path
			
			# Replace old manager in-place to keep hierarchy/transform
			var wm_parent = existing_wm.get_parent()
			var wm_index = wm_parent.get_children().find(existing_wm)
			var wm_transform = existing_wm.transform
			existing_wm.queue_free()
			wm_parent.add_child(weapon_manager)
			if wm_index >= 0:
				wm_parent.move_child(weapon_manager, wm_index)
			weapon_manager.transform = wm_transform
	
	if weapon_manager:
		weapon_manager.setup_for_player(peer_id)

# --- Health System ---

func take_damage(amount: float, attacker_peer_id: int = -1) -> void:
	if not is_multiplayer_authority() or not is_alive:
		return
	
	var old_health = health
	health = max(0.0, health - amount)
	
	# Forward to character health component (if present) for audio/FX.
	var health_component := _get_health_component()
	if health_component and health_component.has_method("take_damage"):
		health_component.take_damage(int(amount))
	
	health_changed.emit(old_health, health)
	update_health.rpc(health, peer_id)
	
	if health <= 0.0 and is_alive:
		print("[NetworkedPlayer] DEATH TRIGGERED: health=", health, " is_alive=", is_alive)
		_die(attacker_peer_id)

@rpc("any_peer", "call_remote", "reliable")
func apply_damage(amount: float, attacker_peer_id: int = -1, target_peer_id: int = -1) -> void:
	# Network entry point: routes damage to the authoritative instance.
	# CRITICAL: Verify this RPC is being called on the correct NetworkedPlayer instance
	# When multiple players use the same class, we need to ensure damage goes to the right player
	if target_peer_id >= 0 and peer_id != target_peer_id:
		push_warning("[NetworkedPlayer] apply_damage called on wrong instance! Expected peer_id %d, but this is peer_id %d (player: %s). Damage rejected." % [target_peer_id, peer_id, player_name])
		return
	
	# Additional safety: Only apply damage if we have valid authority
	# This prevents damage application on wrong instances even if target_peer_id wasn't provided
	if not is_multiplayer_authority():
		# Don't warn here - non-authority instances shouldn't process damage anyway
		return
	
	take_damage(amount, attacker_peer_id)

## Helper method to safely apply damage to a NetworkedPlayer with validation
## Use this instead of calling apply_damage.rpc directly to ensure correct routing
static func apply_damage_to_player(receiver: NetworkedPlayer, amount: float, attacker_peer_id: int = -1) -> void:
	if not receiver:
		return
	
	if receiver is NetworkedPlayer:
		var target_peer_id := receiver.peer_id
		receiver.apply_damage.rpc(amount, attacker_peer_id, target_peer_id)

func heal(amount: float) -> void:
	if not is_multiplayer_authority():
		return
	
	var old_health = health
	health = min(max_health, health + amount)
	
	if old_health != health:
		health_changed.emit(old_health, health)
		update_health.rpc(health, peer_id)

func _get_health_component() -> Node:
	# Default path used by player scenes: Body/PlayerState/Health
	if not pawn:
		return null
	var health_node := pawn.get_node_or_null("Body/PlayerState/Health")
	if health_node:
		return health_node
	# Fallback: search by name anywhere under pawn
	return pawn.find_child("Health", true, false)

func _on_playerstate_died() -> void:
	"""Called when PlayerState emits player_died signal"""
	print("[NetworkedPlayer] _on_playerstate_died() - PlayerState died signal received for: ", player_name)
	_die()

func _on_playerstate_respawn_requested() -> void:
	"""Called when PlayerState emits respawn_requested signal (player pressed respawn key)"""
	print("[NetworkedPlayer] _on_playerstate_respawn_requested() - Player requested respawn: ", player_name)
	if is_multiplayer_authority():
		_respawn_player()

func _die(killer_peer_id: int = -1) -> void:
	print("[NetworkedPlayer] _die() called, is_alive before check: ", is_alive)
	if not is_alive:
		print("[NetworkedPlayer] _die() returning early - already dead")
		return
	
	is_alive = false
	print("[NetworkedPlayer] _die() setting is_alive to false")
	
	# Apply death material to model
	_set_dead_visuals()
	
	# Let PlayerState handle all death behavior (camera, movement, etc)
	# It already has all the logic we need - don't interfere with it!
	
	# Notify game rules
	if GameRulesManager:
		GameRulesManager.on_player_killed(killer_peer_id, peer_id)
	
	player_died.emit(killer_peer_id)
	
	# Broadcast death to all clients (including this one via call_local)
	player_died_networked.rpc(killer_peer_id)
	
	# NOTE: Do NOT auto-respawn here; wait for explicit respawn requests
	print("Player ", player_name, " died (waiting for manual respawn)")

func _respawn_player() -> void:
	health = max_health
	is_alive = true
	
	# Clear death material
	_clear_dead_visuals()
	
	# Reset PlayerState to NORMAL - it handles ALL the respawn logic:
	# - Camera rotation reset
	# - Movement re-enable
	# - Viewmodel restore
	# - Everything we need!
	var player_state = pawn.get_node_or_null("Body/PlayerState") if pawn else null
	if player_state and player_state.has_method("set_state"):
		if player_state.get("PlayerState"):
			player_state.set_state(player_state.PlayerState.NORMAL)
			print("[NetworkedPlayer] Reset PlayerState to NORMAL - PlayerState handles the rest!")
	
	# Teleport to spawn point
	var spawn_point = _get_best_spawn_point()
	var spawn_pos = Vector3(0, 1, 0)
	var spawn_yaw = 0.0
	
	if spawn_point:
		spawn_pos = spawn_point.use_spawn_point()
		spawn_yaw = spawn_point.get_spawn_rotation_y()
	
	set_spawn_transform(spawn_pos, spawn_yaw)
	
	player_respawned.emit()
	player_respawned_networked.rpc()
	update_health.rpc(health)
	force_sync()
	
	print("Player ", player_name, " respawned")

func _set_dead_visuals() -> void:
	print("[NetworkedPlayer] _set_dead_visuals() START - pawn exists: ", pawn != null)
	
	if not pawn:
		print("[NetworkedPlayer] ERROR: pawn is null!")
		return
	
	var model_root := _get_player_model_root()
	print("[NetworkedPlayer] _get_player_model_root() returned: ", model_root)
	
	if not model_root:
		print("[NetworkedPlayer] ERROR: Could not find PlayerModel!")
		return
	
	print("[NetworkedPlayer] Found model root: ", model_root.name)
	print("[NetworkedPlayer] Model root type: ", model_root.get_class())
	print("[NetworkedPlayer] Applying DEAD_DEV_MATERIAL to player model meshes")
	
	# Apply dead material to all mesh instances under the player model.
	_set_dead_material_recursive(model_root)
	print("[NetworkedPlayer] Applied DEAD_DEV_MATERIAL for dead player: ", player_name)

func _clear_dead_visuals() -> void:
	var model_root := _get_player_model_root()
	if not model_root:
		print("[NetworkedPlayer] ERROR: Could not find PlayerModel to restore!")
		return
	
	# Restore original materials on all mesh instances.
	_clear_dead_material_recursive(model_root)
	print("[NetworkedPlayer] Restored player model materials for respawned player: ", player_name)

func _set_model_tint_recursive(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		# Store original overlay material so we can restore it on respawn.
		if not mesh.has_meta("original_material_overlay"):
			mesh.set_meta("original_material_overlay", mesh.material_overlay)
		
		# Create a simple transparent red overlay material that works regardless of the base material.
		var overlay := StandardMaterial3D.new()
		overlay.albedo_color = tint
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.flags_transparent = true
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		mesh.material_overlay = overlay
	
	for child in node.get_children():
		_set_model_tint_recursive(child, tint)

func _restore_model_tint_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.has_meta("original_material_overlay"):
			mesh.material_overlay = mesh.get_meta("original_material_overlay")
			mesh.remove_meta("original_material_overlay")
	for child in node.get_children():
		_restore_model_tint_recursive(child)

func _set_dead_material_recursive(node: Node) -> void:
	"""Recursively apply the dead material override to all MeshInstance3D nodes."""
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		
		# Store original material override so we can restore it on respawn.
		if not mesh.has_meta("original_material_override"):
			mesh.set_meta("original_material_override", mesh.material_override)
		
		mesh.material_override = DEAD_DEV_MATERIAL
	
	for child in node.get_children():
		_set_dead_material_recursive(child)

func _clear_dead_material_recursive(node: Node) -> void:
	"""Recursively restore original material override on all MeshInstance3D nodes."""
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		
		if mesh.has_meta("original_material_override"):
			mesh.material_override = mesh.get_meta("original_material_override")
			mesh.remove_meta("original_material_override")
	
	for child in node.get_children():
		_clear_dead_material_recursive(child)

func _debug_count_nodes(node: Node, count: int, mesh_count: int) -> void:
	"""Debug function to count nodes and meshes"""
	count += 1
	if node is MeshInstance3D:
		mesh_count += 1
		print("[DEBUG] Found MeshInstance3D: ", node.name)
	
	for child in node.get_children():
		_debug_count_nodes(child, count, mesh_count)

func _set_model_transparency_recursive(node: Node, alpha_value: float) -> void:
	"""Set transparency on all MeshInstance3D nodes recursively by modifying material alpha"""
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		
		# Get the material - try both main and overlay
		var material = mesh.material
		if not material:
			material = mesh.get_override_material()
		
		# If still no material, create one
		if not material:
			material = StandardMaterial3D.new()
		else:
			# Store original material so we can restore it on respawn
			if not mesh.has_meta("original_material"):
				mesh.set_meta("original_material", material)
		
		# Clone the material to avoid modifying the shared one
		var mat_copy = material.duplicate()
		if mat_copy is StandardMaterial3D or mat_copy is ORMMaterial3D or mat_copy is BaseMaterial3D:
			# Store original alpha value
			if not mesh.has_meta("original_alpha"):
				var current_color = mat_copy.albedo_color
				mesh.set_meta("original_alpha", current_color.a)
			
			# Set transparency mode and modify alpha
			mat_copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var color = mat_copy.albedo_color
			color.a = alpha_value
			mat_copy.albedo_color = color
		
		mesh.material = mat_copy
	
	for child in node.get_children():
		_set_model_transparency_recursive(child, alpha_value)

func _restore_model_transparency_recursive(node: Node) -> void:
	"""Restore original transparency on all MeshInstance3D nodes recursively"""
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		
		# Restore original material
		if mesh.has_meta("original_material"):
			var original_mat = mesh.get_meta("original_material")
			mesh.material = original_mat
			mesh.remove_meta("original_material")
			mesh.remove_meta("original_alpha")
	
	for child in node.get_children():
		_restore_model_transparency_recursive(child)

## Set player position and rotation (teleport)
func set_spawn_transform(pos: Vector3, yaw_degrees: float) -> void:
	var yaw_rad = deg_to_rad(yaw_degrees)
	
	# CRITICAL: GoldGdt input logic relies on the body/root being unrotated (or aligned with input space).
	# If we rotate the root/body, the local view yaw is relative to that rotation, 
	# but the input vector is rotated by local view yaw, leading to mismatched directions.
	# Instead, we must keep root/body aligned (0) and rotate the VIEW to the desired facing.
	
	# 1. Set positions
	global_position = pos
	if pawn:
		pawn.global_position = pos
	if pawn_body:
		pawn_body.global_position = pos
		pawn_body.velocity = Vector3.ZERO
	
	# 2. Reset Node Rotations to Identity (World Aligned)
	rotation = Vector3.ZERO
	if pawn:
		pawn.rotation = Vector3.ZERO
	if pawn_body:
		pawn_body.rotation = Vector3.ZERO
	
	# 3. Apply rotation to the VIEW (Horizontal View / Camera Gimbal)
	if pawn_horizontal_view:
		pawn_horizontal_view.rotation.y = yaw_rad
		pawn_horizontal_view.orthonormalize()
	
	# 4. Optionally rotate the player model if it exists (to match view initially)
	var model = _get_player_model_root()
	if model:
		model.rotation.y = yaw_rad
	
	# 5. Update sync state
	last_position = pos
	last_rotation = Vector3.ZERO
	last_view_yaw = yaw_rad
	
	force_sync()

func _get_best_spawn_point() -> SpawnPoint:
	# Try to find team spawn points
	var spawn_points = get_tree().get_nodes_in_group("spawn_points")
	var team_spawns = []
	
	for spawn in spawn_points:
		if spawn.has_method("get_team_id") and spawn.get_team_id() == team_id:
			team_spawns.append(spawn)
	
	# Use team spawns if available, otherwise use any spawn
	var available_spawns = team_spawns if team_spawns.size() > 0 else spawn_points
	
	if available_spawns.size() > 0:
		return available_spawns[randi() % available_spawns.size()]
	
	return null

func _get_spawn_position() -> Vector3:
	var spawn = _get_best_spawn_point()
	if spawn:
		return spawn.global_position
	return Vector3(0, 1, 0)

# --- Network Synchronization ---

func _check_position_sync() -> void:
	if not pawn:
		return
	
	var current_pos = pawn_body.global_position if pawn_body else pawn.global_position
	var current_rot = pawn_body.global_rotation if pawn_body else pawn.global_rotation
	var current_view_yaw = pawn_horizontal_view.rotation.y if pawn_horizontal_view else 0.0
	var current_view_pitch = pawn_vertical_view.rotation.x if pawn_vertical_view else 0.0
	
	# Check if position/rotation changed significantly
	if current_pos.distance_to(last_position) > position_threshold or \
	   current_rot.distance_to(last_rotation) > rotation_threshold or \
	   absf(current_view_yaw - last_view_yaw) > rotation_threshold or \
	   absf(current_view_pitch - last_view_pitch) > rotation_threshold:
		
		last_position = current_pos
		last_rotation = current_rot
		last_view_yaw = current_view_yaw
		last_view_pitch = current_view_pitch
		sync_transform.rpc(current_pos, current_rot, current_view_yaw, current_view_pitch)

func _sync_position() -> void:
	if is_multiplayer_authority() or not pawn:
		return
	
	# Smooth interpolation for remote players
	var target_pos = last_position
	var target_rot = last_rotation
	
	if pawn_body:
		pawn_body.global_position = pawn_body.global_position.lerp(target_pos, 0.15)
		pawn_body.global_rotation = pawn_body.global_rotation.lerp(target_rot, 0.15)
		# Keep wrapper aligned with body for any dependent logic
		global_position = pawn_body.global_position
	else:
		pawn.global_position = pawn.global_position.lerp(target_pos, 0.15)
		pawn.global_rotation = pawn.global_rotation.lerp(target_rot, 0.15)
	
	if pawn_horizontal_view:
		var current_yaw = pawn_horizontal_view.rotation.y
		var new_yaw = lerp_angle(current_yaw, last_view_yaw, 0.2)
		pawn_horizontal_view.rotation.y = new_yaw
		pawn_horizontal_view.orthonormalize()
	
	if pawn_vertical_view:
		var current_pitch = pawn_vertical_view.rotation.x
		var new_pitch = lerp_angle(current_pitch, last_view_pitch, 0.2)
		pawn_vertical_view.rotation.x = new_pitch
		pawn_vertical_view.orthonormalize()

func force_sync(target_peer_id: int = 0) -> void:
	if not is_multiplayer_authority() or not pawn:
		return
	
	var pos = pawn_body.global_position if pawn_body else pawn.global_position
	var rot = pawn_body.global_rotation if pawn_body else pawn.global_rotation
	var view_yaw = pawn_horizontal_view.rotation.y if pawn_horizontal_view else 0.0
	var view_pitch = pawn_vertical_view.rotation.x if pawn_vertical_view else 0.0
	
	last_position = pos
	last_rotation = rot
	last_view_yaw = view_yaw
	last_view_pitch = view_pitch
	
	if target_peer_id > 0:
		sync_transform.rpc_id(target_peer_id, pos, rot, view_yaw, view_pitch)
	else:
		sync_transform.rpc(pos, rot, view_yaw, view_pitch)

# --- RPC Methods ---

@rpc("authority", "call_remote", "unreliable")
func sync_transform(pos: Vector3, rot: Vector3, view_yaw: float, view_pitch: float) -> void:
	last_position = pos
	last_rotation = rot
	last_view_yaw = view_yaw
	last_view_pitch = view_pitch
	
	# Snap wrapper immediately for consistency when interpolation disabled
	if pawn_body:
		pawn_body.global_position = pos
		pawn_body.global_rotation = rot
		global_position = pos
	else:
		global_position = pos
	
	if pawn_horizontal_view:
		pawn_horizontal_view.rotation.y = view_yaw
		pawn_horizontal_view.orthonormalize()
	
	if pawn_vertical_view:
		pawn_vertical_view.rotation.x = view_pitch
		pawn_vertical_view.orthonormalize()

@rpc("authority", "call_remote", "reliable")
func update_health(new_health: float, target_peer_id: int = -1) -> void:
	# CRITICAL: Verify this health update is for the correct NetworkedPlayer instance
	# Prevents health confusion when multiple players use the same class
	if target_peer_id >= 0 and peer_id != target_peer_id:
		push_warning("[NetworkedPlayer] update_health called on wrong instance! Expected peer_id %d, but this is peer_id %d (player: %s). Update rejected." % [target_peer_id, peer_id, player_name])
		return
	
	# Only update health if we're not the authority (authority already has correct health)
	# This prevents overwriting authority's health with stale data
	if not is_multiplayer_authority():
		health = new_health

@rpc("authority", "call_local", "reliable")
func player_died_networked(killer_peer_id: int) -> void:
	# Apply death visuals on all clients (including the authority via call_local)
	print("[NetworkedPlayer] player_died_networked() RPC called for: ", player_name)
	_set_dead_visuals()
	print("[NetworkedPlayer] Applied death visuals for player: ", player_name)

@rpc("authority", "call_local", "reliable")
func player_respawned_networked() -> void:
	# Clear death material
	_clear_dead_visuals()
	
	# Reset PlayerState to NORMAL - it handles everything else
	var player_state = pawn.get_node_or_null("Body/PlayerState") if pawn else null
	if player_state and player_state.has_method("set_state"):
		if player_state.get("PlayerState"):
			player_state.set_state(player_state.PlayerState.NORMAL)
			print("[NetworkedPlayer] Reset PlayerState to NORMAL via RPC - PlayerState handles the rest!")
	
	print("[NetworkedPlayer] Cleared death visuals for player: ", player_name)

# --- Public API ---

## Initialize player with network info
func initialize_player(id: int, name: String, team: int = 0) -> void:
	peer_id = id
	player_name = name
	team_id = team
	
	set_multiplayer_authority(peer_id)
	
	print("Initialized networked player: ", name, " (ID: ", id, ", Team: ", team, ")")

## Get the underlying GoldGdt_Pawn
func get_pawn() -> GoldGdt_Pawn:
	return pawn

## Get current health percentage
func get_health_percentage() -> float:
	return health / max_health

## Check if this is the local player
func is_local_player() -> bool:
	return peer_id == MultiplayerManager.get_local_peer_id()

## Get player info dictionary
func get_player_info() -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": player_name,
		"team": team_id,
		"health": health,
		"max_health": max_health,
		"is_alive": is_alive,
		"position": global_position if pawn else Vector3.ZERO
	}

## Set team (updates visual indicators, spawning, etc.)
func set_team(new_team_id: int) -> void:
	team_id = new_team_id
	# Could add team-based visual changes here (colors, etc.)

## Force respawn (admin/debug function)
func force_respawn() -> void:
	if is_multiplayer_authority():
		_respawn_player()

## Check if player has valid pawn
func has_valid_pawn() -> bool:
	return pawn != null and is_alive

## Get owner information for projectile spawning
## Returns dictionary with owner_ref and owner_peer_id
## Use this when spawning projectiles to enable universal ownership tracking
func get_projectile_owner_info() -> Dictionary:
	var owner_ref: Node3D = null
	if pawn_body:
		owner_ref = pawn_body
	elif pawn:
		owner_ref = pawn as Node3D
	
	return {
		"owner_ref": owner_ref,
		"owner_peer_id": peer_id
	}
