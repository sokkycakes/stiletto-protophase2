## Retreat Action - Flee from threats to safety
class_name RetreatAction
extends NextBotAction

var retreat_distance: float = 15.0
var retreat_position: Vector3 = Vector3.ZERO
var retreat_timer: float = 0.0
var max_retreat_time: float = 10.0
var safety_check_timer: float = 0.0
var safety_check_interval: float = 1.0

func _init():
	action_name = "Retreat"

func on_start(bot_ref, prior_action: NextBotAction) -> ActionResult:
	super.on_start(bot_ref, prior_action)
	
	retreat_timer = 0.0
	safety_check_timer = 0.0
	
	# Find retreat position
	_find_retreat_position(bot)
	
	# Set running animation
	var body = bot.get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.RUN)
	
	# Start retreating
	var locomotion = bot.get_locomotion_interface()
	if locomotion:
		locomotion.approach(retreat_position)
	
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Handle child actions first
	var child_result = super.update(bot_ref, delta)
	if child_result.type != ActionResultType.CONTINUE:
		return child_result
	
	retreat_timer += delta
	safety_check_timer += delta
	
	# Periodically check if we're safe
	if safety_check_timer >= safety_check_interval:
		safety_check_timer = 0.0
		
		if _is_safe(bot):
			return ActionResult.change_to(IdleAction.new(), "reached safety")
		else:
			# Update retreat position if needed
			_update_retreat_position(bot)
	
	# Check if we've been retreating too long
	if retreat_timer > max_retreat_time:
		return ActionResult.change_to(IdleAction.new(), "retreat timeout")
	
	# Check if we've reached retreat position
	var distance = bot.global_position.distance_to(retreat_position)
	if distance < 2.0:
		if _is_safe(bot):
			return ActionResult.change_to(IdleAction.new(), "reached retreat position")
		else:
			# Find new retreat position
			_find_retreat_position(bot)
			var locomotion = bot.get_locomotion_interface()
			if locomotion:
				locomotion.approach(retreat_position)
	
	return ActionResult.continue_action()

func _find_retreat_position(bot: INextBot) -> void:
	var vision = bot.get_vision_interface()
	var bot_pos = bot.global_position
	
	# Find direction away from threats
	var threat_direction = Vector3.ZERO
	var threat_count = 0
	
	if vision:
		var known_entities: Array[IVision.KnownEntity] = []
		vision.collect_known_entities(known_entities)
		
		for known_entity in known_entities:
			if known_entity.threat_level > 0.3:
				var to_threat = (known_entity.last_known_position - bot_pos).normalized()
				threat_direction += to_threat
				threat_count += 1
	
	# Calculate retreat direction
	var retreat_direction: Vector3
	if threat_count > 0:
		# Move away from average threat direction
		retreat_direction = -(threat_direction / threat_count).normalized()
	else:
		# No specific threats, move in random direction
		var angle = randf() * PI * 2
		retreat_direction = Vector3(cos(angle), 0, sin(angle))
	
	# Find retreat position
	retreat_position = bot_pos + retreat_direction * retreat_distance
	
	# Try to find cover or safe areas
	_find_cover_position(bot)

func _find_cover_position(bot: INextBot) -> void:
	# Look for cover points in the scene
	var cover_nodes = bot.get_tree().get_nodes_in_group("cover_points")
	var bot_pos = bot.global_position
	var best_cover: Node = null
	var best_distance = INF
	
	for cover in cover_nodes:
		var distance = bot_pos.distance_to(cover.global_position)
		if distance < best_distance and distance > 5.0:  # Not too close
			# Check if this cover is away from threats
			if _is_position_safe(bot, cover.global_position):
				best_distance = distance
				best_cover = cover
	
	if best_cover:
		retreat_position = best_cover.global_position

func _update_retreat_position(bot: INextBot) -> void:
	# If current retreat position is no longer safe, find a new one
	if not _is_position_safe(bot, retreat_position):
		_find_retreat_position(bot)
		
		var locomotion = bot.get_locomotion_interface()
		if locomotion:
			locomotion.approach(retreat_position)

func _is_safe(bot: INextBot) -> bool:
	var vision = bot.get_vision_interface()
	if not vision:
		return true
	
	# Check if any threats are visible and close
	var threat = vision.get_primary_known_threat(true)
	if threat:
		var distance = bot.global_position.distance_to(threat.last_known_position)
		return distance > retreat_distance * 0.8
	
	return true

func _is_position_safe(bot: INextBot, position: Vector3) -> bool:
	var vision = bot.get_vision_interface()
	if not vision:
		return true
	
	# Check if position is far enough from known threats
	var known_entities: Array[IVision.KnownEntity] = []
	vision.collect_known_entities(known_entities)
	
	for known_entity in known_entities:
		if known_entity.threat_level > 0.3:
			var distance = position.distance_to(known_entity.last_known_position)
			if distance < retreat_distance * 0.5:
				return false
	
	return true

# Event handlers
func on_sight_action(subject: Node) -> ActionResult:
	# If we see a new threat while retreating, update retreat direction
	var vision = bot.get_vision_interface()
	if vision:
		var known_entity = vision._get_known_entity(subject)
		if known_entity and known_entity.threat_level > 0.5:
			_update_retreat_position(bot)
	
	return ActionResult.continue_action()

func on_injured_action(damage_info: Dictionary) -> ActionResult:
	# If injured while retreating, find new retreat position urgently
	_find_retreat_position(bot)
	
	var locomotion = bot.get_locomotion_interface()
	if locomotion:
		locomotion.approach(retreat_position)
	
	# Increase retreat distance
	retreat_distance *= 1.5
	
	return ActionResult.continue_action()

func on_move_to_failure_action(path: NextBotPath, reason: NextBotPath.FailureType) -> ActionResult:
	# If we can't reach retreat position, find alternative
	if reason == NextBotPath.FailureType.NO_PATH_EXISTS:
		_find_retreat_position(bot)
		var locomotion = bot.get_locomotion_interface()
		if locomotion:
			locomotion.approach(retreat_position)
	elif reason == NextBotPath.FailureType.STUCK:
		# Try to unstuck while retreating
		return ActionResult.suspend_for(UnstuckAction.new(), "stuck while retreating")
	
	return ActionResult.continue_action()

# Query overrides
func should_retreat(bot: INextBot) -> bool:
	# Always continue retreating until safe
	return not _is_safe(bot)

func should_attack(bot: INextBot, threat: Node) -> bool:
	# Only attack during retreat if cornered
	if threat and bot.global_position.distance_to(threat.global_position) < 2.0:
		return true  # Fight back if cornered
	return false

func should_hurry(bot: INextBot) -> bool:
	# Always hurry when retreating
	return true

func is_hindrance(bot: INextBot, blocker: Node) -> bool:
	# Everything is a hindrance when retreating
	return blocker != bot
