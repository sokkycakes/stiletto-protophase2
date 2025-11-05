## Enhanced Intention Component Implementation

class_name EnhancedIntentionComponent
extends Node

# Load the base interface
const IIntentionInterface = preload("res://scripts/enemy/interfaces/intention_interface.gd")

# Implement IIntention interface manually
var current_action: NextBotAction = null
var action_stack: Array[NextBotAction] = []
var is_intention_active: bool = true

# Component properties (from INextBotComponent)
var bot
var component_name: String = "EnhancedIntention"
var is_initialized: bool = false
var last_update_time: float = 0.0

# Enhanced decision making
var decision_timer: float = 0.0
var decision_interval: float = 0.5  # Make decisions twice per second
var last_threat_assessment: float = 0.0
var threat_assessment_interval: float = 1.0

# Behavior state
var behavior_history: Array[String] = []
var max_history_size: int = 10

# Component lifecycle methods (implementing INextBotComponent interface)
func initialize(bot_ref) -> void:
	bot = bot_ref
	is_initialized = true
	on_initialize()

func reset() -> void:
	on_reset()

func update(delta: float) -> void:
	if not is_initialized:
		return

	last_update_time = Time.get_unix_time_from_system()
	on_update(delta)

func upkeep() -> void:
	on_upkeep()

func on_initialize() -> void:
	# Enhanced initialization
	decision_timer = 0.0
	last_threat_assessment = 0.0

func on_reset() -> void:
	# Clear all actions
	if current_action:
		current_action.on_end(bot, null)
	current_action = null
	action_stack.clear()

	# Restart with initial action
	var initial_action = get_initial_action()
	if initial_action:
		start_action(initial_action)

func on_upkeep() -> void:
	pass

# IIntention interface methods
func get_initial_action() -> NextBotAction:
	# Start with enhanced idle that can transition to patrol
	return IdleAction.new()

func start_action(action: NextBotAction) -> void:
	if current_action:
		current_action.on_end(bot, action)

	current_action = action
	if action:
		action.on_start(bot, null)

func change_action(action: NextBotAction) -> void:
	start_action(action)

func suspend_for(action: NextBotAction) -> void:
	if current_action:
		action_stack.push_back(current_action)
		current_action.on_suspend(bot, action)

	current_action = action
	if action:
		action.on_start(bot, null)

func resume_action() -> void:
	if action_stack.is_empty():
		return

	var interrupted_action = current_action
	if interrupted_action:
		interrupted_action.on_end(bot, null)

	current_action = action_stack.pop_back()
	if current_action:
		current_action.on_resume(bot, interrupted_action)

func get_current_action() -> NextBotAction:
	return current_action

func is_action_done() -> bool:
	return current_action == null

func on_update(delta: float) -> void:
	if not is_intention_active or not current_action:
		return

	# Update current action
	var result = current_action.update(bot, delta)

	# Handle action result
	_handle_action_result(result)

	# Update decision making
	decision_timer += delta
	last_threat_assessment += delta

	# Periodic decision making
	if decision_timer >= decision_interval:
		decision_timer = 0.0
		_make_tactical_decision()

	# Periodic threat assessment
	if last_threat_assessment >= threat_assessment_interval:
		last_threat_assessment = 0.0
		_assess_threats()

# Action result handling
func _handle_action_result(result) -> void:
	if not result:
		return

	match result.type:
		NextBotAction.ActionResultType.CONTINUE:
			# Keep running current action
			pass

		NextBotAction.ActionResultType.CHANGE_TO:
			# Change to new action
			if result.action:
				change_action(result.action)

		NextBotAction.ActionResultType.SUSPEND_FOR:
			# Suspend current action for new one
			if result.action:
				suspend_for(result.action)

		NextBotAction.ActionResultType.DONE:
			# Current action is complete
			var completed_action = current_action
			current_action = null

			# Handle what to do next
			if result.reason == "interrupted":
				# Resume previous action if available
				resume_action()
			elif result.action:
				# Start specified next action
				start_action(result.action)
			else:
				# No next action specified, try to resume or get initial
				if not action_stack.is_empty():
					resume_action()
				else:
					var initial_action = get_initial_action()
					if initial_action:
						start_action(initial_action)
	
	# Parent class (Node) doesn't have on_update method, so no super call needed

# Enhanced threat selection
func select_more_dangerous_threat(subject1: IVision.KnownEntity, subject2: IVision.KnownEntity) -> IVision.KnownEntity:
	if not subject1:
		return subject2
	if not subject2:
		return subject1
	
	# Enhanced threat comparison
	var threat1_score = _calculate_threat_score(subject1)
	var threat2_score = _calculate_threat_score(subject2)
	
	return subject1 if threat1_score > threat2_score else subject2

func _calculate_threat_score(threat: IVision.KnownEntity) -> float:
	var score = threat.threat_level
	var eye_pos = bot.get_body_interface().get_eye_position()
	var distance = eye_pos.distance_to(threat.last_known_position)
	
	# Closer threats are more dangerous
	score += (20.0 - distance) / 20.0
	
	# Recently seen threats are more dangerous
	var time_since_seen = Time.get_unix_time_from_system() - threat.last_seen_time
	score += max(0.0, (5.0 - time_since_seen) / 5.0)
	
	# Visible threats are more dangerous
	if threat.is_visible_now:
		score += 0.5
	
	# Check if threat is armed or hostile
	if threat.entity.has_method("get_weapon") and threat.entity.get_weapon():
		score += 0.3
	
	if threat.entity.has_method("is_hostile_to") and threat.entity.is_hostile_to(bot):
		score += 0.4
	
	return score

