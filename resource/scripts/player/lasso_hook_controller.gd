extends "res://addons/grappling_hook_3d/src/hook_controller_v2.gd"
class_name LassoHookController

## Lasso Hook Controller for Beaumont Character
## Extends the V2 hook controller but only targets players (not surfaces or enemies)
## Has shorter range than the normal hook

@export_group("Lasso Settings")
@export var lasso_max_distance: float = 10.0  # Shorter range than normal hook (default is 20.0)

# Override max_distance to use lasso range
func _ready() -> void:
	super._ready()
	# Set shorter range for lasso
	max_distance = lasso_max_distance
	print("LassoHookController: Initialized with max_distance: ", max_distance)

# Override _physics_process to handle GRAPPLE_PULLING_ENEMY state
# The base class doesn't process this state in _physics_process, so we add it here
func _physics_process(delta: float) -> void:
	# Call base class physics process
	super._physics_process(delta)
	
	# Handle the GRAPPLE_PULLING_ENEMY state (which base class doesn't handle)
	if current_state == GrappleState.GRAPPLE_PULLING_ENEMY:
		process_enemy_pull(delta)
	# Keep the hook visually attached to the hooked target as they move
	if is_instance_valid(locked_enemy):
		if current_hook_instance:
			current_hook_instance.global_position = locked_enemy.global_position + hook_attach_offset

# Track the hooked player's controls for re-enabling later
var _hooked_player_controls: Node = null
var _hooked_player_body: CharacterBody3D = null
var _pull_timer: float = 0.0
const MAX_PULL_DURATION: float = 3.0  # Maximum pull time before auto-release

# Override set_state to prevent immediate retraction for GRAPPLE_PULLING_ENEMY
# The base class immediately retracts after this state, but we want continuous pulling
func set_state(new_state: GrappleState) -> void:
	if current_state == new_state:
		return
	
	# For GRAPPLE_PULLING_ENEMY, don't call base class (which would retract immediately)
	# Instead, just set the state and let _physics_process handle continuous pulling
	if new_state == GrappleState.GRAPPLE_PULLING_ENEMY:
		current_state = new_state
		_pull_timer = 0.0  # Reset pull timer
		print("Lasso: Entered GRAPPLE_PULLING_ENEMY state (continuous pull mode)")
		
		# Find and disable hooked player's movement controls
		if hit_collider:
			_hooked_player_body = hit_collider as CharacterBody3D if hit_collider is CharacterBody3D else null
			if not _hooked_player_body:
				var node = hit_collider
				while node:
					if node is GoldGdt_Body:
						_hooked_player_body = node as CharacterBody3D
						break
					node = node.get_parent()
			
			if _hooked_player_body:
				_hooked_player_controls = _find_goldgdt_controls_on_player(_hooked_player_body)
				if _hooked_player_controls and _hooked_player_controls.has_method("disable_movement"):
					_hooked_player_controls.disable_movement()
					print("Lasso: Disabled hooked player's movement controls")
		return
	
	# When leaving GRAPPLE_PULLING_ENEMY (e.g., retracting), re-enable movement
	if current_state == GrappleState.GRAPPLE_PULLING_ENEMY and new_state != GrappleState.GRAPPLE_PULLING_ENEMY:
		_reenable_hooked_player_movement()
	
	# For all other states, use base class behavior
	super.set_state(new_state)

# Ensure we reset one-shot attachment state when retracting
func initiate_retraction() -> void:
	locked_enemy = null
	hook_attach_offset = Vector3.ZERO
	# Also clear instant launch state to allow future pulls
	_instant_launched = false
	super.initiate_retraction()

# Re-enable the hooked player's movement (called when pull ends)
func _reenable_hooked_player_movement() -> void:
	if _hooked_player_controls and is_instance_valid(_hooked_player_controls):
		if _hooked_player_controls.has_method("enable_movement"):
			_hooked_player_controls.enable_movement()
			print("Lasso: Re-enabled hooked player's movement controls")
	
	# Also send RPC to re-enable on the owning client
	if _hooked_player_body and multiplayer.has_multiplayer_peer():
		var networked_player = _find_networked_player(_hooked_player_body)
		if networked_player and "peer_id" in networked_player:
			var target_peer_id = networked_player.peer_id
			if target_peer_id > 0 and target_peer_id != multiplayer.get_unique_id():
				_rpc_end_lasso_pull.rpc_id(target_peer_id)
	
	_hooked_player_controls = null
	_hooked_player_body = null

