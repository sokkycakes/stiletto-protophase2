## NextBot Action - Base class for all bot behaviors/actions
## Based on Source SDK NextBotBehavior.h
class_name NextBotAction
extends INextBotEventResponder

# Action result types
enum ActionResultType {
	CONTINUE,      # Keep running this action
	CHANGE_TO,     # Change to a different action
	SUSPEND_FOR,   # Suspend this action for another, then resume
	DONE          # This action is complete
}

# Action result class
class ActionResult:
	var type: ActionResultType
	var action: NextBotAction = null
	var reason: String = ""
	
	func _init(result_type: ActionResultType, next_action: NextBotAction = null, result_reason: String = ""):
		type = result_type
		action = next_action
		reason = result_reason
	
	static func continue_action() -> ActionResult:
		return ActionResult.new(ActionResultType.CONTINUE)
	
	static func change_to(new_action: NextBotAction, reason: String = "") -> ActionResult:
		return ActionResult.new(ActionResultType.CHANGE_TO, new_action, reason)
	
	static func suspend_for(new_action: NextBotAction, reason: String = "") -> ActionResult:
		return ActionResult.new(ActionResultType.SUSPEND_FOR, new_action, reason)
	
	static func done(reason: String = "") -> ActionResult:
		return ActionResult.new(ActionResultType.DONE, null, reason)

# Action properties
var action_name: String = "Action"
var parent_action: NextBotAction = null
var child_action: NextBotAction = null
var is_started: bool = false
var is_suspended: bool = false
var bot = null  # Reference to the bot this action is running on

# Lifecycle methods - override in derived classes
func on_start(bot_ref, prior_action: NextBotAction) -> ActionResult:
	bot = bot_ref  # Store bot reference for use in event methods
	is_started = true
	is_suspended = false
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Update child action if we have one
	if child_action:
		var result = child_action.update(bot, delta)
		return _handle_child_result(bot, result)
	
	return ActionResult.continue_action()

func on_end(bot_ref, next_action: NextBotAction) -> void:
	is_started = false
	is_suspended = false

	# End child action if we have one
	if child_action:
		child_action.on_end(bot_ref, next_action)
		child_action = null

func on_suspend(bot_ref, interrupting_action: NextBotAction) -> ActionResult:
	is_suspended = true

	# Suspend child action if we have one
	if child_action:
		return child_action.on_suspend(bot_ref, interrupting_action)

	return ActionResult.continue_action()

func on_resume(bot_ref, interrupting_action: NextBotAction) -> ActionResult:
	is_suspended = false

	# Resume child action if we have one
	if child_action:
		return child_action.on_resume(bot_ref, interrupting_action)

	return ActionResult.continue_action()

# Child action management
func start_child_action(bot_ref, action: NextBotAction) -> ActionResult:
	if child_action:
		child_action.on_end(bot_ref, action)

	child_action = action
	action.parent_action = self

	return action.on_start(bot_ref, null)

func get_child_action() -> NextBotAction:
	return child_action

func has_child_action() -> bool:
	return child_action != null

# Query methods - override in derived classes for decision making
func should_pickup(bot: INextBot, item: Node) -> bool:
	if child_action:
		return child_action.should_pickup(bot, item)
	return false

func should_hurry(bot: INextBot) -> bool:
	if child_action:
		return child_action.should_hurry(bot)
	return false

func should_retreat(bot: INextBot) -> bool:
	if child_action:
		return child_action.should_retreat(bot)
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	if child_action:
		return child_action.should_attack(bot, threat)
	return false

func is_hindrance(bot: INextBot, blocker: Node) -> bool:
	if child_action:
		return child_action.is_hindrance(bot, blocker)
	return false

func select_target_point(bot: INextBot, subject: Node) -> Vector3:
	if child_action:
		return child_action.select_target_point(bot, subject)
	return subject.global_position if subject else Vector3.ZERO

func select_more_dangerous_threat(bot: INextBot, subject1: IVision.KnownEntity, subject2: IVision.KnownEntity) -> IVision.KnownEntity:
	if child_action:
		return child_action.select_more_dangerous_threat(bot, subject1, subject2)
	
	# Default implementation
	if not subject1:
		return subject2
	if not subject2:
		return subject1
	
	# Prefer closer threats
	var eye_pos = bot.get_body_interface().get_eye_position()
	var dist1 = eye_pos.distance_to(subject1.last_known_position)
	var dist2 = eye_pos.distance_to(subject2.last_known_position)
	
	return subject1 if dist1 < dist2 else subject2

# Event handling - override parent void methods but provide ActionResult versions for actions
func on_move_to_success(path) -> void:
	var result = on_move_to_success_action(path)
	_handle_event_result(result)

func on_move_to_failure(path, reason) -> void:
	var result = on_move_to_failure_action(path, reason)
	_handle_event_result(result)

func on_stuck() -> void:
	var result = on_stuck_action()
	_handle_event_result(result)

func on_unstuck() -> void:
	var result = on_unstuck_action()
	_handle_event_result(result)

# Action-specific event methods that return ActionResult - override these in derived classes
func on_move_to_success_action(path) -> ActionResult:
	if child_action and child_action.has_method("on_move_to_success_action"):
		return child_action.on_move_to_success_action(path)
	return ActionResult.continue_action()

