extends CharacterBody3D
class_name QuakeKnight

# -----------------------------------------------------------------------------
#  All-in-one re-implementation of Quake's melee-only Knight.
#  No external dependencies: drop this script onto a CharacterBody3D, add a
#  CollisionShape3D and (optionally) a NavigationAgent3D if you want path-finding.
# -----------------------------------------------------------------------------

enum State { IDLE, AWARE, CHASE, MELEE, ATTACKING, PAIN, STUNNED, DEAD }

@export var health:           int   = 75     # Quake Knight base HP
@export var run_speed:        float = 4.8    # metres / second
@export var melee_range:      float = 1.8    # sword reach
@export var damage:           int   = 25     # per swing
@export var attack_cooldown:  float = 1.0    # seconds between swings
@export var player_path:      NodePath       # set in Inspector or put player in "player" group
@export var debug_enabled:    bool  = false
@export var performance_debug: bool = false  # Show performance metrics
@export var turn_speed:       float = 5.0    # how fast the knight turns to face player
@export var turn_threshold:   float = 0.1    # how close to target rotation before considered "done turning"
@export var aware_duration:   float = 0.7    # how long to stay in AWARE state (seconds)
@export var launch_force:     float = 11.0   # how hard to launch the player
@export var launch_angle:     float = 45.0   # launch angle in degrees
@export var aware_particles:  GPUParticles3D  # particles to emit when becoming aware

# Performance / navigation tuning ------------------------------
@export var path_refresh:       float = 0.25   # seconds between navigation path updates
@export var active_distance:    float = 40.0   # beyond this, knight idles to save CPU
@export var ignore_enemy_collisions: bool = true # when true, Knights don't collide with each other
@export var enemy_layer: int = 4                 # physics layer index used by Knights (1-20)
@export var ai_refresh:         float = 0.05   # seconds between heavy AI updates (chase, rotation etc.)

# Advanced performance settings - More aggressive LOD system
@export var lod_distances: Array[float] = [8.0, 16.0, 25.0, 40.0, 60.0]  # 5 LOD levels
@export var lod_update_rates: Array[float] = [0.033, 0.066, 0.15, 0.33, 0.66, 1.0]  # Update rates per LOD level
@export var max_knights_full_update: int = 6  # Reduced max knights updating at full rate per frame
@export var player_cache_duration: float = 1.0  # How long to cache player reference
@export var micro_lod_distance: float = 80.0  # Beyond this, knights enter micro-LOD mode
@export var culling_distance: float = 100.0  # Beyond this, knights are completely culled

# Emergency performance scaling
@export var target_fps: float = 60.0  # Target frame rate
@export var emergency_fps_threshold: float = 45.0  # Below this, emergency scaling kicks in
@export var performance_recovery_fps: float = 55.0  # Above this, emergency scaling is disabled

# Internal ---------------------------------------------------------------------
var _state:    State = State.IDLE
var _player:   Node3D
var _can_attack: bool = true
var _player_not_found_warning: bool = false
var _aware_timer: float = 0.0
var _particles_emitted: bool = false
var _stun_timer: float = 0.0
var _force_chase: bool = false   # When true, Knight will chase player globally

# Nav helpers
var _path_timer: float = 0.0
var _nav_target_reachable: bool = false
var _unreachable_attempts: int = 0
const MAX_UNREACHABLE_ATTEMPTS := 3
var _ai_timer: float = 0.0

# Advanced navigation caching
var _cached_nav_path: PackedVector3Array = []
var _nav_path_index: int = 0
var _nav_path_cache_timer: float = 0.0
var _last_nav_target: Vector3
var _nav_recalc_distance_threshold: float = 2.0  # Recalculate path if target moves this far

# Performance optimization variables
var _current_lod_level: int = 0
var _cached_distance: float = 0.0
var _distance_cache_timer: float = 0.0
var _player_cache_timer: float = 0.0
var _cached_player_position: Vector3
var _cached_direction: Vector3
var _direction_cache_timer: float = 0.0
var _update_offset: float = 0.0  # Stagger updates across knights
var _knight_id: int = 0  # Unique ID for this knight instance

