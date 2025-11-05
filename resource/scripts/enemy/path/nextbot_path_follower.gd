## NextBot Path Follower - Handles following a computed path
## Based on Source SDK PathFollower
class_name NextBotPathFollower
extends RefCounted

# Path following properties
var path: NextBotPath = null
var bot: INextBot = null
var goal_tolerance: float = 0.5
var min_look_ahead_distance: float = 1.0

# Following state
var is_following: bool = false
var last_progress: float = 0.0
var stuck_timer: float = 0.0
var stuck_threshold: float = 2.0

# Signals (would be implemented as callbacks in actual usage)
signal path_complete
signal path_failed(reason: NextBotPath.FailureType)

func _init(owner_bot: INextBot):
	bot = owner_bot

# Path following control
func set_path(new_path: NextBotPath) -> void:
	path = new_path
	if path and path.is_valid():
		path.move_cursor_to_start()
		is_following = true
		last_progress = 0.0
		stuck_timer = 0.0
	else:
		is_following = false

func get_path() -> NextBotPath:
	return path

func is_path_valid() -> bool:
	return path != null and path.is_valid()

func start_following() -> void:
	if is_path_valid():
		is_following = true
		path.move_cursor_to_start()

func stop_following() -> void:
	is_following = false

func is_following_path() -> bool:
	return is_following and is_path_valid()

# Update path following
func update(delta: float) -> void:
	if not is_following_path():
		return
	
	# Update path age
	path.update(delta)
	
	# Check if we've reached the goal
	if _is_at_goal():
		_on_path_complete()
		return
	
	# Update cursor position to closest point on path
	var bot_pos = bot.global_position
	path.move_cursor_to_closest_position(bot_pos)
	
	# Get movement goal
	var movement_goal = _compute_movement_goal()
	
	# Move towards goal
	if movement_goal != Vector3.ZERO:
		var locomotion = bot.get_locomotion_interface()
		if locomotion:
			locomotion.approach(movement_goal)
	
	# Check for stuck condition
	_check_stuck(delta)

# Compute where the bot should move next
func _compute_movement_goal() -> Vector3:
	if not is_path_valid():
		return Vector3.ZERO
	
	var bot_pos = bot.global_position
	var cursor_data = path.get_cursor_data()
	
	# Look ahead on the path
	var look_ahead_distance = _compute_look_ahead_distance()
	var target_distance = path.get_cursor_position() + look_ahead_distance
	
	# Clamp to path length
	target_distance = min(target_distance, path.get_length())
	
	# Get position at target distance
	var goal_pos = path.get_position_at_distance(target_distance)
	
	# Adjust goal height to ground level if needed
	goal_pos = _adjust_goal_to_ground(goal_pos)
	
	return goal_pos

func _compute_look_ahead_distance() -> float:
	var locomotion = bot.get_locomotion_interface()
	if not locomotion:
		return min_look_ahead_distance
	
	var speed = locomotion.get_speed()
	var base_distance = min_look_ahead_distance
	
	# Scale look-ahead with speed
	var speed_factor = speed / locomotion.get_desired_speed()
	return base_distance * (1.0 + speed_factor)

func _adjust_goal_to_ground(goal_pos: Vector3) -> Vector3:
	# Simple ground adjustment - in practice you'd use proper ground detection
	var space_state = bot.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		goal_pos + Vector3.UP * 2.0,
		goal_pos + Vector3.DOWN * 10.0
	)
	
	var result = space_state.intersect_ray(query)
	if not result.is_empty():
		return result.position
	
	return goal_pos

# Goal checking
func _is_at_goal() -> bool:
	if not is_path_valid():
		return false
	
	var bot_pos = bot.global_position
	var goal_pos = path.get_end_position()
	var distance = bot_pos.distance_to(goal_pos)
	
	return distance <= goal_tolerance

func get_distance_to_goal() -> float:
	if not is_path_valid():
		return INF
	
	var bot_pos = bot.global_position
	var goal_pos = path.get_end_position()
	return bot_pos.distance_to(goal_pos)

# Stuck detection
func _check_stuck(delta: float) -> void:
	var current_progress = path.get_cursor_position()
	var progress_delta = current_progress - last_progress
	
	# Check if we're making progress
	if progress_delta < 0.1:  # Very little progress
		stuck_timer += delta
		if stuck_timer > stuck_threshold:
			_on_path_failed(NextBotPath.FailureType.STUCK)
			return
	else:
		stuck_timer = 0.0
	
	last_progress = current_progress

# Path completion/failure handling
func _on_path_complete() -> void:
	is_following = false
	path_complete.emit()
	
	# Notify bot
	if bot:
		bot.on_move_to_success(path)

func _on_path_failed(reason: NextBotPath.FailureType) -> void:
	is_following = false
	path_failed.emit(reason)
	
	# Notify bot
	if bot:
		bot.on_move_to_failure(path, reason)

# Utility methods
func get_goal_tolerance() -> float:
	return goal_tolerance

func set_goal_tolerance(tolerance: float) -> void:
	goal_tolerance = max(0.1, tolerance)

func get_min_look_ahead_distance() -> float:
	return min_look_ahead_distance

func set_min_look_ahead_distance(distance: float) -> void:
	min_look_ahead_distance = max(0.1, distance)

func get_current_goal() -> Vector3:
	if not is_path_valid():
		return Vector3.ZERO
	return _compute_movement_goal()

func get_progress() -> float:
	if not is_path_valid():
		return 0.0
	return path.get_cursor_position() / path.get_length()

func get_remaining_distance() -> float:
	if not is_path_valid():
		return 0.0
	return path.get_length() - path.get_cursor_position()

# Debug
func draw_debug() -> void:
	if not is_path_valid():
		return
	
	# Draw the path
	path.draw_debug(bot)
	
	# Draw current goal
	var goal = _compute_movement_goal()
	if goal != Vector3.ZERO:
		_debug_draw_sphere(goal, 0.3, Color.GREEN)
	
	# Draw goal tolerance
	var end_goal = path.get_end_position()
	_debug_draw_sphere(end_goal, goal_tolerance, Color.BLUE, true)

func _debug_draw_sphere(pos: Vector3, radius: float, color: Color, wireframe: bool = false) -> void:
	# Placeholder for debug sphere drawing
	pass