# RPC to end lasso pull on the receiving player
@rpc("any_peer", "call_local", "reliable")
func _rpc_end_lasso_pull() -> void:
	# Re-enable our own movement controls
	var our_controls = _find_goldgdt_controls_on_player(player_body)
	if our_controls and our_controls.has_method("enable_movement"):
		our_controls.enable_movement()
		print("Lasso: Re-enabled own movement controls via RPC")

# Override fire_hook to only target players
func fire_hook():
	if current_charges <= 0:
		return
	var _world := get_world_3d()
	if _world == null:
		printerr("LassoHookController: World3D is null. Aborting raycast.")
		return
	var space_state = _world.direct_space_state
	var camera = get_viewport().get_camera_3d()
	if not camera:
		printerr("LassoHookController: No Camera3D found in viewport for screen center raycast.")
		return
	
	# Use lasso max distance (shorter than normal hook)
	var current_max_distance = lasso_max_distance
	
	# Use camera's forward direction
	var ray_origin = camera.global_position
	var ray_dir = -camera.global_transform.basis.z
	var ray_end = ray_origin + ray_dir * current_max_distance
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# LASSO: Only target players - use collision mask that includes player layer
	# Player layer is typically layer 1 (0x2), so we only check that layer
	# Exclude everything else (surfaces, enemies, etc.)
	query.collision_mask = 0x2  # Only layer 1 (players)
	
	# Debug: Print the collision mask
	print("Lasso raycast collision mask: ", query.collision_mask, " (only players)")
	
	# Exclude self and current hook instance
	if current_hook_instance:
		query.exclude.append(current_hook_instance.get_rid())
	if player_body:
		query.exclude.append(player_body.get_rid())
	
	# Also exclude all children of player_body to avoid self-collision
	if player_body:
		var nodes_to_exclude = _get_all_collision_bodies(player_body)
		for node in nodes_to_exclude:
			if node is CollisionObject3D:
				query.exclude.append(node.get_rid())
	
	var result = space_state.intersect_ray(query)
	if result:
		var hit_node = result.collider
		
		# LASSO: Only allow players, reject everything else
		if not _is_part_of_player(hit_node):
			print("Lasso: Hit non-player object (", hit_node.name, "). Cannot lasso.")
			return
		
		print("Lasso: Hit player (", hit_node.name, ")")
		
		# Store the surface normal (will be used for positioning)
		grapple_target_normal = result.normal
		
		# Use a charge: find the first available timer slot
		for i in range(MAX_CHARGES):
			if charge_timers[i] == 0:
				charge_timers[i] = 0.6 if is_grounded else 1.3
				break
		current_charges -= 1
		charges_changed.emit(current_charges)
		
		grapple_target_point = result.position
		hit_collider = result.collider # Using member variable if needed, or just unused local update? 
		# Actually hit_collider member is usually set on contact. 
		# But here we just want to ensure we don't shadow. 
		# If we don't set self.hit_collider here, it's fine because we haven't hit yet.
		
		current_hook_instance = grappling_hook_scene.instantiate()
		get_parent().add_child(current_hook_instance)
		current_hook_instance.global_position = get_spawn_position()
		hook_tip_position = get_spawn_position()
		current_hook_instance.look_at(grapple_target_point)
		set_state(GrappleState.HOOK_FLYING)
		
		# Play hook fire sound
		play_sound(hook_fire_sound)
		
		# Broadcast hook fire to other clients for visual sync
		sync_hook_fire.rpc(get_spawn_position(), grapple_target_point, grapple_target_normal)
	else:
		print("Lasso: No player target found. Ray from ", ray_origin, " to ", ray_end)

