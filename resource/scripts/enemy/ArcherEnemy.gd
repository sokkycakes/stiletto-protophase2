extends BaseEnemy
class_name ArcherEnemy

# Ranged enemy implementation using BaseEnemy
# Shows how different the behavior can be while sharing the same foundation

@export_group("Archer Settings")
@export var preferred_distance: float = 8.0  # Stay back from player
@export var min_distance: float = 4.0        # Too close - retreat!
@export var projectile_scene: PackedScene    # Arrow/projectile to shoot
@export var projectile_speed: float = 20.0
@export var aim_time: float = 1.0            # Time to aim before shooting
@export var retreat_speed: float = 6.0       # Speed when backing away

# Archer-specific state
var aim_timer: float = 0.0
var is_aiming: bool = false
var is_retreating: bool = false

func setup_enemy():
	# Archer-specific setup
	if debug_enabled:
		print("[ArcherEnemy] Archer ready to shoot!")

	# Override attack range for ranged combat
	attack_range = preferred_distance + 2.0  # Archers attack from preferred distance

	# Archers prefer to stay at range
	if not projectile_scene:
		push_warning("ArcherEnemy: No projectile_scene assigned! Archer can't shoot.")

# =============================================================================
# ARCHER-SPECIFIC STATE BEHAVIORS
# =============================================================================

func do_idle(delta: float):
	super.do_idle(delta)  # Call parent behavior
	
	# Archers are more alert - longer sight range
	if can_see_player() and target_player:
		var distance = global_position.distance_to(target_player.global_position)
		if distance <= sight_range:
			change_state(EnemyState.CHASE)

func enter_chase():
	super.enter_chase()  # Call parent behavior
	is_aiming = false
	is_retreating = false
	aim_timer = 0.0

func do_chase(delta: float):
	if not target_player:
		change_state(EnemyState.IDLE)
		return

	if not can_see_player():
		# Lost sight - use parent's lose target logic
		super.do_chase(delta)
		return

	var distance = global_position.distance_to(target_player.global_position)

	if debug_enabled:
		print("[ArcherEnemy] Chase - Distance: %.2f, Min: %.2f, Attack: %.2f, Timer: %.2f" % [distance, min_distance, attack_range, attack_timer])

	# Archer positioning logic
	if distance < min_distance:
		# Too close! Retreat
		if debug_enabled:
			print("[ArcherEnemy] Too close! Retreating...")
		retreat_from_player(delta)
	elif distance > preferred_distance + 2.0:
		# Too far! Move closer
		if debug_enabled:
			print("[ArcherEnemy] Too far! Moving closer...")
		move_toward_position(target_player.global_position, movement_speed)
		face_position(target_player.global_position, delta)
	elif distance >= min_distance and distance <= attack_range and attack_timer <= 0.0:
		# Perfect distance! Attack
		if debug_enabled:
			print("[ArcherEnemy] Perfect distance! Attacking...")
		change_state(EnemyState.ATTACK)
	else:
		# Good position, just face player
		if debug_enabled:
			print("[ArcherEnemy] Good position, facing player...")
		velocity.x = move_toward(velocity.x, 0, 5.0)
		velocity.z = move_toward(velocity.z, 0, 5.0)
		face_position(target_player.global_position, delta)

func retreat_from_player(delta: float):
	if not target_player:
		return
	
	is_retreating = true
	
	# Move away from player
	var direction = (global_position - target_player.global_position).normalized()
	direction.y = 0
	velocity.x = direction.x * retreat_speed
	velocity.z = direction.z * retreat_speed
	
	# Still face the player while retreating
	face_position(target_player.global_position, delta)
	
	if debug_enabled and not is_retreating:
		print("[ArcherEnemy] Retreating! Too close!")

func enter_attack():
	super.enter_attack()  # Call parent behavior
	is_aiming = true
	aim_timer = 0.0
	
	if debug_enabled:
		print("[ArcherEnemy] Taking aim...")

