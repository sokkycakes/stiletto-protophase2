## Seek and Destroy Action - Hunt down and attack enemies
class_name SeekAndDestroyAction
extends NextBotAction

var target: Node = null
var last_known_position: Vector3 = Vector3.ZERO
var search_timer: float = 0.0
var max_search_time: float = 10.0
var path_follower: NextBotPathFollower = null
var repath_timer: float = 0.0
var repath_interval: float = 1.0

func _init():
	action_name = "SeekAndDestroy"

func on_start(bot_ref, prior_action: NextBotAction) -> ActionResult:
	super.on_start(bot_ref, prior_action)
	
	search_timer = 0.0
	repath_timer = 0.0
	
	# Find initial target
	_find_target(bot)
	
	# Set movement animation
	var body = bot.get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.RUN)
	
	# Initialize path follower
	var locomotion = bot.get_locomotion_interface()
	if locomotion and locomotion.has_method("get_path_follower"):
		path_follower = locomotion.get_path_follower()
	
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Handle child actions first
	var child_result = super.update(bot_ref, delta)
	if child_result.type != ActionResultType.CONTINUE:
		return child_result
	
	search_timer += delta
	repath_timer += delta
	
	# Update target
	_update_target(bot)
	
	# If we have a target, pursue it
	if target and is_instance_valid(target):
		return _pursue_target(bot, delta)
	else:
		# No target, search for one
		return _search_for_target(bot, delta)

func _find_target(bot: INextBot) -> void:
	var vision = bot.get_vision_interface()
	if not vision:
		return
	
	var threat = vision.get_primary_known_threat(false)  # Include non-visible threats
	if threat:
		target = threat.entity
		last_known_position = threat.last_known_position

func _update_target(bot: INextBot) -> void:
	var vision = bot.get_vision_interface()
	if not vision:
		return
	
	# Check if current target is still valid
	if target and not is_instance_valid(target):
		target = null
	
	# Look for better target
	var threat = vision.get_primary_known_threat(true)  # Prefer visible threats
	if threat and threat.entity != target:
		# Switch to more dangerous or closer threat
		if not target or threat.threat_level > 0.7:
			target = threat.entity
			last_known_position = threat.last_known_position

func _pursue_target(bot: INextBot, delta: float) -> ActionResult:
	var vision = bot.get_vision_interface()
	var locomotion = bot.get_locomotion_interface()
	
	if not locomotion:
		return ActionResult.continue_action()
	
	# Update last known position if we can see the target
	if vision and vision.is_able_to_see(target):
		last_known_position = target.global_position
	
	# Check if we're close enough to attack
	var distance = bot.global_position.distance_to(target.global_position)
	if distance < 3.0 and vision and vision.is_able_to_see(target):
		return ActionResult.change_to(AttackAction.new(), "close enough to attack")
	
	# Move towards target
	if repath_timer >= repath_interval:
		repath_timer = 0.0
		locomotion.approach(last_known_position)
	
	# Check if we've been searching too long
	if search_timer > max_search_time:
		return ActionResult.change_to(PatrolAction.new(), "search timeout")
	
	return ActionResult.continue_action()

func _search_for_target(bot: INextBot, delta: float) -> ActionResult:
	# No current target, search for one
	_find_target(bot)
	
	if target:
		return ActionResult.continue_action()  # Found target, continue pursuing
	
	# Move to random search location
	var locomotion = bot.get_locomotion_interface()
	if locomotion and repath_timer >= repath_interval * 2:
		repath_timer = 0.0
		var search_pos = _get_random_search_position(bot)
		locomotion.approach(search_pos)
	
	# Give up after max search time
	if search_timer > max_search_time:
		return ActionResult.change_to(PatrolAction.new(), "no targets found")
	
	return ActionResult.continue_action()

func _get_random_search_position(bot: INextBot) -> Vector3:
	# Generate random position around bot
	var angle = randf() * PI * 2
	var distance = randf_range(5.0, 15.0)
	var offset = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	return bot.global_position + offset

# Event handlers
func on_sight_action(subject: Node) -> ActionResult:
	# Check if this is a better target
	var vision = bot.get_vision_interface()
	if vision:
		var known_entity = vision._get_known_entity(subject)
		if known_entity and known_entity.threat_level > 0.5:
			target = subject
			last_known_position = subject.global_position
			search_timer = 0.0  # Reset search timer
	
	return ActionResult.continue_action()

func on_lost_sight_action(subject: Node) -> ActionResult:
	# If we lost sight of our target, continue to last known position
	if subject == target:
		# Keep pursuing to last known position
		pass
	
	return ActionResult.continue_action()

func on_move_to_failure_action(path, reason) -> ActionResult:
	# If we can't reach the target, try a different approach
	if reason == NextBotPath.FailureType.NO_PATH_EXISTS:
		# Try to find alternative route or give up
		return ActionResult.change_to(PatrolAction.new(), "cannot reach target")
	elif reason == NextBotPath.FailureType.STUCK:
		# Try to unstuck or retreat
		return ActionResult.suspend_for(UnstuckAction.new(), "stuck while pursuing")
	
	return ActionResult.continue_action()

func on_injured_action(damage_info: Dictionary) -> ActionResult:
	# If injured while seeking, become more aggressive or retreat
	if bot.has_method("is_health_low") and bot.is_health_low():
		return ActionResult.change_to(RetreatAction.new(), "injured and low health")
	
	# Otherwise, become more aggressive
	max_search_time *= 1.5
	return ActionResult.continue_action()

# Query overrides
func should_retreat(bot: INextBot) -> bool:
	# Retreat if heavily outnumbered or very low health
	if bot.has_method("is_health_low") and bot.is_health_low():
		var vision = bot.get_vision_interface()
		if vision and vision.get_known_count(-1, true) > 2:  # Multiple visible enemies
			return true
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	# Always attack if we can see the threat and are close
	if threat and bot.global_position.distance_to(threat.global_position) < 5.0:
		var vision = bot.get_vision_interface()
		if vision and vision.is_able_to_see(threat):
			return true
	return false

func should_hurry(bot: INextBot) -> bool:
	# Hurry if we have a visible target
	return target != null and is_instance_valid(target)
