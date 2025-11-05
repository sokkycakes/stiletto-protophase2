## Unstuck Action - Attempt to get unstuck from obstacles
class_name UnstuckAction
extends NextBotAction

var unstuck_attempts: int = 0
var max_unstuck_attempts: int = 5
var attempt_timer: float = 0.0
var attempt_duration: float = 1.0
var original_position: Vector3 = Vector3.ZERO
var current_unstuck_method: int = 0

enum UnstuckMethod {
	RANDOM_MOVEMENT,
	BACKWARD_MOVEMENT,
	JUMP,
	TELEPORT_NEARBY,
	GIVE_UP
}

func _init():
	action_name = "Unstuck"

func on_start(bot_ref, prior_action: NextBotAction) -> ActionResult:
	super.on_start(bot_ref, prior_action)
	
	unstuck_attempts = 0
	attempt_timer = 0.0
	current_unstuck_method = 0
	original_position = bot.global_position
	
	print("Bot ", bot.get_debug_name(), " attempting to unstuck")
	
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Handle child actions first
	var child_result = super.update(bot_ref, delta)
	if child_result.type != ActionResultType.CONTINUE:
		return child_result
	
	attempt_timer += delta
	
	# Check if we're no longer stuck
	var locomotion = bot.get_locomotion_interface()
	if locomotion and not locomotion.is_stuck_query():
		return ActionResult.done("successfully unstuck")
	
	# Try different unstuck methods
	if attempt_timer >= attempt_duration:
		attempt_timer = 0.0
		unstuck_attempts += 1
		
		if unstuck_attempts > max_unstuck_attempts:
			return ActionResult.done("gave up trying to unstuck")
		
		_try_unstuck_method(bot, current_unstuck_method)
		current_unstuck_method = (current_unstuck_method + 1) % UnstuckMethod.size()
	
	return ActionResult.continue_action()

func _try_unstuck_method(bot: INextBot, method: UnstuckMethod) -> void:
	var locomotion = bot.get_locomotion_interface()
	var body = bot.get_body_interface()
	
	match method:
		UnstuckMethod.RANDOM_MOVEMENT:
			_try_random_movement(bot, locomotion)
		
		UnstuckMethod.BACKWARD_MOVEMENT:
			_try_backward_movement(bot, locomotion)
		
		UnstuckMethod.JUMP:
			_try_jump(bot, locomotion)
		
		UnstuckMethod.TELEPORT_NEARBY:
			_try_teleport_nearby(bot, locomotion)
		
		UnstuckMethod.GIVE_UP:
			print("Bot ", bot.get_debug_name(), " giving up on unstuck attempts")

func _try_random_movement(bot: INextBot, locomotion: ILocomotion) -> void:
	if not locomotion:
		return
	
	# Try moving in a random direction
	var random_angle = randf() * PI * 2
	var random_direction = Vector3(cos(random_angle), 0, sin(random_angle))
	var unstuck_position = bot.global_position + (random_direction * 3.0)
	
	print("Bot ", bot.get_debug_name(), " trying random movement to unstuck")
	locomotion.approach(unstuck_position)

func _try_backward_movement(bot: INextBot, locomotion: ILocomotion) -> void:
	if not locomotion:
		return
	
	# Try moving backward from current facing direction
	var backward_direction = bot.global_transform.basis.z  # Positive Z is backward
	var backward_position = bot.global_position + (backward_direction * 2.0)
	
	print("Bot ", bot.get_debug_name(), " trying backward movement to unstuck")
	locomotion.approach(backward_position)

func _try_jump(bot: INextBot, locomotion: ILocomotion) -> void:
	if not locomotion:
		return
	
	# Try jumping to get over obstacle
	if locomotion.is_on_ground_query():
		print("Bot ", bot.get_debug_name(), " trying jump to unstuck")
		locomotion.jump()
		
		# Also try moving forward while jumping
		var forward_direction = -bot.global_transform.basis.z
		var jump_position = bot.global_position + (forward_direction * 2.0)
		locomotion.approach(jump_position)