# Micro-LOD and culling system
var _is_micro_lod: bool = false
var _is_culled: bool = false
var _micro_lod_timer: float = 0.0
var _culling_check_timer: float = 0.0

# Static performance management
static var _knight_counter: int = 0
static var _knights_updated_this_frame: int = 0
static var _frame_counter: int = 0

# Emergency performance scaling (static across all knights)
static var _emergency_mode: bool = false
static var _fps_samples: Array[float] = []
static var _fps_check_timer: float = 0.0
static var _emergency_lod_multiplier: float = 1.0

# Object pooling for frequently used objects
static var _vector3_pool: Array[Vector3] = []
static var _array_pool: Array[Array] = []

# Spatial awareness system
@export var avoidance_radius: float = 2.0
@export var avoidance_strength: float = 0.3
var _nearby_knights: Array[Node3D] = []
var _spatial_update_timer: float = 0.0
var _spatial_update_interval: float = 0.2  # Update nearby knights every 0.2 seconds

# Performance monitoring
var _performance_timer: float = 0.0
var _frame_time_samples: Array[float] = []
var _avg_frame_time: float = 0.0
var _peak_frame_time: float = 0.0

@onready var _nav: NavigationAgent3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * 1.5 # Heavier so it falls faster

# -----------------------------------------------------------------------------
#  Doom-charge integration helpers (used by GameMaster)
# -----------------------------------------------------------------------------
# GameMaster expects each enemy to have:
#   • A child node called "AI" with: States enum, change_state(), awareness_threshold,
#     current_awareness, player_in_range, player reference.
#   • Root script exposing boost_speed(multiplier) to accelerate movement.
#  We create a minimal proxy node at runtime to satisfy those calls without
#  changing existing Knight logic.

class KnightAIProxy:
	extends Node
	# Minimal enum with CHASE state (value 2 to match Knight.State.CHASE)
	enum States { IDLE, AWARE, CHASE }

	var awareness_threshold: float = 1.0
	var current_awareness: float = 1.0
	var player_in_range: bool = true
	var player: Node3D

	func change_state(state):
		# No-op – Knight already chases based on its own logic
		pass

	func get_awareness_percentage():
		return current_awareness


func _ready() -> void:
	add_to_group("enemy")

	# Assign unique ID and stagger updates
	_knight_counter += 1
	_knight_id = _knight_counter
	_update_offset = (_knight_id % 10) * 0.01  # Spread updates over 0.1 seconds

	# Create AI proxy so GameMaster can interact during Doom charge
	if not has_node("AI"):
		var proxy := KnightAIProxy.new()
		proxy.name = "AI"
		add_child(proxy)
		# Attempt to set player reference if available
		proxy.player = _player
	if has_node("NavigationAgent3D"):
		_nav = $NavigationAgent3D
		# Disable crowd avoidance
		_nav.avoidance_enabled = false
	else:
		_nav = null

	# Optional: ignore collisions between Knights to reduce physics overhead
	if ignore_enemy_collisions:
		# Ensure we're on the enemy layer
		collision_layer = 1 << (enemy_layer - 1)
		# Collide with everything except our own layer
		for i in range(20):
			set_collision_mask_value(i + 1, i != (enemy_layer - 1))

	_resolve_player()
	# Stagger timers to distribute load
	_path_timer = randf_range(0.0, path_refresh)
	_ai_timer = randf_range(0.0, ai_refresh) + _update_offset
	_distance_cache_timer = randf_range(0.0, 0.1)
	_direction_cache_timer = randf_range(0.0, 0.05)

func _resolve_player() -> void:
	_player = get_node_or_null(player_path)
	if _player == null:
		var g := get_tree().get_nodes_in_group("player")
		if g.size() > 0:
			_player = g[0]

