## Death Action - Handle bot death state

class_name DeathAction
extends NextBotAction

var death_timer: float = 0.0
var respawn_time: float = 10.0
var is_death_animation_complete: bool = false

func _init():
	action_name = "Death"

func on_start(bot_ref, prior_action) -> ActionResult:
	super.on_start(bot_ref, prior_action)
	
	death_timer = 0.0
	is_death_animation_complete = false
	
	# Stop all movement
	var locomotion = bot.get_locomotion_interface()
	if locomotion:
		locomotion.drive_to(bot.get_position())
	
	# Play death animation
	var body = bot.get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.DEATH)
	
	# Disable collision
	_disable_collision(bot)
	
	print("Bot ", bot.get_debug_name(), " has died")
	
	return ActionResult.continue_action()

func update(bot_ref, delta: float) -> ActionResult:
	# Handle child actions first
	var child_result = super.update(bot_ref, delta)
	if child_result.type != ActionResultType.CONTINUE:
		return child_result

	death_timer += delta

	# Check if death animation is complete
	if not is_death_animation_complete:
		var body = bot.get_body_interface()
		if body and not body.is_animation_playing("death"):
			is_death_animation_complete = true
			_on_death_animation_complete(bot)

	# Handle respawn if enabled
	if death_timer >= respawn_time:
		return _handle_respawn(bot)

	return ActionResult.continue_action()

func _on_death_animation_complete(bot: INextBot) -> void:
	# Death animation finished, bot is now fully dead
	print("Bot ", bot.get_debug_name(), " death animation complete")
	
	# Additional death effects could go here
	_create_death_effects(bot)

func _handle_respawn(bot: INextBot) -> ActionResult:
	# Check if respawn is enabled for this bot
	if bot.has_method("should_respawn") and bot.should_respawn():
		return _respawn_bot(bot)
	else:
		# Stay dead
		return ActionResult.continue_action()

func _respawn_bot(bot: INextBot) -> ActionResult:
	print("Bot ", bot.get_debug_name(), " respawning")
	
	# Find respawn position
	var respawn_pos = _find_respawn_position(bot)
	
	# Reset bot state
	if bot.has_method("reset_health"):
		bot.reset_health()
	
	# Move to respawn position
	var locomotion = bot.get_locomotion_interface()
	if locomotion:
		locomotion.drive_to(respawn_pos)
	
	# Enable collision
	_enable_collision(bot)
	
	# Reset body state
	var body = bot.get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.IDLE)
	
	# Return to idle behavior
	return ActionResult.change_to(IdleAction.new(), "respawned")

func _find_respawn_position(bot: INextBot) -> Vector3:
	# Look for respawn points in the scene
	var respawn_points = bot.get_tree().get_nodes_in_group("respawn_points")
	
	if not respawn_points.is_empty():
		# Choose random respawn point
		var respawn_point = respawn_points[randi() % respawn_points.size()]
		return respawn_point.global_position
	else:
		# Fallback to original position or a safe position
		return _find_safe_position(bot)

func _find_safe_position(bot: INextBot) -> Vector3:
	# Try to find a safe position away from threats
	var bot_pos = bot.get_position()
	var space_state = bot.get_world_3d().direct_space_state
	
	# Try positions in a circle around current position
	var test_radius = 10.0
	var test_angles = [0, 45, 90, 135, 180, 225, 270, 315]
	
	for angle_deg in test_angles:
		var angle_rad = deg_to_rad(angle_deg)
		var test_direction = Vector3(cos(angle_rad), 0, sin(angle_rad))
		var test_position = bot_pos + (test_direction * test_radius)
		
		# Check if position is safe
		if _is_position_safe(bot, test_position, space_state):
			return test_position
	
	# Fallback to current position
	return bot_pos

func _is_position_safe(bot: INextBot, position: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	# Check for obstacles
	var query = PhysicsRayQueryParameters3D.create(position + Vector3.UP, position + Vector3.DOWN * 2)
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return false  # No ground
	
	# Check for enemies nearby
	var enemies = bot.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy != bot and position.distance_to(enemy.global_position) < 5.0:
			return false  # Too close to enemies
	
	return true

func _disable_collision(bot: INextBot) -> void:
	# Disable collision for the dead bot
	var collision_shape = bot.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = true

func _enable_collision(bot: INextBot) -> void:
	# Re-enable collision for respawned bot
	var collision_shape = bot.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = false

func _create_death_effects(bot: INextBot) -> void:
	# Create death effects like particles, sounds, etc.
	# This is a placeholder for your game's effect system
	pass

# Event handlers - dead bots don't respond to most events
func on_sight_action(subject: Node) -> ActionResult:
	# Dead bots don't see anything
	return ActionResult.continue_action()

func on_sound_action(source: Node, pos: Vector3, sound_data: Dictionary) -> ActionResult:
	# Dead bots don't hear anything
	return ActionResult.continue_action()

func on_injured_action(damage_info: Dictionary) -> ActionResult:
	# Dead bots can't be injured further
	return ActionResult.continue_action()

func on_move_to_success_action(path) -> ActionResult:
	# Dead bots don't move
	return ActionResult.continue_action()

func on_move_to_failure_action(path, reason) -> ActionResult:
	# Dead bots don't move
	return ActionResult.continue_action()

# Query overrides - dead bots don't do anything
func should_retreat(bot: INextBot) -> bool:
	return false

func should_attack(bot: INextBot, threat: Node) -> bool:
	return false

func should_hurry(bot: INextBot) -> bool:
	return false

func should_pickup(bot: INextBot, item: Node) -> bool:
	return false

func is_hindrance(bot: INextBot, blocker: Node) -> bool:
	return false