# Override evaluate_hook_contact to only allow players
func evaluate_hook_contact():
	# Reset any existing camera lock target
	locked_enemy = null
	hook_attach_offset = Vector3.ZERO
	
	if not hit_collider:
		print("Lasso: Error - Hook in contact eval, but no hit_collider.")
		initiate_retraction()
		return
	
	# LASSO: Only allow players, reject everything else
	if not _is_part_of_player(hit_collider):
		print("Lasso: Hit non-player object (", hit_collider.name, "). Retracting.")
		play_sound(hook_bounce_sound)
		spawn_spark_effect(grapple_target_point, -current_hook_instance.global_transform.basis.z)
		initiate_retraction()
		return
	
	# Check if we hit ourselves!
	if hit_collider == player_body:
		print("Lasso: ERROR - Hit our own body! This shouldn't happen.")
		initiate_retraction()
		return
	
	# If we hit a player, launch them towards us in an upward arc
	print("Lasso: Hooked player (", hit_collider.name, ") at position: ", hit_collider.global_position)
	print("Lasso: Our player_body is: ", player_body.name if player_body else "null", " at: ", player_body.global_position if player_body else "N/A")
	
	# Find the player node (walk up hierarchy to find the player root)
	var player_node = hit_collider
	while player_node and not (player_node.is_in_group("player") or player_node.is_in_group("players")):
		player_node = player_node.get_parent()
	
	if not player_node:
		print("Lasso: Could not find player root node. Retracting.")
		initiate_retraction()
		return
	
	# Launch the player towards us with an upward arc
	_launch_player_towards_us(player_node)
	
	# Calculate target point on the player (center of player body)
	var target_player_body = player_node
	if target_player_body is CharacterBody3D:
		# Use player's center position
		grapple_target_point = target_player_body.global_position + Vector3(0, 1.0, 0)  # 1m up from feet
		grapple_target_normal = Vector3.UP  # Default normal for player grab
	
	# Play hook hit sound
	play_sound(hook_hit_sound, get_speed_pitch_multiplier())
	
	# Store reference to the hooked player
	locked_enemy = player_node  # Reuse locked_enemy variable to store player reference
	
	# Set state to pull player (we'll pull the target player to us, not ourselves to them)
	# For lasso, we want to pull the other player to us
	set_state(GrappleState.GRAPPLE_PULLING_ENEMY)  # Reuse enemy pull state for player pull

# Helper function to check if a node is part of a player
func _is_part_of_player(node: Node) -> bool:
	var n := node
	while n:
		if n.is_in_group("player") or n.is_in_group("players"):
			return true
		n = n.get_parent()
	return false

# Helper function to get all collision bodies from a node (for exclusion)
func _get_all_collision_bodies(node: Node) -> Array:
	var collision_bodies: Array = []
	var nodes_to_check: Array = [node]
	
	while nodes_to_check.size() > 0:
		var current_node = nodes_to_check.pop_back()
		
		if current_node is CollisionObject3D:
			collision_bodies.append(current_node)
		
		for child in current_node.get_children():
			nodes_to_check.append(child)
	
	return collision_bodies

# Override get_dynamic_distance to use lasso range
func get_dynamic_distance() -> float:
	# Always use lasso max distance (shorter than normal hook)
	return lasso_max_distance

# Override process_hook_flying to only hit players during flight
func process_hook_flying(delta: float):
	if not current_hook_instance:
		return
	var distance_to_target = hook_tip_position.distance_to(grapple_target_point)
	var distance_from_player = hook_tip_position.distance_to(get_spawn_position())
	var current_max_distance = lasso_max_distance
	if distance_from_player > current_max_distance:
		print("Lasso: Hook flew too far.")
		initiate_retraction()
		return
	var direction = (grapple_target_point - hook_tip_position).normalized()
	var current_hook_speed = get_dynamic_hook_speed()
	var travel = current_hook_speed * delta
	hook_tip_position = hook_tip_position.move_toward(grapple_target_point, travel)
	
	# Update rope visual to stretch from player to hook tip
	if current_hook_instance.has_method("extend_from_to"):
		var source_pos = get_spawn_position()
		var normal = grapple_target_normal if grapple_target_normal != Vector3.ZERO else Vector3.UP
		current_hook_instance.extend_from_to(source_pos, hook_tip_position, normal)
		
		# Broadcast position update to other clients
		sync_hook_position.rpc(source_pos, hook_tip_position, normal)
	
	# Short raycast from hook tip - LASSO: Only check for players
	var _world := get_world_3d()
	if _world == null:
		printerr("LassoHookController: World3D is null. Aborting raycast.")
		return
	var space_state = _world.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		hook_tip_position,
		hook_tip_position + direction * 0.5 # 0.5 units in 3D
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.collision_mask = 0x2  # Only layer 1 (players) for lasso
	query.exclude = [self, current_hook_instance]
	if player_body:
		query.exclude.append(player_body.get_rid())
		# Exclude all collision bodies from player
		var nodes_to_exclude = _get_all_collision_bodies(player_body)
		for node in nodes_to_exclude:
			if node is CollisionObject3D:
				query.exclude.append(node.get_rid())
	
	var collision_result = space_state.intersect_ray(query)
	if hook_tip_position.is_equal_approx(grapple_target_point) or collision_result:
		if collision_result:
			# LASSO: Only allow player hits
			if not _is_part_of_player(collision_result.collider):
				print("Lasso: Hit non-player during flight. Retracting.")
				initiate_retraction()
				return
			
			print("Lasso: Hook hit player during flight.")
			grapple_target_point = collision_result.position
			hook_tip_position = collision_result.position
			# Update the stored surface normal from the collision
			grapple_target_normal = collision_result.normal
			hit_collider = collision_result.collider
		else:
			hook_tip_position = grapple_target_point
		print("Lasso: Hook reached target or hit player.")
		set_state(GrappleState.HOOK_CONTACT_EVAL)