# Performance optimization functions
func _get_cached_distance_to_player() -> float:
	if _distance_cache_timer <= 0.0:
		if is_instance_valid(_player):
			_cached_distance = global_position.distance_to(_player.global_position)
			_cached_player_position = _player.global_position
		_distance_cache_timer = 0.1  # Cache for 0.1 seconds
	return _cached_distance

func _get_cached_direction_to_player() -> Vector3:
	if _direction_cache_timer <= 0.0:
		if is_instance_valid(_player):
			_cached_direction = (_player.global_position - global_position).normalized()
			_cached_direction.y = 0.0
		_direction_cache_timer = 0.05  # Cache for 0.05 seconds
	return _cached_direction

func _update_lod_level() -> void:
	var dist = _get_cached_distance_to_player()

	# DOOM state knights (force_chase) have special LOD handling
	if _force_chase:
		# DOOM knights are never culled - they must always pursue
		_is_culled = false

		# DOOM knights can use micro-LOD for very distant movement
		if dist > micro_lod_distance:
			_is_micro_lod = true
			_current_lod_level = lod_update_rates.size() - 1
			return
		else:
			_is_micro_lod = false

		# DOOM knights use slightly better LOD levels to maintain pursuit
		_current_lod_level = lod_distances.size()  # Default to lowest LOD
		for i in range(lod_distances.size()):
			if dist <= lod_distances[i]:
				_current_lod_level = min(i + 1, lod_distances.size() - 1)  # One level better than normal
				break
		return

	# Standard knights can be culled and use normal LOD
	# Check for culling first
	if dist > culling_distance:
		_is_culled = true
		_is_micro_lod = false
		_current_lod_level = lod_update_rates.size() - 1
		return
	else:
		_is_culled = false

	# Check for micro-LOD
	if dist > micro_lod_distance:
		_is_micro_lod = true
		_current_lod_level = lod_update_rates.size() - 1
		return
	else:
		_is_micro_lod = false

	# Standard LOD calculation with more aggressive levels
	_current_lod_level = lod_distances.size()  # Default to lowest LOD

	for i in range(lod_distances.size()):
		if dist <= lod_distances[i]:
			_current_lod_level = i
			break

func _should_update_ai() -> bool:
	# Reset frame counter for static tracking
	if Engine.get_process_frames() != _frame_counter:
		_frame_counter = Engine.get_process_frames()
		_knights_updated_this_frame = 0

	# Always update if we're in critical states
	if _state in [State.ATTACKING, State.PAIN, State.STUNNED]:
		return true

	# DOOM knights (force_chase) get priority updates even at high LOD
	if _force_chase:
		# DOOM knights always get at least some updates, even in emergency mode
		var doom_lod_level = min(_current_lod_level, lod_update_rates.size() - 2)  # Never use the slowest rate
		var update_rate = lod_update_rates[doom_lod_level]

		# Reduced emergency penalty for DOOM knights
		if _emergency_mode:
			update_rate *= min(_emergency_lod_multiplier, 1.5)  # Cap emergency penalty

		if _ai_timer <= 0.0:
			_ai_timer = update_rate + _update_offset
			if doom_lod_level == 0:
				_knights_updated_this_frame += 1
			return true
		return false

	# Check if we've exceeded the frame budget for full updates (normal knights only)
	if _current_lod_level == 0 and _knights_updated_this_frame >= max_knights_full_update:
		return false

	# Check if it's time for our LOD-based update (with emergency scaling)
	var effective_lod_level = _get_emergency_adjusted_lod_level()
	var update_rate = lod_update_rates[min(effective_lod_level, lod_update_rates.size() - 1)]

	# In emergency mode, further reduce update frequency
	if _emergency_mode:
		update_rate *= _emergency_lod_multiplier

	if _ai_timer <= 0.0:
		_ai_timer = update_rate + _update_offset
		if effective_lod_level == 0:
			_knights_updated_this_frame += 1
		return true

	return false

