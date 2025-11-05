## NextBot Intention Interface
## Based on Source SDK NextBotIntentionInterface.h
class_name IIntention
extends INextBotComponent

# Current behavior/action
var current_action: NextBotAction = null
var action_stack: Array[NextBotAction] = []

# Intention state
var is_intention_active: bool = true

# Abstract methods - must be implemented by derived classes
func select_more_dangerous_threat(subject1: IVision.KnownEntity, subject2: IVision.KnownEntity) -> IVision.KnownEntity:
	# Default implementation - override in derived classes
	if not subject1:
		return subject2
	if not subject2:
		return subject1
		
	# Simple threat comparison based on distance
	var eye_pos = bot.get_body_interface().get_eye_position()
	var dist1 = eye_pos.distance_to(subject1.last_known_position)
	var dist2 = eye_pos.distance_to(subject2.last_known_position)
	
	return subject1 if dist1 < dist2 else subject2

# Action management
func get_initial_action() -> NextBotAction:
	# Must be implemented by derived classes
	assert(false, "get_initial_action() must be implemented by derived class")
	return null

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

# Component lifecycle
func _init() -> void:
	component_name = "Intention"

func on_initialize() -> void:
	# Start with initial action
	var initial_action = get_initial_action()
	if initial_action:
		start_action(initial_action)

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

func on_update(delta: float) -> void:
	if not is_intention_active or not current_action:
		return
	
	# Update current action
	var result = current_action.update(bot, delta)
	
	# Handle action result
	_handle_action_result(result)

# Action result handling
func _handle_action_result(result: NextBotAction.ActionResult) -> void:
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

# Event propagation to current action
func get_first_contained_responder() -> INextBotEventResponder:
	return current_action

func get_next_contained_responder(current: INextBotEventResponder) -> INextBotEventResponder:
	# Only one responder (current action)
	return null

# Query methods for actions to use
func should_pickup(item: Node) -> bool:
	# Default implementation - can be overridden
	return false

func should_hurry() -> bool:
	# Default implementation - can be overridden
	return false

func should_retreat() -> bool:
	# Default implementation - can be overridden
	var vision = bot.get_vision_interface()
	if not vision:
		return false
		
	var threat = vision.get_primary_known_threat(true)
	if not threat:
		return false
	
	# Simple retreat logic - retreat if health is low and we have a visible threat
	var body = bot.get_body_interface()
	if body and "health" in bot and bot.health < 30.0:
		return true
		
	return false

func should_attack() -> bool:
	# Default implementation - can be overridden
	var vision = bot.get_vision_interface()
	if not vision:
		return false
		
	var threat = vision.get_primary_known_threat(true)
	return threat != null

func is_hindrance(blocker: Node) -> bool:
	# Default implementation - can be overridden
	return blocker != null and blocker != bot

# Utility methods
func get_action_stack_depth() -> int:
	return action_stack.size()

func clear_action_stack() -> void:
	action_stack.clear()

func set_intention_active(active: bool) -> void:
	is_intention_active = active