func do_attack(delta: float):
	# Stop moving and aim
	velocity.x = 0
	velocity.z = 0
	
	if not target_player:
		change_state(EnemyState.IDLE)
		return
	
	# Face target while aiming
	face_position(target_player.global_position, delta)
	
	# Aim time
	aim_timer += delta
	
	if aim_timer >= aim_time and attack_timer <= 0.0:
		# Fire!
		shoot_projectile()
		attack_timer = attack_cooldown
		change_state(EnemyState.CHASE)

func exit_attack():
	super.exit_attack()  # Call parent behavior
	is_aiming = false
	is_retreating = false

# =============================================================================
# ARCHER-SPECIFIC METHODS
# =============================================================================

func shoot_projectile():
	if not target_player or not projectile_scene:
		if debug_enabled:
			print("[ArcherEnemy] Can't shoot - no target or projectile!")
		return

	# Create projectile
	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)

	# Position projectile at archer
	var spawn_position = global_position + Vector3(0, 1.5, 0)  # Shoot from chest height
	projectile.global_position = spawn_position

	# Calculate direction to player (aim at player's center)
	var target_position = target_player.global_position + Vector3(0, 1.0, 0)  # Aim at player's center
	var direction = (target_position - spawn_position).normalized()

	if debug_enabled:
		print("[ArcherEnemy] Shooting from: %s to: %s" % [spawn_position, target_position])
		print("[ArcherEnemy] Direction: %s, Speed: %s" % [direction, projectile_speed])

	# Set projectile velocity/direction (try multiple methods for compatibility)
	if projectile.has_method("set_direction"):
		projectile.set_direction(direction, projectile_speed)
	elif projectile.has_method("set_velocity"):
		projectile.set_velocity(direction * projectile_speed)
	elif projectile is RigidBody3D:
		projectile.linear_velocity = direction * projectile_speed
	elif projectile is CharacterBody3D:
		projectile.velocity = direction * projectile_speed
	else:
		if debug_enabled:
			print("[ArcherEnemy] Warning: Unknown projectile type, trying direct velocity assignment")
		if "linear_velocity" in projectile:
			projectile.linear_velocity = direction * projectile_speed
		elif "velocity" in projectile:
			projectile.velocity = direction * projectile_speed

	# Set damage if projectile supports it
	if projectile.has_method("set_damage"):
		projectile.set_damage(attack_damage)

	# Orient projectile to face direction
	if projectile is Node3D:
		projectile.look_at(spawn_position + direction, Vector3.UP)

	if debug_enabled:
		print("[ArcherEnemy] Arrow shot! Direction: %s, Damage: %s" % [direction, attack_damage])

# Override the base attack method since archers don't do melee
func perform_attack():
	# Archers use projectiles, not melee
	shoot_projectile()

# Override can_see_player for archer's better vision
func can_see_player() -> bool:
	if not target_player:
		return false
	
	var distance = global_position.distance_to(target_player.global_position)
	# Archers have better sight range
	if distance > sight_range * 1.2:
		return false
	
	# Improved line-of-sight check (matches BaseEnemy but with archer eye height)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.5, 0),  # Eye level
		target_player.global_position + Vector3(0, 1, 0)
	)
	query.exclude = [self]
	
	var result = space_state.intersect_ray(query)
	var can_see: bool = false
	if result.is_empty():
		can_see = true
	else:
		var hit: Object = result.collider
		if hit == target_player:
			can_see = true
		else:
			# Ascend from hit collider to see if it's part of the player
			var n: Node = hit as Node
			while n and not can_see:
				if n == target_player:
					can_see = true
					break
				n = n.get_parent()
	return can_see

# Override take_damage for archer-specific behavior
func take_damage(amount: int):
	super.take_damage(amount)  # Call parent behavior
	
	# Archers panic when hurt - try to retreat
	if current_state != EnemyState.DEAD and target_player:
		var distance = global_position.distance_to(target_player.global_position)
		if distance < preferred_distance:
			if debug_enabled:
				print("[ArcherEnemy] Hit! Retreating!")
			# Force a retreat by changing state
			change_state(EnemyState.CHASE)