# Spatial awareness functions
func _update_nearby_knights() -> void:
	_nearby_knights.clear()

	# Skip spatial awareness in emergency mode or high LOD levels
	if _emergency_mode or _current_lod_level > 3:
		return

	var all_enemies = get_tree().get_nodes_in_group("enemy")
	var detection_radius_sq = (avoidance_radius * 2.0) * (avoidance_radius * 2.0)

	for enemy in all_enemies:
		if enemy == self or not enemy is Node3D:
			continue

		# Use distance_squared for performance
		var distance_sq = global_position.distance_squared_to((enemy as Node3D).global_position)
		if distance_sq <= detection_radius_sq:
			_nearby_knights.append(enemy as Node3D)

func _get_avoidance_vector() -> Vector3:
	var avoidance = Vector3.ZERO

	for knight in _nearby_knights:
		if not is_instance_valid(knight):
			continue

		var delta = global_position - knight.global_position
		delta.y = 0  # Keep horizontal
		var distance = delta.length()

		if distance > 0 and distance < avoidance_radius:
			var strength = (avoidance_radius - distance) / avoidance_radius
			avoidance += delta.normalized() * strength

	return avoidance.normalized() * avoidance_strength

# Object pooling functions
static func _get_pooled_vector3() -> Vector3:
	if _vector3_pool.size() > 0:
		return _vector3_pool.pop_back()
	return Vector3.ZERO

static func _return_vector3(vec: Vector3) -> void:
	if _vector3_pool.size() < 50:  # Limit pool size
		vec.x = 0.0
		vec.y = 0.0
		vec.z = 0.0
		_vector3_pool.append(vec)

static func _get_pooled_array() -> Array:
	if _array_pool.size() > 0:
		var arr = _array_pool.pop_back()
		arr.clear()
		return arr
	return []

static func _return_array(arr: Array) -> void:
	if _array_pool.size() < 20:  # Limit pool size
		arr.clear()
		_array_pool.append(arr)

# Emergency performance scaling functions
static func _update_emergency_scaling(delta: float) -> void:
	_fps_check_timer += delta

	# Check FPS every 0.5 seconds
	if _fps_check_timer >= 0.5:
		_fps_check_timer = 0.0
		var current_fps = Engine.get_frames_per_second()

		_fps_samples.append(current_fps)
		if _fps_samples.size() > 10:  # Keep last 10 samples (5 seconds)
			_fps_samples.pop_front()

		# Calculate average FPS
		var avg_fps = 0.0
		for fps in _fps_samples:
			avg_fps += fps
		avg_fps /= _fps_samples.size()

		# Emergency mode logic
		if not _emergency_mode and avg_fps < 45.0:  # Emergency threshold
			_emergency_mode = true
			_emergency_lod_multiplier = 2.0  # Double LOD distances
			print("[Knight Emergency] Performance scaling activated - FPS: %.1f" % avg_fps)
		elif _emergency_mode and avg_fps > 55.0:  # Recovery threshold
			_emergency_mode = false
			_emergency_lod_multiplier = 1.0
			print("[Knight Emergency] Performance scaling deactivated - FPS: %.1f" % avg_fps)

func _get_emergency_adjusted_lod_level() -> int:
	if not _emergency_mode:
		return _current_lod_level

	# In emergency mode, push knights to higher LOD levels
	var adjusted_level = _current_lod_level + 1
	return min(adjusted_level, lod_update_rates.size() - 1)

