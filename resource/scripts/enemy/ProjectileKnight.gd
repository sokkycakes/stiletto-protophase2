extends KnightV2
class_name ProjectileKnight

## Knight enemy that fires projectiles for testing parry mechanics
## Extends KnightV2 to inherit all knight behavior but adds projectile firing
## This is a stationary, invincible test dummy for parry mechanics

@export_group("Projectile Settings")
@export var projectile_scene: PackedScene = preload("res://resource/entities/player/projectile.tscn")
@export var projectile_fire_rate: float = 1.0  # Fires every second
@export var projectile_speed: float = 20.0
@export var projectile_damage: int = 0  # No damage for testing
@export var projectile_spawn_offset: Vector3 = Vector3(0, 1.5, 0)  # Spawn projectiles at chest height

@export_group("Test Dummy Settings")
@export var is_stationary: bool = true  # Doesn't move
@export var is_invincible: bool = true  # Can't be killed

# Internal timer for projectile firing
var projectile_timer: float = 0.0

func _ready() -> void:
	super._ready()
	if debug_enabled:
		print("[ProjectileKnight] Projectile knight initialized - fires every ", projectile_fire_rate, " seconds")

# Override player detection to prevent spam - we don't need to find players
func _update_player_detection(delta: float) -> void:
	# Do nothing - ProjectileKnight doesn't need player detection
	# This prevents the parent class from spamming debug messages
	pass

func _physics_process(delta: float) -> void:
	# Call parent but skip player detection (handled by override above)
	super._physics_process(delta)
	
	# Fire projectiles continuously when alive (no target needed)
	if current_state != EnemyState.DEAD:
		_update_projectile_firing(delta)

func _update_projectile_firing(delta: float) -> void:
	"""Update projectile firing timer and spawn projectiles"""
	projectile_timer -= delta
	
	if projectile_timer <= 0.0:
		_fire_projectile()
		projectile_timer = projectile_fire_rate

func _fire_projectile() -> void:
	"""Spawn and fire a projectile in the knight's forward direction"""
	if not projectile_scene:
		return
	
	# Instantiate projectile
	var projectile: Projectile = projectile_scene.instantiate()
	if not projectile:
		push_error("[ProjectileKnight] Failed to instantiate projectile")
		return
	
	# Add to scene
	get_tree().current_scene.add_child(projectile)
	
	# Calculate spawn position (in front of knight at chest height)
	var spawn_pos = global_position + projectile_spawn_offset
	
	# Fire in the knight's forward direction (based on spawn rotation)
	var direction = -global_transform.basis.z.normalized()
	
	# Override projectile settings for testing
	projectile.damage = projectile_damage
	projectile.speed = projectile_speed
	
	# Initialize projectile with direction
	projectile.initialize(spawn_pos, direction, self, -1)
	
	if debug_enabled:
		print("[ProjectileKnight] Fired projectile in forward direction: ", direction)

# Override setup to announce projectile knight
func setup_enemy() -> void:
	super.setup_enemy()
	if debug_enabled:
		print("[ProjectileKnight] Projectile Knight ready! Will fire projectiles every ", projectile_fire_rate, " seconds")
		if is_invincible:
			print("[ProjectileKnight] Invincible mode enabled - cannot die")
		if is_stationary:
			print("[ProjectileKnight] Stationary mode enabled - will not move")

# Override take_damage to make invincible
func take_damage(amount: int) -> void:
	if is_invincible:
		if debug_enabled:
			print("[ProjectileKnight] Invincible - ignoring ", amount, " damage")
		return
	
	# If not invincible, use normal damage handling
	super.take_damage(amount)

# Override idle behavior to still fire projectiles even when stationary
func do_idle(delta: float) -> void:
	if is_stationary:
		# Stay in place, don't move or rotate
		velocity.x = 0
		velocity.z = 0
		return
	
	# If not stationary, use normal idle behavior
	super.do_idle(delta)

# Override chase behavior to keep distance while firing projectiles
func do_chase(delta: float) -> void:
	if is_stationary:
		# Don't move or rotate, just stay in place
		velocity.x = 0
		velocity.z = 0
		return
	
	# Original chase behavior (with distance management)
	# If not stationary, use the original chase behavior
	if not target_player:
		change_state(EnemyState.IDLE)
		return
	
	var distance = global_position.distance_to(target_player.global_position)
	
	# Keep a medium distance for projectile attacks (don't get too close)
	var optimal_distance = attack_range * 2.5
	
	var target_pos = target_player.global_position if can_see_player() else last_known_player_pos
	
	# If too close, back away; if too far, move closer
	if distance < optimal_distance:
		# Move away from player
		var away_direction = (global_position - target_pos).normalized()
		var move_target = global_position + away_direction * 2.0
		move_toward_position(move_target, movement_speed * 0.5)
	elif distance > optimal_distance * 2.0:
		# Move toward player
		move_toward_position(target_pos, movement_speed)
	# else: stay at current distance
	
	# Always face the player
	face_position(target_pos, delta)
	
	# Don't enter melee attack state - this knight only fires projectiles
	# (Removed the attack range check from base class)
	
	# Check if lost player
	if not can_see_player():
		lose_target_timer += delta
		if lose_target_timer >= lose_target_time:
			change_state(EnemyState.IDLE)
	else:
		lose_target_timer = 0.0
		last_known_player_pos = target_player.global_position

# Override attack to prevent melee attacks
func enter_attack() -> void:
	# Projectile knight doesn't do melee attacks, go back to chase
	change_state(EnemyState.CHASE)

func do_attack(delta: float) -> void:
	# Should never reach here, but just in case
	change_state(EnemyState.CHASE)

