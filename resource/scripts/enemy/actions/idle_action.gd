## Idle Action - Basic idle behavior for NextBot
class_name IdleAction
extends NextBotAction

var idle_timer: float = 0.0
var max_idle_time: float = 5.0
var look_around_timer: float = 0.0
var look_around_interval: float = 2.0

func _init():
	action_name = "Idle"

func on_start(bot_ref, prior_action: NextBotAction) -> ActionResult:
	super.on_start(bot_ref, prior_action)
	
	idle_timer = 0.0
	look_around_timer = 0.0
	
	# Set idle animation
	var body = bot.get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.IDLE)
	
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Handle child actions first
	var child_result = super.update(bot_ref, delta)
	if child_result.type != ActionResultType.CONTINUE:
		return child_result
	
	idle_timer += delta
	look_around_timer += delta
	
	# Occasionally look around
	if look_around_timer >= look_around_interval:
		look_around_timer = 0.0
		_look_around(bot)
	
	# Check for threats
	var vision = bot.get_vision_interface()
	if vision:
		var threat = vision.get_primary_known_threat(true)
		if threat:
			return ActionResult.change_to(SeekAndDestroyAction.new(), "threat detected")

	# After max idle time, do something else
	if idle_timer >= max_idle_time:
		return ActionResult.change_to(PatrolAction.new(), "idle timeout")
	
	return ActionResult.continue_action()

func on_sight_action(subject: Node) -> ActionResult:
	# If we see something interesting, investigate
	var vision = bot.get_vision_interface()
	if vision:
		var known_entity = vision._get_known_entity(subject)
		if known_entity and known_entity.threat_level > 0.3:
			return ActionResult.change_to(SeekAndDestroyAction.new(), "threat spotted")
	
	return ActionResult.continue_action()

func on_sound_action(source: Node, pos: Vector3, sound_data: Dictionary) -> ActionResult:
	# React to interesting sounds
	if source != bot and pos.distance_to(bot.global_position) < 10.0:
		var investigate_action = InvestigateAction.new()
		investigate_action.set_target_position(pos)
		return ActionResult.suspend_for(investigate_action, "investigating sound")
	
	return ActionResult.continue_action()

func _look_around(bot: INextBot) -> void:
	# Randomly look in different directions
	var body = bot.get_body_interface()
	if body:
		var random_angle = randf() * PI * 2
		var look_direction = Vector3(cos(random_angle), 0, sin(random_angle))
		var look_position = bot.global_position + look_direction * 5.0
		body.aim_head_towards_pos(look_position, 1.0)

# Query overrides
func should_retreat(bot: INextBot) -> bool:
	# Idle bots should retreat if they detect threats and are low on health
	var vision = bot.get_vision_interface()
	if vision:
		var threat = vision.get_primary_known_threat(true)
		if threat and bot.has_method("is_health_low") and bot.is_health_low():
			return true
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	# Idle bots will attack if threatened directly
	if threat and bot.global_position.distance_to(threat.global_position) < 5.0:
		return true
	return false