# DOOM state micro-LOD movement for distant knights
func _doom_micro_lod_movement(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	var dist = _get_cached_distance_to_player()
	var player_pos = _cached_player_position  # Use the cached position directly

	# Apply gravity
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# For very distant DOOM knights, use teleport-style movement
	if dist > micro_lod_distance * 1.5:  # Beyond 120m
		_doom_teleport_movement(player_pos, dist)
	else:
		# Use simplified direct movement for moderately distant DOOM knights
		_doom_direct_movement(player_pos, delta)

	move_and_slide()

# Teleport-style movement for extremely distant DOOM knights
func _doom_teleport_movement(player_pos: Vector3, dist: float) -> void:
	# Calculate a position closer to the player (but not too close)
	var direction = (player_pos - global_position).normalized()
	var teleport_distance = min(dist * 0.3, 30.0)  # Move 30% closer or 30m max
	var target_pos = global_position + direction * teleport_distance

	# Ensure the target position is on the ground (simple Y adjustment)
	target_pos.y = player_pos.y  # Assume same height as player for simplicity

	# Teleport to new position
	global_position = target_pos

	# Set velocity toward player for next frame
	velocity.x = direction.x * run_speed * 0.5
	velocity.z = direction.z * run_speed * 0.5

# Direct movement for moderately distant DOOM knights
func _doom_direct_movement(player_pos: Vector3, delta: float) -> void:
	var direction = (player_pos - global_position).normalized()
	direction.y = 0.0  # Keep movement horizontal

	# Use reduced speed but ensure continuous movement
	var doom_speed = run_speed * 0.7  # 70% of normal speed
	velocity.x = direction.x * doom_speed
	velocity.z = direction.z * doom_speed

# Performance monitoring functions
func _update_performance_metrics(delta: float) -> void:
	if not performance_debug:
		return

	_performance_timer += delta
	_frame_time_samples.append(delta)

	# Keep only last 60 samples (roughly 1 second at 60fps)
	if _frame_time_samples.size() > 60:
		_frame_time_samples.pop_front()

	# Update metrics every second
	if _performance_timer >= 1.0:
		_performance_timer = 0.0

		# Calculate average
		var sum = 0.0
		_peak_frame_time = 0.0
		for sample in _frame_time_samples:
			sum += sample
			_peak_frame_time = max(_peak_frame_time, sample)
		_avg_frame_time = sum / _frame_time_samples.size()

		# Print performance stats
		print("[Knight %d] LOD: %d, Avg: %.3fms, Peak: %.3fms, Nearby: %d" % [
			_knight_id, _current_lod_level, _avg_frame_time * 1000,
			_peak_frame_time * 1000, _nearby_knights.size()
		])

func get_performance_info() -> Dictionary:
	return {
		"knight_id": _knight_id,
		"lod_level": _current_lod_level,
		"effective_lod_level": _get_emergency_adjusted_lod_level(),
		"avg_frame_time_ms": _avg_frame_time * 1000,
		"peak_frame_time_ms": _peak_frame_time * 1000,
		"nearby_knights": _nearby_knights.size(),
		"state": State.keys()[_state],
		"distance_to_player": _cached_distance,
		"is_micro_lod": _is_micro_lod,
		"is_culled": _is_culled,
		"emergency_mode": _emergency_mode,
		"is_doom_state": _force_chase
	}

# Static function to get overall performance stats
static func get_global_performance_stats() -> Dictionary:
	return {
		"total_knights": _knight_counter,
		"knights_updated_this_frame": _knights_updated_this_frame,
		"emergency_mode": _emergency_mode,
		"emergency_lod_multiplier": _emergency_lod_multiplier,
		"current_fps": Engine.get_frames_per_second(),
		"vector3_pool_size": _vector3_pool.size(),
		"array_pool_size": _array_pool.size()
	}

# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var frame_start_time = Time.get_ticks_usec()

	# Update emergency performance scaling (only first knight per frame)
	if _knight_id == 0:
		_update_emergency_scaling(delta)

	# Update timers
	_ai_timer -= delta
	_distance_cache_timer -= delta
	_direction_cache_timer -= delta
	_player_cache_timer -= delta
	_spatial_update_timer -= delta
	_facing_cache_timer -= delta
	_micro_lod_timer -= delta
	_culling_check_timer -= delta
	_rotation_cache_timer -= delta

	if _state == State.DEAD:
		return

	# Update LOD level first to determine processing level
	_update_lod_level()

	# Handle culled knights - minimal processing
	if _is_culled:
		_culling_check_timer -= delta
		if _culling_check_timer <= 0.0:
			_culling_check_timer = 2.0  # Check every 2 seconds if we should un-cull
			# Just update distance cache and return
			if _distance_cache_timer <= 0.0:
				_get_cached_distance_to_player()
		return

	# Handle micro-LOD knights - very minimal processing
	if _is_micro_lod:
		_micro_lod_timer -= delta
		if _micro_lod_timer <= 0.0:
			if _force_chase:
				# DOOM knights in micro-LOD use simplified pursuit
				_micro_lod_timer = 0.5  # Update every 0.5 seconds for DOOM knights
				_doom_micro_lod_movement(delta)
			else:
				# Normal knights in micro-LOD just slow down
				_micro_lod_timer = 1.0  # Update every second in micro-LOD
				if not is_on_floor():
					velocity.y -= _gravity * delta
				velocity.x = move_toward(velocity.x, 0, 0.05)
				velocity.z = move_toward(velocity.z, 0, 0.05)
				move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Optimized player resolution with caching
	if not is_instance_valid(_player) or _player_cache_timer <= 0.0:
		_resolve_player()
		_player_cache_timer = player_cache_duration
		if not is_instance_valid(_player):
			if debug_enabled and not _player_not_found_warning:
				print("[Knight] Cannot find player. Knight is idle. Ensure player has 'player' group or player_path is set.")
				_player_not_found_warning = true
			velocity.x = 0
			velocity.z = 0
			move_and_slide()
			return

	# Update spatial awareness periodically
	if _spatial_update_timer <= 0.0:
		_spatial_update_timer = _spatial_update_interval
		_update_nearby_knights()

	# Update LOD level and check if we should update AI this frame
	_update_lod_level()
	var should_update = _should_update_ai()
	var dist = _get_cached_distance_to_player()

	# Performance LOD: if far away and not forced, idle to save CPU
	if dist > active_distance and not _force_chase:
		velocity.x = move_toward(velocity.x, 0, 0.1)
		velocity.z = move_toward(velocity.z, 0, 0.1)
		move_and_slide()
		return

	match _state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, 0.1)
			velocity.z = move_toward(velocity.z, 0, 0.1)
			if should_update and dist < 10.0:
				_state = State.AWARE
				_aware_timer = 0.0  # Reset timer when entering AWARE state
				_particles_emitted = false  # Reset particle flag
		State.AWARE:
			velocity.x = move_toward(velocity.x, 0, 0.1)
			velocity.z = move_toward(velocity.z, 0, 0.1)
			if should_update:
				_face_player(delta)

			# Emit particles once when entering AWARE state
			if not _particles_emitted and aware_particles:
				aware_particles.restart()
				_particles_emitted = true

			_aware_timer += delta
			if _aware_timer >= aware_duration:
				_state = State.CHASE
		State.CHASE:
			if should_update:
				if dist <= melee_range:
					_state = State.MELEE
				elif dist > 10.0 and not _force_chase:
					_state = State.IDLE
				else:
					_chase(delta)
					_face_player(delta)
			else:
				# Light update - just continue moving in last direction
				_chase_light(delta)
		State.MELEE:
			velocity.x = move_toward(velocity.x, 0, 0.1)
			velocity.z = move_toward(velocity.z, 0, 0.1)
			if should_update:
				_face_player(delta)
				if dist > melee_range:
					_state = State.CHASE
				elif _can_attack:
					# ensure attack decision on AI frames only
					_state = State.ATTACKING
					_swing_sword()
		State.ATTACKING:
			# Stay completely still during attack
			velocity.x = 0
			velocity.z = 0
			# Will return to MELEE state when _swing_sword() completes
		State.PAIN:
			velocity.x = move_toward(velocity.x, 0, 0.1)
			velocity.z = move_toward(velocity.z, 0, 0.1)
		State.STUNNED:
			# Only damp horizontal velocity when on the ground so airborne launches maintain trajectory.
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0, 8.0)
				velocity.z = move_toward(velocity.z, 0, 8.0)
			_stun_timer -= delta
			if _stun_timer <= 0:
				_state = State.CHASE

	# Update attack timers
	_update_attack_timers(delta)

	# Update pain timer
	_update_pain_timer(delta)

	move_and_slide()

	# Performance monitoring
	if performance_debug:
		var frame_time = (Time.get_ticks_usec() - frame_start_time) / 1000000.0
		_update_performance_metrics(frame_time)

