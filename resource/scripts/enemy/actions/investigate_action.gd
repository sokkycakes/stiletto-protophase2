## Investigate Action - Investigate sounds or suspicious activity
class_name InvestigateAction
extends NextBotAction

var target_position: Vector3 = Vector3.ZERO
var target_entity: Node = null
var investigation_radius: float = 2.0
var max_investigation_time: float = 8.0
var investigation_timer: float = 0.0
var search_timer: float = 0.0
var search_interval: float = 1.0

func _init():
	action_name = "Investigate"

func set_target_position(pos: Vector3) -> void:
	target_position = pos
	target_entity = null

func set_target(entity: Node) -> void:
	target_entity = entity
	if entity:
		target_position = entity.global_position

func on_start(bot_ref, prior_action: NextBotAction) -> ActionResult:
	super.on_start(bot_ref, prior_action)
	
	investigation_timer = 0.0
	search_timer = 0.0
	
	# Set walking animation
	var body = bot.get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.WALK)
	
	# Move to investigation point
	var locomotion = bot.get_locomotion_interface()
	if locomotion:
		locomotion.approach(target_position)
	
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Handle child actions first
	var child_result = super.update(bot_ref, delta)
	if child_result.type != ActionResultType.CONTINUE:
		return child_result
	
	investigation_timer += delta
	search_timer += delta
	
	# Check for threats while investigating
	var vision = bot.get_vision_interface()
	if vision:
		var threat = vision.get_primary_known_threat(true)
		if threat:
			return ActionResult.change_to(SeekAndDestroyAction.new(), "threat found during investigation")
	
	# Check if we've reached the investigation point
	var distance = bot.global_position.distance_to(target_position)
	if distance < investigation_radius:
		return _investigate_area(bot, delta)
	
	# Check timeout
	if investigation_timer > max_investigation_time:
		return ActionResult.done("investigation timeout")
	
	return ActionResult.continue_action()

func _investigate_area(bot: INextBot, delta: float) -> ActionResult:
	# We've reached the investigation point, now search the area
	var body = bot.get_body_interface()
	
	# Look around periodically
	if search_timer >= search_interval:
		search_timer = 0.0
		_look_around(bot)
	
	# Search for clues or entities
	var found_something = _search_for_clues(bot)
	if found_something:
		return ActionResult.done("investigation complete - found something")
	
	# Continue investigating for a bit longer
	if investigation_timer > max_investigation_time * 0.7:
		return ActionResult.done("investigation complete - nothing found")
	
	return ActionResult.continue_action()

func _look_around(bot: INextBot) -> void:
	var body = bot.get_body_interface()
	if body:
		# Look in a systematic pattern
		var angles = [0, 90, 180, 270]  # Look in cardinal directions
		var current_angle = angles[int(investigation_timer) % angles.size()]
		var look_direction = Vector3(cos(deg_to_rad(current_angle)), 0, sin(deg_to_rad(current_angle)))
		var look_position = bot.global_position + look_direction * 5.0
		body.aim_head_towards_pos(look_position, search_interval * 0.8)

func _search_for_clues(bot: INextBot) -> bool:
	# Look for interesting entities or clues in the area
	var space_state = bot.get_world_3d().direct_space_state
	var bot_pos = bot.global_position
	
	# Check for items or entities of interest
	var items = bot.get_tree().get_nodes_in_group("items")
	for item in items:
		if bot_pos.distance_to(item.global_position) < investigation_radius * 2:
			# Found something interesting
			target_entity = item
			return true
	
	# Check for other entities
	var entities = bot.get_tree().get_nodes_in_group("entities")
	for entity in entities:
		if entity != bot and bot_pos.distance_to(entity.global_position) < investigation_radius * 2:
			# Found an entity
			target_entity = entity
			return true
	
	return false

# Event handlers
func on_sight_action(subject: Node) -> ActionResult:
	# If we see something during investigation, check if it's relevant
	var vision = bot.get_vision_interface()
	if vision:
		var known_entity = vision._get_known_entity(subject)
		if known_entity and known_entity.threat_level > 0.5:
			return ActionResult.change_to(SeekAndDestroyAction.new(), "threat spotted during investigation")
		elif known_entity and known_entity.threat_level > 0.2:
			# Minor interest, continue investigating but keep an eye on it
			target_entity = subject
	
	return ActionResult.continue_action()

func on_sound_action(source: Node, pos: Vector3, sound_data: Dictionary) -> ActionResult:
	# If we hear another sound while investigating, check if it's more important
	var distance_to_current = bot.global_position.distance_to(target_position)
	var distance_to_new = bot.global_position.distance_to(pos)
	
	# If the new sound is much closer, investigate it instead
	if distance_to_new < distance_to_current * 0.5:
		target_position = pos
		target_entity = source
		
		var locomotion = bot.get_locomotion_interface()
		if locomotion:
			locomotion.approach(target_position)
	
	return ActionResult.continue_action()

func on_move_to_failure_action(path, reason) -> ActionResult:
	# If we can't reach the investigation point, try to get as close as possible
	if reason == NextBotPath.FailureType.NO_PATH_EXISTS:
		# Find alternative position nearby
		var alternative_pos = _find_alternative_position(bot)
		if alternative_pos != Vector3.ZERO:
			target_position = alternative_pos
			var locomotion = bot.get_locomotion_interface()
			if locomotion:
				locomotion.approach(target_position)
			return ActionResult.continue_action()
		else:
			return ActionResult.done("cannot reach investigation point")
	elif reason == NextBotPath.FailureType.STUCK:
		return ActionResult.suspend_for(UnstuckAction.new(), "stuck during investigation")
	
	return ActionResult.continue_action()

func _find_alternative_position(bot: INextBot) -> Vector3:
	# Try to find a position near the target that we can reach
	var bot_pos = bot.global_position
	var directions = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	
	for direction in directions:
		var test_pos = target_position + direction * 3.0
		# Simple check - in a real implementation you'd use proper pathfinding
		var space_state = bot.get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(bot_pos, test_pos)
		var result = space_state.intersect_ray(query)
		
		if result.is_empty():
			return test_pos
	
	return Vector3.ZERO

# Query overrides
func should_retreat(bot: INextBot) -> bool:
	# Retreat if we encounter threats during investigation
	var vision = bot.get_vision_interface()
	if vision:
		var threat = vision.get_primary_known_threat(true)
		if threat and bot.has_method("is_health_low") and bot.is_health_low():
			return true
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	# Attack if threatened directly during investigation
	if threat and bot.global_position.distance_to(threat.global_position) < 4.0:
		return true
	return false

func should_hurry(bot: INextBot) -> bool:
	# Don't hurry during investigation unless threatened
	var vision = bot.get_vision_interface()
	if vision:
		var threat = vision.get_primary_known_threat(true)
		return threat != null
	return false
