## Attack Action - Engage and attack a target
class_name AttackAction
extends NextBotAction

var target: Node = null
var attack_timer: float = 0.0
var attack_interval: float = 1.0
var max_attack_range: float = 3.0
var min_attack_range: float = 1.0
var attack_timeout: float = 10.0
var timeout_timer: float = 0.0

func _init():
	action_name = "Attack"

func on_start(bot_ref, prior_action: NextBotAction) -> ActionResult:
	super.on_start(bot_ref, prior_action)
	
	attack_timer = 0.0
	timeout_timer = 0.0
	
	# Find target
	_find_target(bot)
	
	# Set attack animation
	var body = bot.get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.ATTACK)
	
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Handle child actions first
	var child_result = super.update(bot_ref, delta)
	if child_result.type != ActionResultType.CONTINUE:
		return child_result
	
	attack_timer += delta
	timeout_timer += delta
	
	# Check if we still have a valid target
	if not target or not is_instance_valid(target):
		return ActionResult.change_to(SeekAndDestroyAction.new(), "lost target")
	
	# Check timeout
	if timeout_timer > attack_timeout:
		return ActionResult.change_to(SeekAndDestroyAction.new(), "attack timeout")
	
	var distance = bot.global_position.distance_to(target.global_position)
	var vision = bot.get_vision_interface()
	var locomotion = bot.get_locomotion_interface()
	
	# Check if we can see the target
	if not vision or not vision.is_able_to_see(target):
		return ActionResult.change_to(SeekAndDestroyAction.new(), "lost sight of target")
	
	# Position ourselves for attack
	if distance > max_attack_range:
		# Too far, move closer
		if locomotion:
			locomotion.approach(target.global_position)
		return ActionResult.continue_action()
	elif distance < min_attack_range:
		# Too close, back away slightly
		if locomotion:
			var retreat_direction = (bot.global_position - target.global_position).normalized()
			var retreat_position = bot.global_position + retreat_direction * 2.0
			locomotion.approach(retreat_position)
		return ActionResult.continue_action()
	
	# In attack range, face target and attack
	var body = bot.get_body_interface()
	if body:
		body.face_towards(target.global_position)
	
	# Perform attack
	if attack_timer >= attack_interval:
		attack_timer = 0.0
		_perform_attack(bot)
	
	return ActionResult.continue_action()

func _find_target(bot: INextBot) -> void:
	var vision = bot.get_vision_interface()
	if not vision:
		return
	
	var threat = vision.get_primary_known_threat(true)  # Only visible threats
	if threat:
		target = threat.entity

func _perform_attack(bot: INextBot) -> void:
	if not target or not is_instance_valid(target):
		return
	
	# Play attack animation
	var body = bot.get_body_interface()
	if body:
		body.play_animation("attack")
	
	# Deal damage if target has health
	if target.has_method("take_damage"):
		var damage_info = {
			"amount": 25.0,
			"attacker": bot,
			"position": target.global_position
		}
		target.take_damage(damage_info)
	
	# Create attack effects (placeholder)
	_create_attack_effects(bot)

func _create_attack_effects(bot: INextBot) -> void:
	# Placeholder for attack effects like sounds, particles, etc.
	# In a real implementation, you'd spawn attack effects here
	pass

# Event handlers
func on_sight_action(subject: Node) -> ActionResult:
	# If we see a more dangerous threat, switch targets
	var vision = bot.get_vision_interface()
	if vision:
		var known_entity = vision._get_known_entity(subject)
		if known_entity and known_entity.threat_level > 0.8:
			var current_threat_level = 0.0
			if target:
				var current_known = vision._get_known_entity(target)
				if current_known:
					current_threat_level = current_known.threat_level
			
			if known_entity.threat_level > current_threat_level:
				target = subject
				timeout_timer = 0.0  # Reset timeout
	
	return ActionResult.continue_action()

func on_lost_sight_action(subject: Node) -> ActionResult:
	if subject == target:
		return ActionResult.change_to(SeekAndDestroyAction.new(), "lost sight of target")
	
	return ActionResult.continue_action()

func on_injured_action(damage_info: Dictionary) -> ActionResult:
	# If we're injured during attack, check if we should retreat
	if bot.has_method("is_health_low") and bot.is_health_low():
		return ActionResult.change_to(RetreatAction.new(), "injured during attack")
	
	# Otherwise, become more aggressive
	attack_interval *= 0.8  # Attack faster
	return ActionResult.continue_action()

func on_other_killed_action(victim: Node, damage_info: Dictionary) -> ActionResult:
	# If we killed our target, look for new targets
	if victim == target:
		return ActionResult.change_to(SeekAndDestroyAction.new(), "target eliminated")
	
	return ActionResult.continue_action()

# Query overrides
func should_retreat(bot: INextBot) -> bool:
	# Retreat if very low health or heavily outnumbered
	if bot.has_method("is_health_low") and bot.is_health_low():
		return true
	
	var vision = bot.get_vision_interface()
	if vision and vision.get_known_count(-1, true) > 3:  # Too many enemies
		return true
	
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	# Always continue attacking if we're already in attack mode
	return true

func should_hurry(bot: INextBot) -> bool:
	# Always hurry during combat
	return true

func is_hindrance(bot: INextBot, blocker: Node) -> bool:
	# Other entities are hindrances during attack
	return blocker != target and blocker != bot