# Launch the hooked player towards Beaumont with a perfect arc trajectory
# Uses GoldGdt's movement system and calculates exact velocity to land at Beaumont's feet
# This works like a jump pad: sets velocity directly, and stun prevents input interference
func _launch_player_towards_us(player_node: Node):
	if not player_node:
		return
	
	# Find the actual GoldGdt_Body (CharacterBody3D) - it might be the node itself or in hierarchy
	var goldgdt_body: GoldGdt_Body = null
	if player_node is GoldGdt_Body:
		goldgdt_body = player_node as GoldGdt_Body
	elif player_node is CharacterBody3D:
		# Try to find GoldGdt_Body in the hierarchy
		goldgdt_body = _find_goldgdt_body(player_node)
	
	if not goldgdt_body:
		push_error("LassoHookController: Could not find GoldGdt_Body for player launch!")
		return
	
	var player_cb = goldgdt_body as CharacterBody3D
	
	# Get GoldGdt gravity from Parameters (or use default)
	var gravity: float
	if goldgdt_body.Parameters:
		gravity = goldgdt_body.Parameters.GRAVITY
	else:
		# Fallback to project settings
		gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	
	# Target is Beaumont's feet (spawn position)
	var target_pos = get_spawn_position()
	var start_pos = player_cb.global_position
	
	# Calculate horizontal distance and direction
	var to_target = target_pos - start_pos
	var horizontal_vec = Vector2(to_target.x, to_target.z)
	var horizontal_distance = horizontal_vec.length()
	var horizontal_dir = horizontal_vec.normalized() if horizontal_distance > 0.01 else Vector2(1, 0)
	
	# Vertical difference (positive means target is higher)
	var vertical_diff = to_target.y
	
	# Calculate perfect arc trajectory using physics
	# We want to solve: Δy = v₀y * t - 0.5 * g * t²
	# Where t = R / v₀x, and v₀x = v₀ * cos(θ), v₀y = v₀ * sin(θ)
	
	# Use a launch angle that ensures an upward arc
	# For optimal range with height difference, we'll use a slightly steeper angle (50-60 degrees)
	# This ensures a nice visible arc even for short distances
	var launch_angle_deg: float = 55.0  # Launch angle in degrees (slightly steeper than 45°)
	var launch_angle = deg_to_rad(launch_angle_deg)
	var cos_angle = cos(launch_angle)
	var sin_angle = sin(launch_angle)
	
	# Calculate required launch speed to reach the target
	# From projectile motion: R = (v₀² * sin(2θ)) / g for same height
	# But we have height difference, so we need to solve the full equation
	# Rearranging: v₀² = (g * R²) / (2 * cos²(θ) * (R * tan(θ) - Δy))
	
	if horizontal_distance < 0.1:
		# Very close - just launch straight up
		var launch_velocity = Vector3(0, 15.0, 0)
		player_cb.velocity = launch_velocity
		print("Lasso: Launched player straight up (very close target)")
		return
	
	# Calculate launch speed using physics equation
	# For projectile with height difference:
	# v₀ = sqrt((g * R²) / (2 * cos²(θ) * (R * tan(θ) - Δy)))
	var tan_angle = tan(launch_angle)
	var trajectory_term = horizontal_distance * tan_angle - vertical_diff
	
	# If target is too high relative to distance, adjust angle or use higher speed
	if trajectory_term <= 0:
		# Target is too high - use a steeper angle (70 degrees) or higher fixed speed
		var steep_angle = deg_to_rad(70.0)
		var steep_cos = cos(steep_angle)
		var steep_sin = sin(steep_angle)
		var steep_tan = tan(steep_angle)
		var steep_trajectory_term = horizontal_distance * steep_tan - vertical_diff
		
		if steep_trajectory_term > 0:
			# Steeper angle works
			launch_angle = steep_angle
			cos_angle = steep_cos
			sin_angle = steep_sin
			trajectory_term = steep_trajectory_term
		else:
			# Even steeper angle needed - use very high fixed speed
			var fixed_speed = 35.0
			var launch_velocity = Vector3(
				horizontal_dir.x * fixed_speed * steep_cos,
				fixed_speed * steep_sin,
				horizontal_dir.y * fixed_speed * steep_cos
			)
			player_cb.velocity = launch_velocity
			print("Lasso: Launched player with high fixed velocity (very high target): ", launch_velocity)
			return
	
	var denominator = 2.0 * cos_angle * cos_angle * trajectory_term
	var launch_speed_squared = (gravity * horizontal_distance * horizontal_distance) / denominator
	var launch_speed = sqrt(max(launch_speed_squared, 0.0))
	
	# Clamp launch speed to reasonable values (ensure minimum for visible arc)
	launch_speed = clamp(launch_speed, 18.0, 50.0)
	
	# Calculate launch velocity components
	var launch_velocity = Vector3(
		horizontal_dir.x * launch_speed * cos_angle,
		launch_speed * sin_angle,
		horizontal_dir.y * launch_speed * cos_angle
	)
	
	# JUMP PAD APPROACH: Set velocity directly (like the jump function does)
	# GoldGdt's jump function sets velocity.y directly and it works because:
	# 1. It sets it in _physics_process before move_and_slide
	# 2. GoldGdt's air acceleration only affects horizontal movement based on input
	# 3. If player is stunned, there's no input, so air acceleration does nothing
	# 
	# We'll do the same - set the full velocity vector directly.
	# The key is ensuring the player is stunned so input doesn't interfere.
	
	# Log the setup (continuous pull will handle actual movement in process_enemy_pull)
	print("Lasso: Setup complete - continuous pull will begin")
	print("  - Target player: ", player_cb.name, " at ", player_cb.global_position)
	print("  - Distance: ", horizontal_distance, "m | Height diff: ", vertical_diff, "m")

