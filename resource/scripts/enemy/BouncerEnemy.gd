extends CharacterBody3D
class_name BouncerEnemy

# -----------------------------------------------------------------------------
# Bouncer Enemy - Intelligent Prowler Type Enemy
# Features:
# - Intelligent pursuit based on line of sight and last known location
# - Jumping and gravity mechanics
# - Animation state integration
# - Prowler-style behavior with loose targeting
# -----------------------------------------------------------------------------

enum State { 
	IDLE, 
	AWARE, 
	CHASE, 
	SEARCH,  # Search for player when line of sight is lost
	JUMP,    # Jumping state
	CLIMB,   # Climbing terrain state
	SKID,    # Skidding when changing direction
	ATTACK, 
	PAIN, 
	STUNNED, 
	DEAD 
}

# Core Properties
@export_group("Movement")
@export var health: int = 75
@export var run_speed: float = 6.0
@export var jump_speed: float = 8.0
@export var turn_speed: float = 5.0
@export var turn_threshold: float = 0.1

@export_group("Combat")
@export var attack_range: float = 2.0
@export var damage: int = 30
@export var attack_cooldown: float = 1.2
@export var launch_force: float = 12.0
@export var launch_angle: float = 45.0

@export_group("Detection")
@export var sight_range: float = 15.0
@export var hearing_range: float = 8.0
@export var lose_target_time: float = 5.0
@export var search_duration: float = 8.0
@export var aware_duration: float = 0.8

@export_group("Jumping")
@export var jump_cooldown: float = 2.0
@export var elevation_jump_threshold: float = 2.0  # How much higher player needs to be to trigger jump
@export var elevation_time_threshold: float = 2.0  # How long player needs to be higher before jumping
@export var max_jump_height: float = 4.0
@export var jump_forward_distance: float = 3.0  # How far forward to jump

@export_group("Terrain Detection")
@export var obstacle_check_distance: float = 2.0  # How far ahead to check for obstacles
@export var ceiling_check_height: float = 6.0  # Maximum height to check for ceiling
@export var ledge_scan_increment: float = 0.5  # Vertical increment for ledge scanning
@export var ledge_edge_precision: float = 0.1  # Precision for finding ledge edge

@export_group("Movement Physics")
@export var skid_threshold: float = 90.0  # Degrees of turn to trigger skid
@export var skid_duration: float = 0.3  # How long to skid
@export var skid_friction: float = 0.8  # Friction during skid (0-1)
@export var skid_speed_multiplier: float = 1.2  # Speed multiplier during skid

@export_group("References")
@export var player_path: NodePath
@export var aware_particles: GPUParticles3D
@export var debug_enabled: bool = false

# Internal State
var _state: State = State.IDLE
var _player: Node3D
var _can_attack: bool = true
var _can_jump: bool = true
var _aware_timer: float = 0.0
var _search_timer: float = 0.0
var _jump_timer: float = 0.0
var _particles_emitted: bool = false
var _stun_timer: float = 0.0
var _last_known_player_pos: Vector3
var _search_start_pos: Vector3
var _search_direction: Vector3
var _player_position_history: Array[Vector3] = []
var _player_time_history: Array[float] = []
var _prediction_delay: float = 0.8  # How far back to predict player position
var _total_time: float = 0.0  # Track total time for simpler timing
var _is_jumping: bool = false
var _is_climbing: bool = false
var _jump_start_pos: Vector3
var _jump_target_pos: Vector3
var _elevation_timer: float = 0.0
var _climb_target_pos: Vector3
var _climb_progress: float = 0.0
var _detected_ledge_pos: Vector3
var _detected_ledge_height: float = 0.0
var _terrain_check_timer: float = 0.0
var _last_facing_direction: Vector3
var _skid_timer: float = 0.0
var _skid_start_velocity: Vector3

# Navigation
@onready var _nav: NavigationAgent3D = get_node_or_null("NavigationAgent3D")
var _path_timer: float = 0.0
var _nav_target_reachable: bool = false
var _unreachable_attempts: int = 0
const MAX_UNREACHABLE_ATTEMPTS := 3