# Combat prediction cache
var _cached_facing_result: bool = false
var _facing_cache_timer: float = 0.0

# -----------------------------------------------------------------------------
func _is_facing_player() -> bool:
	if _facing_cache_timer <= 0.0:
		_facing_cache_timer = 0.1  # Cache for 0.1 seconds

		if not is_instance_valid(_player):
			_cached_facing_result = false
		else:
			var target_dir = _get_cached_direction_to_player()
			var forward_dir = -transform.basis.z.normalized()
			var dot_product = forward_dir.dot(target_dir)
			_cached_facing_result = dot_product > (1.0 - turn_threshold)

	return _cached_facing_result

# Cached rotation values for micro-optimization
var _cached_target_rotation: float = 0.0
var _rotation_cache_timer: float = 0.0

# -----------------------------------------------------------------------------
func _face_player(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	# Cache target rotation calculation
	if _rotation_cache_timer <= 0.0:
		_rotation_cache_timer = 0.1  # Cache for 0.1 seconds
		var target_dir = _get_cached_direction_to_player()
		if target_dir.length_squared() > 0.001:  # Use length_squared for performance
			_cached_target_rotation = atan2(target_dir.x, target_dir.z)

	# Use direct rotation interpolation instead of transform.looking_at
	var current_rotation = rotation.y
	var rotation_diff = _cached_target_rotation - current_rotation

	# Normalize rotation difference to [-PI, PI]
	while rotation_diff > PI:
		rotation_diff -= TAU
	while rotation_diff < -PI:
		rotation_diff += TAU

	# Apply rotation with optimized interpolation
	rotation.y += rotation_diff * turn_speed * delta * 0.5

# -----------------------------------------------------------------------------
func _chase(delta: float) -> void:
	var dir: Vector3
	if _nav:
		_nav_path_cache_timer -= delta

		# Check if we need to recalculate path
		var should_recalc = false
		if _path_timer <= 0.0:
			_path_timer = path_refresh
			should_recalc = true
		elif _last_nav_target.distance_to(_cached_player_position) > _nav_recalc_distance_threshold:
			should_recalc = true

		if should_recalc:
			_nav.target_position = _cached_player_position
			_last_nav_target = _cached_player_position
			_nav_target_reachable = _nav.is_target_reachable()

			if not _nav_target_reachable:
				_unreachable_attempts += 1
				if _unreachable_attempts >= MAX_UNREACHABLE_ATTEMPTS:
					# No nav mesh, disable navigation to avoid expensive queries
					_nav = null
					print_debug("[Knight] Navigation disabled – unreachable target")
			else:
				_unreachable_attempts = 0
				# Cache the full path for multiple frames
				if _nav_path_cache_timer <= 0.0:
					_cached_nav_path = _nav.get_current_navigation_path()
					_nav_path_index = 0
					_nav_path_cache_timer = 0.2  # Cache path for 0.2 seconds

		# Use cached path if available
		if _nav_target_reachable:
			if _cached_nav_path.size() > 0 and _nav_path_index < _cached_nav_path.size():
				var next_point = _cached_nav_path[_nav_path_index]
				var dist_to_point = global_position.distance_to(next_point)
				if dist_to_point < 1.0:  # Close enough to next waypoint
					_nav_path_index += 1
				if _nav_path_index < _cached_nav_path.size():
					dir = (next_point - global_position).normalized()
				else:
					dir = _get_cached_direction_to_player()
			elif not _nav.is_navigation_finished():
				dir = (_nav.get_next_path_position() - global_position).normalized()
			else:
				dir = _get_cached_direction_to_player()
		else:
			dir = _get_cached_direction_to_player()
	else:
		dir = _get_cached_direction_to_player()

	dir.y = 0.0

	# Apply avoidance if we have nearby knights (only in higher LOD levels)
	if _nearby_knights.size() > 0 and _current_lod_level <= 2:
		var avoidance = _get_avoidance_vector()
		# Use faster vector addition without normalization when possible
		dir += avoidance
		if dir.length_squared() > 1.01:  # Only normalize if needed
			dir = dir.normalized()

	# Use optimized velocity interpolation
	var target_velocity = dir * run_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, run_speed * 0.1)
	velocity.z = move_toward(velocity.z, target_velocity.z, run_speed * 0.1)