# Helper to find GoldGdt_Controls on the hooked player
func _find_goldgdt_controls_on_player(body_node: Node) -> Node:
	if not body_node:
		return null
	
	# GoldGdt_Controls is typically a sibling of Body, under the player root
	var player_root = body_node.get_parent()
	if not player_root:
		return null
	
	# Check direct children of player root
	for child in player_root.get_children():
		if child is GoldGdt_Controls:
			return child
		# Also check by name
		if child.name == "User Input" or child.name == "GoldGdt_Controls":
			if child.has_method("disable_movement"):
				return child
	
	return null

# Helper to find PlayerState directly (no recursion)
func _find_player_state_direct(body_node: Node) -> Node:
	if not body_node:
		return null
	
	# PlayerState might be a child of Body
	var ps = body_node.get_node_or_null("PlayerState")
	if ps:
		return ps
	
	# Or a sibling under the player root
	var player_root = body_node.get_parent()
	if player_root:
		ps = player_root.get_node_or_null("PlayerState")
		if ps:
			return ps
		
		# Check all children
		for child in player_root.get_children():
			if child.name == "PlayerState":
				return child
	
	return null

# Schedule re-enabling movement after delay
func _schedule_reenable_movement(controls: Node, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(controls) and controls.has_method("enable_movement"):
		controls.enable_movement()
		print("Lasso: Re-enabled movement controls")

# Helper to find PlayerState in player hierarchy
# Searches upward from the Body node to find PlayerState (typically a sibling)
func _find_player_state(node: Node) -> Node:
	if not node:
		return null
	
	# Check if this node is PlayerState
	if node.name == "PlayerState" or (node.has_method("apply_stun") and node.has_method("enter_stun_state")):
		return node
	
	# Search upward only (no recursion to avoid infinite loops)
	# PlayerState is typically a sibling of Body or a child of the player root
	var current = node
	var visited = {}  # Track visited nodes to prevent cycles
	
	while current:
		if current in visited:
			break  # Prevent infinite loop
		visited[current] = true
		
		# Check siblings
		var parent = current.get_parent()
		if parent:
			for sibling in parent.get_children():
				if sibling != current:  # Don't check ourselves
					if sibling.name == "PlayerState" or (sibling.has_method("apply_stun") and sibling.has_method("enter_stun_state")):
						return sibling
		
		# Move up one level
		current = parent
	
	return null

# Helper to find GoldGdt_Body in player hierarchy
func _find_goldgdt_body(node: Node) -> GoldGdt_Body:
	if node is GoldGdt_Body:
		return node as GoldGdt_Body
	
	for child in node.get_children():
		var result = _find_goldgdt_body(child)
		if result:
			return result
	
	return null

# Override process_enemy_pull to handle player pulling with CONTINUOUS PULL
# This actively pulls the player towards Beaumont each frame with an upward arc
func process_enemy_pull(delta: float):
	# Safety timeout to prevent softlocks
	_pull_timer += delta
	if _pull_timer > MAX_PULL_DURATION:
		print("Lasso: Pull timeout reached, auto-retracting")
		initiate_retraction()
		return
	
	# Validate hit_collider
	if not is_instance_valid(hit_collider):
		print("Lasso: hit_collider invalid, retracting")
		initiate_retraction()
		return
	
	if not _is_part_of_player(hit_collider):
		print("Lasso: hit_collider not part of player, retracting")
		initiate_retraction()
		return
		
	if not current_hook_instance:
		print("Lasso: no hook instance")
		return
	
	# Find the player's GoldGdt_Body
	var player_body_node: CharacterBody3D = null
	if hit_collider is GoldGdt_Body:
		player_body_node = hit_collider as CharacterBody3D
	elif hit_collider is CharacterBody3D:
		player_body_node = hit_collider as CharacterBody3D
	else:
		# Walk up hierarchy
		var node = hit_collider
		while node:
			if node is GoldGdt_Body:
				player_body_node = node as CharacterBody3D
				break
			node = node.get_parent()
	
	if not player_body_node:
		print("Lasso: could not find player CharacterBody3D")
		initiate_retraction()
		return
	
	var target_pos = get_spawn_position()
	var player_pos = player_body_node.global_position
	var to_target = target_pos - player_pos
	var horizontal_dist = Vector2(to_target.x, to_target.z).length()
	
	# Instant launch path (one-shot) before normal retract checks
	if not _instant_launched and is_instance_valid(player_body_node):
		_launch_instant_blast_to_target(player_body_node)
		_instant_launched = true
		return

	# Retract if player is close enough
	if horizontal_dist < 1.5:
		print("Lasso: Player reached Beaumont, retracting")
		initiate_retraction()
		return
	
	# Per-frame continuous pull removed for simplification.
	# We rely on a single instant launch impulse (rocket-jump style) instead.

# Apply lasso impulse using the NetworkedPlayer knockback system

# Find NetworkedPlayer from a GoldGdt_Body
func _find_networked_player(body: Node) -> NetworkedPlayer:
	if not body:
		return null
	
	# Search up the hierarchy for NetworkedPlayer
	var current = body
	while current:
		if current is NetworkedPlayer:
			return current as NetworkedPlayer
		# Also check if parent has a reference
		var parent = current.get_parent()
		if parent:
			# Check siblings for NetworkedPlayer wrapper
			for sibling in parent.get_children():
				if sibling is NetworkedPlayer:
					return sibling as NetworkedPlayer
		current = parent
	
	return null

var _instant_launched: bool = false
var hook_attach_offset: Vector3 = Vector3.ZERO

func _calculate_instant_launch_velocity(start_pos: Vector3, target_pos: Vector3, flight_time: float) -> Vector3:
	# Gravity value (magnitude)
	var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	var delta = target_pos - start_pos
	var vx = delta.x / flight_time
	var vz = delta.z / flight_time
	var vy = (delta.y + 0.5 * gravity * flight_time * flight_time) / flight_time
	return Vector3(vx, vy, vz)

func _launch_instant_blast_to_target(target_body: CharacterBody3D) -> void:
	# Compute end at Beaumont's feet
	var start_pos = target_body.global_position
	var target_pos = get_spawn_position()
	var flight_time = 0.55
	var instant_velocity = _calculate_instant_launch_velocity(start_pos, target_pos, flight_time)
	var current_vel = target_body.velocity
	var impulse = instant_velocity - current_vel

	var attacker_peer_id = -1
	if multiplayer.has_multiplayer_peer():
		attacker_peer_id = multiplayer.get_unique_id()
		
	var net_player = _find_networked_player(target_body)
	if net_player:
		NetworkedPlayer.apply_knockback_to_player(net_player, impulse, attacker_peer_id)
	else:
		target_body.velocity = instant_velocity
	# Remember who we hooked and where the hook should stay relative to them
	locked_enemy = target_body
	hook_attach_offset = get_spawn_position() - target_body.global_position