# Physics
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * 1.2

# Animation
@onready var _animation_player: AnimationPlayer = get_node_or_null("model/AnimationPlayer")

# Animation state mapping
var _animation_state_map: Dictionary = {
	State.IDLE: "idle",
	State.AWARE: "idle",
	State.CHASE: "pursuit",
	State.SEARCH: "idle",
	State.JUMP: "jumpfall_pose",
	State.CLIMB: "jumpfall_pose",
	State.SKID: "idle",
	State.ATTACK: "windup",  # Will transition to "punch" in _perform_attack
	State.PAIN: "idle",
	State.STUNNED: "stun",
	State.DEAD: "stun"
}

var _current_animation: String = ""
var _landing_timer: float = 0.0
var _landing_duration: float = 0.5  # How long to play land_pose
var _is_landing: bool = false
var _attack_sequence_active: bool = false

# AI Proxy for GameMaster compatibility
class BouncerAIProxy:
	extends Node
	enum States { IDLE, AWARE, CHASE }
	var awareness_threshold: float = 1.0
	var current_awareness: float = 1.0
	var player_in_range: bool = true
	var player: Node3D
	
	func change_state(state):
		pass
	
	func get_awareness_percentage():
		return current_awareness

func _ready() -> void:
	add_to_group("enemy")
	
	# Create AI proxy for GameMaster compatibility
	if not has_node("AI"):
		var proxy := BouncerAIProxy.new()
		proxy.name = "AI"
		add_child(proxy)
		proxy.player = _player
	
	# Setup navigation
	if _nav:
		_nav.avoidance_enabled = false
		_nav.max_speed = run_speed
		_nav.path_desired_distance = 1.0
		_nav.target_desired_distance = 1.5
	
	_resolve_player()
	_path_timer = randf_range(0.0, 0.25)
	
	# Initialize facing direction for skid detection
	_last_facing_direction = -transform.basis.z.normalized()
	_last_facing_direction.y = 0

func _resolve_player() -> void:
	_player = get_node_or_null(player_path)
	if _player == null:
		var g := get_tree().get_nodes_in_group("player")
		if g.size() > 0:
			_player = g[0]

func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	# Update timers
	_jump_timer = max(0.0, _jump_timer - delta)
	if _jump_timer <= 0.0:
		_can_jump = true

	# Update player position history
	_total_time += delta
	_update_player_history(delta)
	
	# Update landing sequence
	_update_landing_sequence(delta)

	# Apply gravity
	if not is_on_floor():
		velocity.y -= _gravity * delta

	if not is_instance_valid(_player):
		_resolve_player()
		if not is_instance_valid(_player):
			if debug_enabled:
				print("[Bouncer] Cannot find player. Bouncer is idle.")
			velocity.x = 0
			velocity.z = 0
			move_and_slide()
			return

	var dist := global_position.distance_to(_player.global_position)

	match _state:
		State.IDLE:
			_handle_idle_state(delta, dist)
		State.AWARE:
			_handle_aware_state(delta, dist)
		State.CHASE:
			_handle_chase_state(delta, dist)
		State.SEARCH:
			_handle_search_state(delta, dist)
		State.JUMP:
			_handle_jump_state(delta, dist)
		State.CLIMB:
			_handle_climb_state(delta, dist)
		State.SKID:
			_handle_skid_state(delta, dist)
		State.ATTACK:
			_handle_attack_state(delta, dist)
		State.PAIN:
			_handle_pain_state(delta)
		State.STUNNED:
			_handle_stunned_state(delta)

	move_and_slide()

func _handle_idle_state(delta: float, dist: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 0.1)
	velocity.z = move_toward(velocity.z, 0, 0.1)
	
	_update_animation_for_state()
	
	if dist < sight_range and _has_line_of_sight():
		_state = State.AWARE
		_aware_timer = 0.0
		_particles_emitted = false