func on_move_to_failure_action(path, reason) -> ActionResult:
	if child_action and child_action.has_method("on_move_to_failure_action"):
		return child_action.on_move_to_failure_action(path, reason)
	return ActionResult.continue_action()

func on_stuck_action() -> ActionResult:
	if child_action and child_action.has_method("on_stuck_action"):
		return child_action.on_stuck_action()
	return ActionResult.continue_action()

func on_unstuck_action() -> ActionResult:
	if child_action and child_action.has_method("on_unstuck_action"):
		return child_action.on_unstuck_action()
	return ActionResult.continue_action()

# Helper method to handle ActionResult from event methods
func _handle_event_result(result: ActionResult) -> void:
	if not result or not bot:
		return

	# Get the intention interface to handle action changes
	var intention = bot.get_intention_interface()
	if not intention:
		return

	# Handle the result similar to how intention handles action results
	match result.type:
		ActionResultType.CHANGE_TO:
			if result.action:
				intention.change_action(result.action)
		ActionResultType.SUSPEND_FOR:
			if result.action:
				intention.suspend_for(result.action)
		ActionResultType.DONE:
			if result.action:
				intention.start_action(result.action)
			# If no next action, the intention will handle getting initial action

# Override parent void methods but provide ActionResult versions for actions
func on_sight(subject: Node) -> void:
	var result = on_sight_action(subject)
	_handle_event_result(result)

func on_lost_sight(subject: Node) -> void:
	var result = on_lost_sight_action(subject)
	_handle_event_result(result)

func on_injured(damage_info: Dictionary) -> void:
	var result = on_injured_action(damage_info)
	_handle_event_result(result)

# Action-specific event methods that return ActionResult - override these in derived classes
func on_sight_action(subject: Node) -> ActionResult:
	if child_action and child_action.has_method("on_sight_action"):
		return child_action.on_sight_action(subject)
	return ActionResult.continue_action()

func on_lost_sight_action(subject: Node) -> ActionResult:
	if child_action and child_action.has_method("on_lost_sight_action"):
		return child_action.on_lost_sight_action(subject)
	return ActionResult.continue_action()

func on_injured_action(damage_info: Dictionary) -> ActionResult:
	if child_action and child_action.has_method("on_injured_action"):
		return child_action.on_injured_action(damage_info)
	return ActionResult.continue_action()

# Override parent void methods
func on_killed(damage_info: Dictionary) -> void:
	var result = on_killed_action(damage_info)
	_handle_event_result(result)

func on_other_killed(victim: Node, damage_info: Dictionary) -> void:
	var result = on_other_killed_action(victim, damage_info)
	_handle_event_result(result)

func on_sound(source: Node, pos: Vector3, sound_data: Dictionary) -> void:
	var result = on_sound_action(source, pos, sound_data)
	_handle_event_result(result)

func on_weapon_fired(who_fired: Node, weapon: Node) -> void:
	var result = on_weapon_fired_action(who_fired, weapon)
	_handle_event_result(result)

# Action-specific event methods that return ActionResult
func on_killed_action(damage_info: Dictionary) -> ActionResult:
	if child_action and child_action.has_method("on_killed_action"):
		return child_action.on_killed_action(damage_info)
	return ActionResult.continue_action()

func on_other_killed_action(victim: Node, damage_info: Dictionary) -> ActionResult:
	if child_action and child_action.has_method("on_other_killed_action"):
		return child_action.on_other_killed_action(victim, damage_info)
	return ActionResult.continue_action()

func on_sound_action(source: Node, pos: Vector3, sound_data: Dictionary) -> ActionResult:
	if child_action and child_action.has_method("on_sound_action"):
		return child_action.on_sound_action(source, pos, sound_data)
	return ActionResult.continue_action()

func on_weapon_fired_action(who_fired: Node, weapon: Node) -> ActionResult:
	if child_action and child_action.has_method("on_weapon_fired_action"):
		return child_action.on_weapon_fired_action(who_fired, weapon)
	return ActionResult.continue_action()

# Utility methods
func get_action_name() -> String:
	return action_name

func set_action_name(name: String) -> void:
	action_name = name

func get_action_parent() -> NextBotAction:
	return parent_action

func is_named(name: String) -> bool:
	return action_name == name

# Event handling methods - override in derived classes to respond to events
# These return ActionResult to allow actions to change behavior based on events

# Child action result handling
func _handle_child_result(bot_ref, result: ActionResult) -> ActionResult:
	if not result:
		return ActionResult.continue_action()
	
	match result.type:
		ActionResultType.CONTINUE:
			return ActionResult.continue_action()
			
		ActionResultType.CHANGE_TO:
			# Child wants to change - start new child action
			if result.action:
				return start_child_action(bot_ref, result.action)
			else:
				# No child action
				child_action = null
				return ActionResult.continue_action()

		ActionResultType.SUSPEND_FOR:
			# Child wants to suspend - not typically handled at this level
			return result

		ActionResultType.DONE:
			# Child is done
			if child_action:
				child_action.on_end(bot_ref, null)
				child_action = null
			
			# Continue with this action
			return ActionResult.continue_action()
	
	return ActionResult.continue_action()
