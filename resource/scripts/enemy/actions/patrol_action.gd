## Patrol Action - Move between waypoints or patrol an area
class_name PatrolAction
extends NextBotAction

var patrol_points: Array[Vector3] = []
var current_patrol_index: int = 0
var wait_timer: float = 0.0
var wait_time: float = 2.0
var is_waiting: bool = false
var patrol_radius: float = 10.0

func _init():
	action_name = "Patrol"

func on_start(bot_ref, prior_action: NextBotAction) -> ActionResult:
	super.on_start(bot_ref, prior_action)
	
	wait_timer = 0.0
	is_waiting = false
	
	# Set up patrol points
	_setup_patrol_points(bot)
	
	# Set walking animation
	var body = bot.get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.WALK)
	
	# Start moving to first patrol point
	_move_to_next_patrol_point(bot)
	
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Handle child actions first
	var child_result = super.update(bot_ref, delta)
	if child_result.type != ActionResultType.CONTINUE:
		return child_result
	
	# Check for threats while patrolling
	var vision = bot.get_vision_interface()
	if vision:
		var threat = vision.get_primary_known_threat(true)
		if threat:
			return ActionResult.change_to(SeekAndDestroyAction.new(), "threat detected while patrolling")
	
	# Handle waiting at patrol points
	if is_waiting:
		wait_timer += delta
		if wait_timer >= wait_time:
			is_waiting = false
			wait_timer = 0.0
			_move_to_next_patrol_point(bot)
		return ActionResult.continue_action()
	
	# Check if we've reached current patrol point
	if patrol_points.size() > 0:
		var target_point = patrol_points[current_patrol_index]
		var distance = bot.global_position.distance_to(target_point)
		
		if distance < 2.0:  # Reached patrol point
			is_waiting = true
			wait_timer = 0.0
			
			# Look around while waiting
			_look_around(bot)
	
	return ActionResult.continue_action()

func _setup_patrol_points(bot: INextBot) -> void:
	# Try to find patrol points in the scene
	var patrol_nodes = bot.get_tree().get_nodes_in_group("patrol_points")
	
	if patrol_nodes.size() > 0:
		# Use predefined patrol points
		for node in patrol_nodes:
			patrol_points.append(node.global_position)
	else:
		# Generate random patrol points around starting position
		var start_pos = bot.global_position
		var num_points = 4
		
		for i in range(num_points):
			var angle = (float(i) / float(num_points)) * PI * 2
			var offset = Vector3(cos(angle) * patrol_radius, 0, sin(angle) * patrol_radius)
			patrol_points.append(start_pos + offset)
	
	# Ensure we have at least one patrol point
	if patrol_points.is_empty():
		patrol_points.append(bot.global_position)

func _move_to_next_patrol_point(bot: INextBot) -> void:
	if patrol_points.is_empty():
		return
	
	# Move to next patrol point
	current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
	var target_point = patrol_points[current_patrol_index]
	
	var locomotion = bot.get_locomotion_interface()
	if locomotion:
		locomotion.approach(target_point)

func _look_around(bot: INextBot) -> void:
	# Look in a random direction while waiting
	var body = bot.get_body_interface()
	if body:
		var random_angle = randf() * PI * 2
		var look_direction = Vector3(cos(random_angle), 0, sin(random_angle))
		var look_position = bot.global_position + look_direction * 5.0
		body.aim_head_towards_pos(look_position, wait_time * 0.5)

# Event handlers
func on_sight_action(subject: Node) -> ActionResult:
	# If we see a threat, investigate or attack
	var vision = bot.get_vision_interface()
	if vision:
		var known_entity = vision._get_known_entity(subject)
		if known_entity and known_entity.threat_level > 0.5:
			return ActionResult.change_to(SeekAndDestroyAction.new(), "threat spotted during patrol")
		elif known_entity and known_entity.threat_level > 0.2:
			# Minor threat, investigate
			var investigate_action = InvestigateAction.new()
			investigate_action.set_target(subject)
			return ActionResult.suspend_for(investigate_action, "investigating during patrol")
	
	return ActionResult.continue_action()

func on_sound_action(source: Node, pos: Vector3, sound_data: Dictionary) -> ActionResult:
	# Investigate interesting sounds
	if source != bot and pos.distance_to(bot.get_position()) < 15.0:
		var investigate_action = InvestigateAction.new()
		investigate_action.set_target_position(pos)
		return ActionResult.suspend_for(investigate_action, "investigating sound during patrol")
	
	return ActionResult.continue_action()

func on_move_to_failure_action(path: NextBotPath, reason: NextBotPath.FailureType) -> ActionResult:
	# If we can't reach a patrol point, skip to the next one
	if reason == NextBotPath.FailureType.NO_PATH_EXISTS:
		_move_to_next_patrol_point(bot)
	elif reason == NextBotPath.FailureType.STUCK:
		# Try to unstuck
		return ActionResult.suspend_for(UnstuckAction.new(), "stuck during patrol")
	
	return ActionResult.continue_action()

# Query overrides
func should_retreat(bot: INextBot) -> bool:
	# Patrol bots should retreat if they encounter superior threats
	if bot.has_method("is_health_low") and bot.is_health_low():
		var vision = bot.get_vision_interface()
		if vision and vision.get_primary_known_threat(true):
			return true
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	# Attack if threat is close and we can handle it
	if threat and bot.global_position.distance_to(threat.global_position) < 5.0:
		return not (bot.has_method("is_health_low") and bot.is_health_low())
	return false

func should_hurry(bot: INextBot) -> bool:
	# Don't hurry during normal patrol
	return false