func _handle_aware_state(delta: float, dist: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 0.1)
	velocity.z = move_toward(velocity.z, 0, 0.1)
	
	_face_player(delta)
	_update_animation_for_state()
	
	# Emit particles once when entering AWARE state
	if not _particles_emitted and aware_particles:
		aware_particles.restart()
		_particles_emitted = true
	
	_aware_timer += delta
	if _aware_timer >= aware_duration:
		_state = State.CHASE
		_last_known_player_pos = _player.global_position

func _handle_chase_state(delta: float, dist: float) -> void:
	if dist <= attack_range:
		_state = State.ATTACK
		return
	
	# Update last known position if we can see the player
	if _has_line_of_sight():
		_last_known_player_pos = _player.global_position
	
	# Check elevation difference and handle jumping/climbing
	_check_elevation_and_jump(delta)
	
	# Periodic terrain analysis for obstacle detection
	_terrain_check_timer += delta
	if _terrain_check_timer >= 0.5:  # Check every 0.5 seconds
		_terrain_check_timer = 0.0
		var terrain_analysis = _perform_terrain_analysis()
		
		# If there's an obstacle ahead and we're not already climbing, consider climbing
		if terrain_analysis.obstacle_ahead and _state != State.CLIMB and _state != State.JUMP:
			var elevation_diff = _player.global_position.y - global_position.y
			if elevation_diff > elevation_jump_threshold:
				_start_climbing()
	
	# Move toward predicted target position (0.8 seconds ago)
	var predicted_pos = _get_predicted_player_position()
	var target_pos = predicted_pos if _has_line_of_sight() else _last_known_player_pos
	_chase_toward(target_pos, delta)
	
	# Face the predicted position instead of current player position
	_face_position(predicted_pos, delta)
	
	# Check for direction change that should trigger skid
	if _check_for_direction_change():
		_start_skid()
		return
	
	_update_animation_for_state()
	
	# Check if we lost the player
	if not _has_line_of_sight():
		_search_timer += delta
		if _search_timer >= lose_target_time:
			_state = State.SEARCH
			_search_start_pos = global_position
			_search_direction = (_last_known_player_pos - global_position).normalized()
			_search_timer = 0.0
	else:
		_search_timer = 0.0

func _handle_search_state(delta: float, dist: float) -> void:
	# If we can see the player again, go back to chase
	if _has_line_of_sight():
		_state = State.CHASE
		return
	
	_search_timer += delta
	if _search_timer >= search_duration:
		_state = State.IDLE
		return
	
	# Search behavior - move toward last known position with some randomness
	var search_target = _last_known_player_pos + Vector3(
		randf_range(-2.0, 2.0),
		0,
		randf_range(-2.0, 2.0)
	)
	
	_chase_toward(search_target, delta)
	_face_position(search_target, delta)
	
	_update_animation_for_state()

func _handle_jump_state(delta: float, dist: float) -> void:
	if is_on_floor() and _is_jumping:
		_is_jumping = false
		_can_jump = false
		_jump_timer = jump_cooldown
		
		# Start landing sequence
		_start_landing_sequence()
		
		# Check if we need to start climbing
		if _should_start_climbing():
			_start_climbing()
		else:
			_state = State.CHASE
		return
	
	# Continue jump trajectory
	_update_animation_for_state()

func _handle_attack_state(delta: float, dist: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 0.1)
	velocity.z = move_toward(velocity.z, 0, 0.1)
	
	_face_player(delta)
	
	# Start attack sequence if not already active
	if not _attack_sequence_active and _can_attack:
		_start_attack_sequence()
	
	if dist > attack_range:
		_state = State.CHASE
		_attack_sequence_active = false
	elif _can_attack and _attack_sequence_active:
		_perform_attack()

func _handle_pain_state(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0, 0.1)
	velocity.z = move_toward(velocity.z, 0, 0.1)
	
	_update_animation_for_state()
	
	await get_tree().create_timer(0.3).timeout
	if _state != State.DEAD:
		_state = State.CHASE

func _handle_stunned_state(delta: float) -> void:
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0, 8.0)
		velocity.z = move_toward(velocity.z, 0, 8.0)
	
	_update_animation_for_state()
	
	_stun_timer -= delta
	if _stun_timer <= 0:
		_state = State.CHASE