# Enhanced decision making
func _make_tactical_decision() -> void:
	if not current_action:
		return
	
	var vision = bot.get_vision_interface()
	if not vision:
		return
	
	# Assess current situation
	var threat = vision.get_primary_known_threat(true)
	var health_percentage = _get_health_percentage()
	var visible_enemies = vision.get_known_count(-1, true)
	
	# Make tactical decisions based on situation
	if threat and health_percentage < 0.3:
		# Low health with threat - consider retreating
		if not current_action.is_named("Retreat"):
			var retreat_action = RetreatAction.new()
			change_action(retreat_action)
			_add_to_behavior_history("Retreat")
	elif threat and visible_enemies > 2 and health_percentage < 0.6:
		# Outnumbered - consider tactical retreat
		if not current_action.is_named("Retreat"):
			var retreat_action = RetreatAction.new()
			change_action(retreat_action)
			_add_to_behavior_history("TacticalRetreat")
	elif threat:
		# Engage threat
		if not current_action.is_named("SeekAndDestroy") and not current_action.is_named("Attack"):
			var seek_action = SeekAndDestroyAction.new()
			change_action(seek_action)
			_add_to_behavior_history("Engage")
	elif current_action.is_named("Idle") and randf() < 0.1:
		# Occasionally patrol when idle
		var patrol_action = PatrolAction.new()
		change_action(patrol_action)
		_add_to_behavior_history("Patrol")

func _assess_threats() -> void:
	var vision = bot.get_vision_interface()
	if not vision:
		return
	
	# Update threat levels for all known entities
	var known_entities: Array[IVision.KnownEntity] = []
	vision.collect_known_entities(known_entities)
	
	for known_entity in known_entities:
		if is_instance_valid(known_entity.entity):
			known_entity.threat_level = _calculate_enhanced_threat_level(known_entity.entity)

func _calculate_enhanced_threat_level(entity: Node) -> float:
	var threat_level = 0.0
	var distance = bot.global_position.distance_to(entity.global_position)
	
	# Base threat based on proximity
	threat_level += max(0.0, (20.0 - distance) / 20.0) * 0.3
	
	# Team-based threat
	if entity.has_method("get_team") and bot.has_method("get_team"):
		if entity.get_team() != bot.get_team():
			threat_level += 0.4
	
	# Weapon-based threat
	if entity.has_method("get_weapon") and entity.get_weapon():
		threat_level += 0.3
	
	# Health-based threat (healthy enemies are more dangerous)
	if entity.has_method("get_health_percentage"):
		threat_level += entity.get_health_percentage() * 0.2
	
	# Behavioral threat (attacking entities are more dangerous)
	if entity.has_method("get_current_action"):
		var action = entity.get_current_action()
		if action and action.is_named("Attack"):
			threat_level += 0.3
	
	# Line of sight threat
	var vision = bot.get_vision_interface()
	if vision and vision.is_able_to_see(entity):
		threat_level += 0.2
	
	return clamp(threat_level, 0.0, 1.0)

# Enhanced query methods
func should_pickup(bot: INextBot, item: Node) -> bool:
	# Enhanced pickup logic
	if not item:
		return false
	
	# Don't pickup during combat
	var vision = bot.get_vision_interface()
	if vision and vision.get_primary_known_threat(true):
		return false
	
	# Check if item is useful
	if item.has_method("get_item_type"):
		var item_type = item.get_item_type()
		match item_type:
			"health":
				return _get_health_percentage() < 0.8
			"ammo":
				return true  # Always useful
			"weapon":
				return not bot.has_method("get_weapon") or not bot.get_weapon()
	
	return false

func should_hurry(bot: INextBot) -> bool:
	# Enhanced hurry logic
	var vision = bot.get_vision_interface()
	if vision:
		var threat = vision.get_primary_known_threat(true)
		if threat:
			var distance = bot.global_position.distance_to(threat.last_known_position)
			return distance < 10.0  # Hurry if threat is close
	
	# Hurry if health is low
	return _get_health_percentage() < 0.3

func should_retreat(bot: INextBot) -> bool:
	var health_percentage = _get_health_percentage()
	var vision = bot.get_vision_interface()
	
	# Always retreat if very low health
	if health_percentage < 0.2:
		return true
	
	if vision:
		var visible_enemies = vision.get_known_count(-1, true)
		var threat = vision.get_primary_known_threat(true)
		
		# Retreat if outnumbered and low health
		if visible_enemies > 2 and health_percentage < 0.5:
			return true
		
		# Retreat if facing very dangerous threat while weak
		if threat and threat.threat_level > 0.8 and health_percentage < 0.4:
			return true
	
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	if not threat:
		return false
	
	var distance = bot.global_position.distance_to(threat.global_position)
	var health_percentage = _get_health_percentage()
	
	# Don't attack if too weak unless cornered
	if health_percentage < 0.2 and distance > 3.0:
		return false
	
	# Attack if threat is close
	if distance < 5.0:
		return true
	
	# Attack if we have good health and can see the threat
	var vision = bot.get_vision_interface()
	if vision and vision.is_able_to_see(threat) and health_percentage > 0.4:
		return true
	
	return false

# Utility methods
func _get_health_percentage() -> float:
	if bot.has_method("get_health") and bot.has_method("get_max_health"):
		return bot.get_health() / bot.get_max_health()
	return 1.0

func _add_to_behavior_history(behavior_name: String) -> void:
	behavior_history.append(behavior_name)
	if behavior_history.size() > max_history_size:
		behavior_history.pop_front()

func get_behavior_history() -> Array[String]:
	return behavior_history.duplicate()

func get_recent_behavior_count(behavior_name: String, recent_count: int = 5) -> int:
	var count = 0
	var start_index = max(0, behavior_history.size() - recent_count)
	
	for i in range(start_index, behavior_history.size()):
		if behavior_history[i] == behavior_name:
			count += 1
	
	return count