func _try_teleport_nearby(bot: INextBot, locomotion: ILocomotion) -> void:
	if not locomotion:
		return
	
	# Find a nearby clear position and teleport there
	var clear_position = _find_clear_position(bot)
	if clear_position != Vector3.ZERO:
		print("Bot ", bot.get_debug_name(), " teleporting to clear position to unstuck")
		locomotion.drive_to(clear_position)
	else:
		print("Bot ", bot.get_debug_name(), " could not find clear position for teleport")

func _find_clear_position(bot: INextBot) -> Vector3:
	var bot_pos = bot.global_position
	var space_state = bot.get_world_3d().direct_space_state
	
	# Try positions in a circle around the bot
	var test_radius = 3.0
	var test_angles = [0, 45, 90, 135, 180, 225, 270, 315]
	
	for angle_deg in test_angles:
		var angle_rad = deg_to_rad(angle_deg)
		var test_direction = Vector3(cos(angle_rad), 0, sin(angle_rad))
		var test_position = bot_pos + (test_direction * test_radius)
		
		# Check if position is clear
		if _is_position_clear(bot, test_position, space_state):
			return test_position
	
	# Try positions at different heights
	for height_offset in [1.0, -1.0, 2.0]:
		var test_position = bot_pos + Vector3(0, height_offset, 0)
		if _is_position_clear(bot, test_position, space_state):
			return test_position
	
	return Vector3.ZERO

func _is_position_clear(bot: INextBot, position: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	# Check if there's enough space at the position
	var body_interface = bot.get_body_interface()
	var hull_size = Vector3(0.8, 1.8, 0.8)  # Default hull size
	
	if body_interface:
		hull_size.x = body_interface.get_hull_width()
		hull_size.y = body_interface.get_hull_height()
		hull_size.z = body_interface.get_hull_width()
	
	# Create a box query to check for obstacles
	var query = PhysicsShapeQueryParameters3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = hull_size
	query.shape = box_shape
	query.transform.origin = position
	query.exclude = [bot]
	
	var results = space_state.intersect_shape(query, 1)
	return results.is_empty()

# Event handlers
func on_sight_action(subject: Node) -> ActionResult:
	# If we see a threat while trying to unstuck, prioritize getting unstuck first
	var vision = bot.get_vision_interface()
	if vision:
		var known_entity = vision._get_known_entity(subject)
		if known_entity and known_entity.threat_level > 0.8:
			# Very dangerous threat, try to unstuck faster
			attempt_duration *= 0.5
			max_unstuck_attempts += 2
	
	return ActionResult.continue_action()

func on_injured_action(damage_info: Dictionary) -> ActionResult:
	# If we're taking damage while stuck, try more aggressive unstuck methods
	print("Bot ", bot.get_debug_name(), " taking damage while stuck, trying aggressive unstuck")
	
	# Try teleporting immediately
	var locomotion = bot.get_locomotion_interface()
	_try_teleport_nearby(bot, locomotion)
	
	# Reduce attempt duration
	attempt_duration = 0.5
	
	return ActionResult.continue_action()

func on_move_to_success_action(path: NextBotPath) -> ActionResult:
	# Successfully moved, we might be unstuck
	var locomotion = bot.get_locomotion_interface()
	if locomotion:
		locomotion.clear_stuck_status()
	
	return ActionResult.done("movement successful, likely unstuck")

func on_move_to_failure_action(path: NextBotPath, reason: NextBotPath.FailureType) -> ActionResult:
	# Movement failed, try different method
	current_unstuck_method = (current_unstuck_method + 1) % UnstuckMethod.size()
	attempt_timer = attempt_duration  # Force immediate retry
	
	return ActionResult.continue_action()

# Query overrides
func should_retreat(bot: INextBot) -> bool:
	# Don't retreat while trying to unstuck, focus on getting unstuck first
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	# Don't attack while stuck unless absolutely necessary
	if threat and bot.get_position().distance_to(threat.global_position) < 2.0:
		return true  # Fight back if very close
	return false

func should_hurry(bot: INextBot) -> bool:
	# Always hurry when trying to unstuck
	return true

func is_hindrance(bot: INextBot, blocker: Node) -> bool:
	# Everything is a potential hindrance when stuck
	return blocker != bot