func _start_jump() -> void:
	_state = State.JUMP
	_is_jumping = true
	_jump_start_pos = global_position
	
	# Calculate jump trajectory toward predicted player position
	var predicted_pos = _get_predicted_player_position()
	var jump_direction = (predicted_pos - global_position).normalized()
	jump_direction.y = 0
	
	# Apply jump velocity with more upward force for elevation gain
	velocity.x = jump_direction.x * jump_speed
	velocity.z = jump_direction.z * jump_speed
	velocity.y = jump_speed * 1.2  # Increased vertical component for elevation
	
	_update_animation_for_state()

func _chase_toward(target_pos: Vector3, delta: float) -> void:
	var dir: Vector3 = Vector3.ZERO
	var should_move: bool = false
	
	if _nav:
		_path_timer -= delta
		if _path_timer <= 0.0:
			_path_timer = 0.25
			_nav.target_position = target_pos
			_nav_target_reachable = _nav.is_target_reachable()
			if not _nav_target_reachable:
				_unreachable_attempts += 1
				if _unreachable_attempts >= MAX_UNREACHABLE_ATTEMPTS:
					_nav = null
			else:
				_unreachable_attempts = 0

		if _nav_target_reachable and not _nav.is_navigation_finished():
			var next_pos = _nav.get_next_path_position()
			if next_pos != Vector3.ZERO:
				dir = (next_pos - global_position).normalized()
				should_move = true
	else:
		dir = (target_pos - global_position).normalized()
		var distance_to_target = global_position.distance_to(target_pos)
		if distance_to_target > attack_range * 1.5:
			should_move = true

	dir.y = 0.0
	
	if should_move:
		velocity = velocity.lerp(dir * run_speed, 0.1)
	else:
		velocity.x = move_toward(velocity.x, 0, 0.1)
		velocity.z = move_toward(velocity.z, 0, 0.1)

func _face_player(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	
	var target_dir = (_player.global_position - global_position).normalized()
	target_dir.y = 0
	
	if target_dir.length() > 0:
		var target_transform = transform.looking_at(global_position + target_dir, Vector3.UP)
		transform = transform.interpolate_with(target_transform, turn_speed * delta)

func _face_position(target_pos: Vector3, delta: float) -> void:
	var target_dir = (target_pos - global_position).normalized()
	target_dir.y = 0
	
	if target_dir.length() > 0:
		var target_transform = transform.looking_at(global_position + target_dir, Vector3.UP)
		transform = transform.interpolate_with(target_transform, turn_speed * delta)

func _has_line_of_sight() -> bool:
	if not is_instance_valid(_player):
		return false
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.5, 0),  # Eye level
		_player.global_position + Vector3(0, 1.0, 0),  # Player chest level
		1  # Collision mask
	)
	var result = space_state.intersect_ray(query)
	
	return result.is_empty() or result.collider == _player

func _perform_attack() -> void:
	_can_attack = false
	
	if debug_enabled:
		print("[Bouncer] Punch!")
	
	# Complete the attack sequence with punch animation
	_complete_attack_sequence()
	
	# Damage and launch player
	if _player.has_method("take_damage"):
		_player.take_damage(damage)
	
	# Launch player away
	if _player is CharacterBody3D:
		var launch_direction = (_player.global_position - global_position).normalized()
		launch_direction.y = 0
		
		var vertical_component = sin(deg_to_rad(launch_angle))
		var launch_vector = launch_direction * launch_force
		launch_vector.y = vertical_component * launch_force
		
		(_player as CharacterBody3D).velocity = launch_vector
	
	# Call player's take_hit function if available
	var player_state = _player.get_node_or_null("PlayerState")
	if player_state and player_state.has_method("take_hit"):
		player_state.take_hit()

	# Attack cooldown
	await get_tree().create_timer(attack_cooldown).timeout
	_can_attack = true
	_attack_sequence_active = false
	
	if _state == State.ATTACK:
		_state = State.CHASE