# Light chase update for when AI is throttled
func _chase_light(delta: float) -> void:
	# Just continue in the last cached direction without expensive calculations
	var dir = _cached_direction
	if dir.length() > 0:
		# DOOM knights maintain better pursuit in light updates
		var lerp_speed = 0.08 if _force_chase else 0.05
		var speed_multiplier = 1.0 if _force_chase else 0.8
		velocity = velocity.lerp(dir * run_speed * speed_multiplier, lerp_speed)

# Attack timing variables
var _attack_recovery_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0

# -----------------------------------------------------------------------------
func _swing_sword() -> void:
	_can_attack = false
	if debug_enabled:
		print("[Knight] Slash!")

	# damage and launch player
	if _player.has_method("take_damage"):
		_player.take_damage(damage)

	# launch player away from knight
	if _player is CharacterBody3D:
		var launch_direction = _get_cached_direction_to_player()

		var vertical_component = sin(deg_to_rad(launch_angle))
		var launch_vector = launch_direction * launch_force
		launch_vector.y = vertical_component * launch_force

		(_player as CharacterBody3D).velocity = launch_vector

	# call player's take_hit function if available
	var player_state = _player.get_node_or_null("PlayerState")
	if player_state and player_state.has_method("take_hit"):
		player_state.take_hit()

	# Use timer-based approach instead of await to avoid creating timer objects
	_attack_recovery_timer = 0.7  # stand still duration
	_attack_cooldown_timer = 0.7 + attack_cooldown  # total time until next attack

