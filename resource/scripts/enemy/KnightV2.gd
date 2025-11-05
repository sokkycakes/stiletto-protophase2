extends BaseEnemy
class_name KnightV2

# Simple knight implementation using BaseEnemy
# This replaces your 352-line knight with just the knight-specific behavior

@export_group("Knight Settings")
@export var launch_force: float = 8.0
@export var launch_angle: float = 30.0
@export var charge_speed_multiplier: float = 1.5

# Knight-specific state
var is_charging: bool = false

func setup_enemy():
	# Knight-specific setup
	if debug_enabled:
		print("[KnightV2] Knight ready for battle!")

# =============================================================================
# KNIGHT-SPECIFIC STATE BEHAVIORS
# =============================================================================

func enter_chase():
	super.enter_chase()  # Call parent behavior
	is_charging = false

func do_chase(delta: float):
	# Enhanced chase behavior for knight
	if not target_player:
		change_state(EnemyState.IDLE)
		return
	
	var distance = global_position.distance_to(target_player.global_position)
	
	# Start charging when close
	if distance <= attack_range * 2.0 and not is_charging:
		is_charging = true
		if debug_enabled:
			print("[KnightV2] Charging attack!")
	
	# Move toward player (faster when charging)
	var target_pos = target_player.global_position if can_see_player() else last_known_player_pos
	var speed = movement_speed * (charge_speed_multiplier if is_charging else 1.0)
	move_toward_position(target_pos, speed)
	face_position(target_pos, delta)
	
	# Check for attack range
	if distance <= attack_range and attack_timer <= 0.0:
		change_state(EnemyState.ATTACK)
	
	# Check if lost player
	if not can_see_player():
		lose_target_timer += delta
		if lose_target_timer >= lose_target_time:
			change_state(EnemyState.IDLE)
			is_charging = false
	else:
		lose_target_timer = 0.0
		last_known_player_pos = target_player.global_position

func enter_attack():
	super.enter_attack()  # Call parent behavior
	if debug_enabled:
		print("[KnightV2] Sword attack!")

func do_attack(delta: float):
	# Stop moving and face target
	velocity.x = 0
	velocity.z = 0
	
	if target_player:
		face_position(target_player.global_position, delta)
		
		# Perform knight's melee attack with knockback
		if state_timer >= 0.2 and attack_timer <= 0.0:  # Quick attack
			perform_knight_attack()
			attack_timer = attack_cooldown
			change_state(EnemyState.CHASE)
	else:
		change_state(EnemyState.IDLE)

func exit_attack():
	super.exit_attack()  # Call parent behavior
	is_charging = false

# =============================================================================
# KNIGHT-SPECIFIC METHODS
# =============================================================================

func perform_knight_attack():
	if not target_player:
		return
	
	var distance = global_position.distance_to(target_player.global_position)
	if distance > attack_range:
		return
	
	# Deal damage
	if target_player.has_method("take_damage"):
		target_player.take_damage(attack_damage)
	
	# Launch player (knight's signature move)
	if target_player is CharacterBody3D:
		launch_player(target_player)
	
	# Call player's take_hit if available
	var player_state = target_player.get_node_or_null("PlayerState")
	if player_state and player_state.has_method("take_hit"):
		player_state.take_hit()
	
	if debug_enabled:
		print("[KnightV2] Sword slash! Damage: %d" % attack_damage)

func launch_player(player: CharacterBody3D):
	# Calculate launch direction
	var launch_direction = (player.global_position - global_position).normalized()
	launch_direction.y = 0  # Keep horizontal
	
	# Add vertical component
	var vertical_component = sin(deg_to_rad(launch_angle))
	var launch_vector = launch_direction * launch_force
	launch_vector.y = vertical_component * launch_force
	
	# Apply launch
	player.velocity = launch_vector
	
	if debug_enabled:
		print("[KnightV2] Player launched!")

# Override take_damage for knight-specific behavior
func take_damage(amount: int):
	super.take_damage(amount)  # Call parent behavior
	
	# Knight-specific damage response
	if current_state != EnemyState.DEAD:
		# Knights get angry when hurt
		if current_state == EnemyState.IDLE:
			change_state(EnemyState.CHASE)