func _play_animation(anim_name: String) -> void:
	if _animation_player and _animation_player.has_animation(anim_name):
		if _current_animation != anim_name:
			_current_animation = anim_name
			_animation_player.play(anim_name)

func _update_animation_for_state() -> void:
	"""Automatically update animation based on current state"""
	# Don't change animation if we're in a special sequence
	if _attack_sequence_active or _is_landing:
		return
	
	var target_animation = _animation_state_map.get(_state, "idle")
	_play_animation(target_animation)

func _start_landing_sequence() -> void:
	"""Start the landing sequence with land_pose then transition to pursuit"""
	_is_landing = true
	_landing_timer = _landing_duration
	_play_animation("land_pose")

func _update_landing_sequence(delta: float) -> void:
	"""Update landing sequence timer and transition to pursuit when done"""
	if _is_landing:
		_landing_timer -= delta
		if _landing_timer <= 0.0:
			_is_landing = false
			_play_animation("pursuit")

func _start_attack_sequence() -> void:
	"""Start the attack sequence with windup"""
	_attack_sequence_active = true
	_play_animation("windup")

func _complete_attack_sequence() -> void:
	"""Complete the attack sequence with punch animation"""
	_play_animation("punch")
	# Reset attack sequence after punch animation
	await get_tree().create_timer(0.3).timeout  # Adjust timing as needed
	_attack_sequence_active = false

func _check_elevation_and_jump(delta: float) -> void:
	if not is_instance_valid(_player) or not is_on_floor() or not _can_jump:
		_elevation_timer = 0.0
		return
	
	# Use predicted position for elevation checking
	var predicted_pos = _get_predicted_player_position()
	var elevation_diff = predicted_pos.y - global_position.y
	
	# Check if predicted player position is significantly higher
	if elevation_diff > elevation_jump_threshold:
		_elevation_timer += delta
		
		# Jump if player has been higher for the required time
		if _elevation_timer >= elevation_time_threshold:
			# Check if we can reach the predicted position with a jump
			if _can_jump_reach_position(predicted_pos):
				_start_jump()
			else:
				# Need to climb instead
				_start_climbing()
			_elevation_timer = 0.0
	else:
		_elevation_timer = 0.0

func _should_start_climbing() -> bool:
	if not is_instance_valid(_player):
		return false
	
	var elevation_diff = _player.global_position.y - global_position.y
	return elevation_diff > elevation_jump_threshold

func _start_climbing() -> void:
	# Perform terrain analysis to find the best climbing path
	var terrain_analysis = _perform_terrain_analysis()
	
	if terrain_analysis.ledge_found:
		_state = State.CLIMB
		_is_climbing = true
		_climb_target_pos = terrain_analysis.ledge_edge
		_detected_ledge_pos = terrain_analysis.ledge_position
		_detected_ledge_height = terrain_analysis.ledge_position.y
		_climb_progress = 0.0
		_update_animation_for_state()
		
		if debug_enabled:
			print("[Bouncer] Starting climb to ledge at: ", _climb_target_pos)
	else:
		# No climbable ledge found, try to jump anyway
		if debug_enabled:
			print("[Bouncer] No climbable ledge found, attempting jump")
		_start_jump()

func _handle_climb_state(delta: float, dist: float) -> void:
	if not is_instance_valid(_player):
		_state = State.CHASE
		_is_climbing = false
		return
	
	# Move toward the detected ledge edge
	var distance_to_ledge = global_position.distance_to(_climb_target_pos)
	
	if distance_to_ledge < 0.5:
		# Reached the ledge, now climb up
		_climb_progress += delta * 2.0  # Climbing speed
		
		if _climb_progress >= 1.0:
			# Climb complete, move to ledge position
			global_position = _detected_ledge_pos
			_state = State.CHASE
			_is_climbing = false
			_climb_progress = 0.0
			
			if debug_enabled:
				print("[Bouncer] Climb complete, reached ledge")
			return
		
		# During climb, move upward
		velocity.y = run_speed * 0.5
		velocity.x = 0
		velocity.z = 0
	else:
		# Move toward the ledge edge
		var climb_direction = (_climb_target_pos - global_position).normalized()
		climb_direction.y = 0  # Keep horizontal movement
		
		velocity = velocity.lerp(climb_direction * run_speed, 0.1)
		
		# Face the climbing direction
		_face_position(_climb_target_pos, delta)
	
	_update_animation_for_state()