# Update attack timers in physics process
func _update_attack_timers(delta: float) -> void:
	if _attack_recovery_timer > 0.0:
		_attack_recovery_timer -= delta
		if _attack_recovery_timer <= 0.0 and _state == State.ATTACKING:
			_state = State.MELEE

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta
		if _attack_cooldown_timer <= 0.0:
			_can_attack = true

# -----------------------------------------------------------------------------
#  External damage interface
# -----------------------------------------------------------------------------
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

var _pain_timer: float = 0.0

func _pain() -> void:
	_state = State.PAIN
	_pain_timer = 0.2  # Pain duration
	if debug_enabled:
		print("[Knight] Pain!")

# Update pain timer in physics process
func _update_pain_timer(delta: float) -> void:
	if _state == State.PAIN and _pain_timer > 0.0:
		_pain_timer -= delta
		if _pain_timer <= 0.0 and _state != State.DEAD:
			_state = State.CHASE

func _die() -> void:
	_state = State.DEAD
	if debug_enabled:
		print("[Knight] Dead.")
	queue_free()

# Exposed for GameMaster – doubles run_speed (or any multiplier)
func boost_speed(multiplier: float):
	run_speed *= multiplier
	_force_chase = true
	if _state != State.DEAD:
		_state = State.CHASE