func _handle_skid_state(delta: float, dist: float) -> void:
	_skid_timer -= delta
	
	# Apply skid physics - maintain momentum with reduced friction
	velocity.x = move_toward(velocity.x, 0, skid_friction * 10.0)
	velocity.z = move_toward(velocity.z, 0, skid_friction * 10.0)
	
	# Face the direction we're skidding
	_face_skid_direction(delta)
	
	_update_animation_for_state()
	
	if _skid_timer <= 0.0:
		_state = State.CHASE
		if debug_enabled:
			print("[Bouncer] Skid complete")

func _check_for_direction_change() -> bool:
	if not is_on_floor():
		return false
	
	var current_facing = -transform.basis.z.normalized()
	current_facing.y = 0
	
	if _last_facing_direction == Vector3.ZERO:
		_last_facing_direction = current_facing
		return false
	
	var angle_change = rad_to_deg(_last_facing_direction.angle_to(current_facing))
	
	# Update last facing direction
	_last_facing_direction = current_facing
	
	return abs(angle_change) > skid_threshold

func _start_skid() -> void:
	_state = State.SKID
	_skid_timer = skid_duration
	_skid_start_velocity = velocity
	
	# Boost speed during skid
	velocity *= skid_speed_multiplier
	
	if debug_enabled:
		print("[Bouncer] Starting skid! Velocity: ", velocity)

func _face_skid_direction(delta: float) -> void:
	# Face the direction of movement during skid
	var move_direction = velocity.normalized()
	move_direction.y = 0
	
	if move_direction.length() > 0.1:
		var target_transform = transform.looking_at(global_position + move_direction, Vector3.UP)
		transform = transform.interpolate_with(target_transform, turn_speed * 2.0 * delta)  # Faster turning during skid

func _update_player_history(delta: float) -> void:
	if not is_instance_valid(_player):
		return
	
	# Add current player position to history
	_player_position_history.append(_player.global_position)
	_player_time_history.append(_total_time)
	
	# Remove old entries (keep only last 2 seconds of history)
	while _player_time_history.size() > 0 and _total_time - _player_time_history[0] > 2.0:
		_player_position_history.pop_front()
		_player_time_history.pop_front()

func _get_predicted_player_position() -> Vector3:
	if _player_position_history.size() == 0:
		return _player.global_position if is_instance_valid(_player) else global_position
	
	var target_time = _total_time - _prediction_delay
	
	# Find the closest time in history
	var closest_index = 0
	var closest_time_diff = abs(_player_time_history[0] - target_time)
	
	for i in range(1, _player_time_history.size()):
		var time_diff = abs(_player_time_history[i] - target_time)
		if time_diff < closest_time_diff:
			closest_time_diff = time_diff
			closest_index = i
	
	return _player_position_history[closest_index]

func _can_jump_reach_player() -> bool:
	if not is_instance_valid(_player):
		return false
	
	var elevation_diff = _player.global_position.y - global_position.y
	return elevation_diff <= max_jump_height

func _can_jump_reach_position(target_pos: Vector3) -> bool:
	var elevation_diff = target_pos.y - global_position.y
	return elevation_diff <= max_jump_height

func _detect_obstacle_ahead() -> bool:
	var space_state = get_world_3d().direct_space_state
	var forward_direction = -transform.basis.z.normalized()
	var check_start = global_position + Vector3(0, 1.0, 0)  # Eye level
	var check_end = check_start + forward_direction * obstacle_check_distance
	
	var query = PhysicsRayQueryParameters3D.create(check_start, check_end, 1)
	var result = space_state.intersect_ray(query)
	
	return not result.is_empty()

func _find_ceiling_height() -> float:
	var space_state = get_world_3d().direct_space_state
	var check_start = global_position + Vector3(0, 1.5, 0)  # Head level
	var check_end = check_start + Vector3(0, ceiling_check_height, 0)
	
	var query = PhysicsRayQueryParameters3D.create(check_start, check_end, 1)
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return ceiling_check_height
	else:
		return result.position.y - global_position.y

func _find_ledge() -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var forward_direction = -transform.basis.z.normalized()
	var ceiling_height = _find_ceiling_height()
	
	# Scan from lowest to highest to find first unobstructed path
	for height in range(0, int(ceiling_height * 10), int(ledge_scan_increment * 10)):
		var scan_height = height / 10.0
		var check_start = global_position + Vector3(0, scan_height, 0)
		var check_end = check_start + forward_direction * obstacle_check_distance
		
		var query = PhysicsRayQueryParameters3D.create(check_start, check_end, 1)
		var result = space_state.intersect_ray(query)
		
		if result.is_empty():
			# Found unobstructed path, now find the ledge height
			return _find_ledge_height(check_start)
	
	return Vector3.ZERO

func _find_ledge_height(scan_position: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var forward_direction = -transform.basis.z.normalized()
	
	# Trace downward from the unobstructed position
	var check_start = scan_position + forward_direction * obstacle_check_distance
	var check_end = check_start + Vector3(0, -ceiling_check_height, 0)
	
	var query = PhysicsRayQueryParameters3D.create(check_start, check_end, 1)
	var result = space_state.intersect_ray(query)
	
	if not result.is_empty():
		return result.position
	
	return Vector3.ZERO

func _find_ledge_forward_edge(ledge_position: Vector3) -> Vector3:
	var space_state = get_world_3d().direct_space_state
	var forward_direction = -transform.basis.z.normalized()
	var ledge_height = ledge_position.y
	
	# Step backwards from the ledge to find the edge
	var step_distance = ledge_edge_precision
	var current_pos = ledge_position
	
	for i in range(20):  # Limit iterations
		var check_start = current_pos + Vector3(0, 0.1, 0)  # Slightly above ledge
		var check_end = check_start + Vector3(0, -0.2, 0)  # Check downward
		
		var query = PhysicsRayQueryParameters3D.create(check_start, check_end, 1)
		var result = space_state.intersect_ray(query)
		
		if result.is_empty():
			# Found the edge
			return current_pos
		
		# Step backwards
		current_pos -= forward_direction * step_distance
	
	return ledge_position

func _perform_terrain_analysis() -> Dictionary:
	var analysis = {
		"obstacle_ahead": false,
		"ceiling_height": 0.0,
		"ledge_found": false,
		"ledge_position": Vector3.ZERO,
		"ledge_edge": Vector3.ZERO
	}
	
	# Check for obstacles ahead
	analysis.obstacle_ahead = _detect_obstacle_ahead()
	
	if analysis.obstacle_ahead:
		# Find ceiling height
		analysis.ceiling_height = _find_ceiling_height()
		
		# Find ledge
		var ledge_pos = _find_ledge()
		if ledge_pos != Vector3.ZERO:
			analysis.ledge_found = true
			analysis.ledge_position = ledge_pos
			analysis.ledge_edge = _find_ledge_forward_edge(ledge_pos)
	
	return analysis

# External damage interface
func take_damage(amount: int) -> void:
	if _state == State.DEAD:
		return

	health -= amount
	if health <= 0:
		_die()
	else:
		_pain()

func apply_stun(duration: float) -> void:
	if _state != State.DEAD:
		_state = State.STUNNED
		_stun_timer = duration

func _pain() -> void:
	_state = State.PAIN
	if debug_enabled:
		print("[Bouncer] Pain!")
	await get_tree().create_timer(0.2).timeout
	if _state != State.DEAD:
		_state = State.CHASE

func _die() -> void:
	_state = State.DEAD
	if debug_enabled:
		print("[Bouncer] Dead.")
	queue_free()

# Exposed for GameMaster - boost speed
func boost_speed(multiplier: float):
	run_speed *= multiplier
	if _state != State.DEAD:
		_state = State.CHASE 
