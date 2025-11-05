extends CharacterBody3D
class_name BaseEnemy

# Base enemy state machine system
# Provides common functionality that all enemies can use

enum EnemyState {
	IDLE,
	PATROL, 
	CHASE,
	ATTACK,
	STUNNED,
	DEAD
}

# Core properties - easily configurable in editor
@export_group("Movement")
@export var movement_speed: float = 5.0
@export var patrol_speed: float = 2.5
@export var turn_speed: float = 5.0

@export_group("Combat")
@export var attack_range: float = 2.0
@export var attack_damage: int = 25
@export var attack_cooldown: float = 1.0

@export_group("Detection")
@export var sight_range: float = 10.0
@export var hearing_range: float = 5.0
@export var lose_target_time: float = 3.0
@export var use_fov: bool = true
@export_range(1.0, 179.0, 1.0) var fov_degrees: float = 110.0

@export_group("Health")
@export var max_health: int = 100

@export_group("Death")
@export var death_cleanup_delay: float = 0.0

@export_group("Debug")
@export var debug_enabled: bool = false
@export var show_state_label: bool = true

# Internal state
var current_state: EnemyState = EnemyState.IDLE
var previous_state: EnemyState = EnemyState.IDLE
var state_timer: float = 0.0
var health: int
var target_player: Node3D
var last_known_player_pos: Vector3
var attack_timer: float = 0.0
var lose_target_timer: float = 0.0

# Optional nodes - will be found automatically if they exist
@onready var navigation_agent: NavigationAgent3D = get_node_or_null("NavigationAgent3D")
@onready var state_label: Label3D = get_node_or_null("StateLabel")

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)

func _ready():
	# Initialize
	health = max_health
	add_to_group("enemies")
	# Also add to singular group for grapple/hook systems
	add_to_group("enemy")
	
	# Find player
	_find_player()
	
	# Setup navigation if available
	if navigation_agent:
		navigation_agent.max_speed = movement_speed
		navigation_agent.path_desired_distance = 1.0
		navigation_agent.target_desired_distance = 1.5
	
	# Setup debug label
	if state_label and show_state_label:
		state_label.visible = true
	elif state_label:
		state_label.visible = false
	
	# Call child setup
	setup_enemy()

func _physics_process(delta):
	if current_state == EnemyState.DEAD:
		return
	
	# Update timers
	state_timer += delta
	attack_timer = max(0.0, attack_timer - delta)
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Update player detection
	_update_player_detection(delta)
	
	# Execute current state
	_execute_state(delta)
	
	# Update debug display
	_update_debug_display()
	
	# Move the character
	move_and_slide()

# =============================================================================
# STATE MACHINE CORE
# =============================================================================

func change_state(new_state: EnemyState):
	if new_state == current_state:
		return
	
	# Exit current state
	_exit_state(current_state)
	
	# Change state
	previous_state = current_state
	current_state = new_state
	state_timer = 0.0
	
	# Enter new state
	_enter_state(new_state)
	
	if debug_enabled:
		print("[%s] State: %s -> %s" % [name, EnemyState.keys()[previous_state], EnemyState.keys()[current_state]])

func _execute_state(delta: float):
	match current_state:
		EnemyState.IDLE:
			do_idle(delta)
		EnemyState.PATROL:
			do_patrol(delta)
		EnemyState.CHASE:
			do_chase(delta)
		EnemyState.ATTACK:
			do_attack(delta)
		EnemyState.STUNNED:
			do_stunned(delta)
		EnemyState.DEAD:
			do_dead(delta)

func _enter_state(state: EnemyState):
	match state:
		EnemyState.IDLE:
			enter_idle()
		EnemyState.PATROL:
			enter_patrol()
		EnemyState.CHASE:
			enter_chase()
		EnemyState.ATTACK:
			enter_attack()
		EnemyState.STUNNED:
			enter_stunned()
		EnemyState.DEAD:
			enter_dead()

func _exit_state(state: EnemyState):
	match state:
		EnemyState.IDLE:
			exit_idle()
		EnemyState.PATROL:
			exit_patrol()
		EnemyState.CHASE:
			exit_chase()
		EnemyState.ATTACK:
			exit_attack()
		EnemyState.STUNNED:
			exit_stunned()
		EnemyState.DEAD:
			exit_dead()

# =============================================================================
# OVERRIDABLE STATE METHODS - Child classes customize these
# =============================================================================

# Called once when enemy is ready
func setup_enemy():
	pass

# IDLE state
func enter_idle(): pass
func do_idle(delta: float):
	velocity.x = move_toward(velocity.x, 0, 5.0)
	velocity.z = move_toward(velocity.z, 0, 5.0)
	
	# Basic behavior: switch to chase if player is visible
	if can_see_player():
		change_state(EnemyState.CHASE)
func exit_idle(): pass

# PATROL state  
func enter_patrol(): pass
func do_patrol(delta: float):
	# Default: just idle (child classes override for actual patrol)
	do_idle(delta)
func exit_patrol(): pass

# CHASE state
func enter_chase():
	if target_player:
		last_known_player_pos = target_player.global_position
func do_chase(delta: float):
	if not target_player:
		change_state(EnemyState.IDLE)
		return
	
	# Move toward player
	var target_pos = target_player.global_position if can_see_player() else last_known_player_pos
	move_toward_position(target_pos, movement_speed)
	face_position(target_pos, delta)
	
	# Check for attack range
	var distance = global_position.distance_to(target_player.global_position)
	if distance <= attack_range and attack_timer <= 0.0:
		change_state(EnemyState.ATTACK)
	
	# Check if lost player
	if not can_see_player():
		lose_target_timer += delta
		if lose_target_timer >= lose_target_time:
			change_state(EnemyState.IDLE)
	else:
		lose_target_timer = 0.0
		last_known_player_pos = target_player.global_position
func exit_chase(): pass

# ATTACK state
func enter_attack(): pass
func do_attack(delta: float):
	# Face target and stop moving
	velocity.x = 0
	velocity.z = 0
	
	if target_player:
		face_position(target_player.global_position, delta)
		
		# Perform attack
		if state_timer >= 0.3 and attack_timer <= 0.0:  # Attack after brief windup
			perform_attack()
			attack_timer = attack_cooldown
			change_state(EnemyState.CHASE)
	else:
		change_state(EnemyState.IDLE)
func exit_attack(): pass

# STUNNED state
func enter_stunned(): pass
func do_stunned(delta: float):
	velocity.x = move_toward(velocity.x, 0, 8.0)
	velocity.z = move_toward(velocity.z, 0, 8.0)
func exit_stunned(): pass

# DEAD state
func enter_dead():
	set_collision_layer_value(1, false)  # Remove from physics
	# Best-effort collision disable
	var collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	# Remove enemy grouping for gameplay systems
	if is_in_group("enemies"):
		remove_from_group("enemies")
	if is_in_group("enemy"):
		remove_from_group("enemy")
	# Schedule cleanup so corpses do not remain
	_schedule_despawn()
func do_dead(delta: float):
	velocity.x = move_toward(velocity.x, 0, 2.0)
	velocity.z = move_toward(velocity.z, 0, 2.0)
func exit_dead(): pass

# =============================================================================
# UTILITY METHODS
# =============================================================================

func _find_player():
	if debug_enabled:
		print("[%s] _find_player() called" % name)

	# Gather candidates from both common groups
	var candidates: Array = get_tree().get_nodes_in_group("player")
	if debug_enabled:
		print("[%s] Found %d nodes in 'player' group" % [name, candidates.size()])

	if candidates.is_empty():
		candidates = get_tree().get_nodes_in_group("players")
		if debug_enabled:
			print("[%s] Found %d nodes in 'players' group" % [name, candidates.size()])

	if candidates.is_empty():
		if debug_enabled:
			print("[%s] No players found in any group!" % name)
		return

	# Partition candidates to strongly prefer nodes that DIRECTLY own a PlayerState child.
	# This avoids targeting stationary container/root nodes that don't move with the player
	# (e.g., a pawn root whose body is set_as_top_level()).
	var direct_with_state: Array[Node3D] = []
	var parent_with_state: Array[Node3D] = []
	var any_nodes: Array[Node3D] = []

	for candidate in candidates:
		var node := candidate as Node
		if node is Node3D:
			any_nodes.append(node)
		if debug_enabled:
			print("[%s] Checking candidate: %s (groups: %s)" % [name, node.name, node.get_groups()])

		# Case 1: node directly owns a PlayerState child
		if node.get_node_or_null("PlayerState") and node is Node3D:
			direct_with_state.append(node)
			if debug_enabled:
				print("[%s] Candidate %s has direct PlayerState" % [name, node.name])
			continue

		# Case 1b: node has a descendant PlayerState; use its immediate Node3D owner
		var ps_desc: Node = node.find_child("PlayerState", true, false)
		if ps_desc and ps_desc.get_parent() is Node3D:
			var owner_n3d: Node3D = ps_desc.get_parent() as Node3D
			direct_with_state.append(owner_n3d)
			if debug_enabled:
				print("[%s] Candidate %s uses descendant PlayerState owner: %s" % [name, node.name, owner_n3d.name])
			continue

		# Case 2: parent owns a PlayerState child (legacy setups)
		var p: Node = node.get_parent()
		if p and p.get_node_or_null("PlayerState") and p is Node3D:
			var pn3d := p as Node3D
			if not pn3d in parent_with_state:
				parent_with_state.append(pn3d)
				if debug_enabled:
					print("[%s] Using parent %s which has PlayerState for candidate %s" % [name, p.name, node.name])

	# Choose the pool in priority order (GDScript ternary uses Python style).
	var pool: Array[Node3D]
	if direct_with_state.size() > 0:
		pool = direct_with_state
	elif parent_with_state.size() > 0:
		pool = parent_with_state
	else:
		pool = any_nodes

	var best: Node3D = null
	var best_distance: float = INF
	for n3d in pool:
		var dist := 0.0
		if is_inside_tree():
			dist = global_position.distance_to(n3d.global_position)
		if best == null or dist < best_distance:
			best = n3d
			best_distance = dist
			if debug_enabled:
				print("[%s] New best candidate: %s (distance: %.2f)" % [name, best.name, dist])

	if best:
		target_player = best
		if debug_enabled:
			print("[%s] Target player set to: %s" % [name, target_player.name])
	else:
		if debug_enabled:
			print("[%s] No valid player candidate found!" % name)

func _update_player_detection(delta: float):
	if not target_player:
		_find_player()

func can_see_player() -> bool:
	if not target_player:
		if debug_enabled:
			print("[%s] can_see_player: No target_player" % name)
		return false
	
	var distance = global_position.distance_to(target_player.global_position)
	if debug_enabled:
		print("[%s] can_see_player: Distance %.2f, sight_range %.2f" % [name, distance, sight_range])
	
	if distance > sight_range:
		if debug_enabled:
			print("[%s] can_see_player: Too far away" % name)
		return false
	
	# Optional horizontal FOV cone check
	if use_fov:
		var to_player := target_player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.0:
			var forward := -transform.basis.z
			forward.y = 0.0
			if forward.length() == 0.0:
				return false
			var cos_limit := cos(deg_to_rad(fov_degrees * 0.5))
			var dp := forward.normalized().dot(to_player.normalized())
			if dp < cos_limit:
				if debug_enabled:
					print("[%s] can_see_player: Outside FOV (dp=%.3f, cos_limit=%.3f)" % [name, dp, cos_limit])
				return false
	
	# Line of sight raycast (head-height)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1, 0),
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
			# If the ray hits a child collider of the player, walk up to check ancestry
			var n: Node = hit as Node
			while n and not can_see:
				if n == target_player:
					can_see = true
					break
				n = n.get_parent()
	
	if debug_enabled:
		print("[%s] can_see_player: Line of sight check - %s" % [name, "CLEAR" if can_see else "BLOCKED"])
	
	return can_see

func move_toward_position(target_pos: Vector3, speed: float):
	if navigation_agent and navigation_agent.is_navigation_finished() == false:
		# Use navigation
		navigation_agent.target_position = target_pos
		var next_pos = navigation_agent.get_next_path_position()
		var direction = (next_pos - global_position).normalized()
		direction.y = 0
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Direct movement
		var direction = (target_pos - global_position).normalized()
		direction.y = 0
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

func face_position(target_pos: Vector3, delta: float):
	var direction = (target_pos - global_position).normalized()
	direction.y = 0
	if direction.length() > 0:
		var target_transform = transform.looking_at(global_position + direction, Vector3.UP)
		transform = transform.interpolate_with(target_transform, turn_speed * delta)

func perform_attack():
	if not target_player:
		return
	
	var distance = global_position.distance_to(target_player.global_position)
	if distance <= attack_range:
		if target_player.has_method("take_damage"):
			target_player.take_damage(attack_damage)
		
		if debug_enabled:
			print("[%s] Attack! Damage: %d" % [name, attack_damage])

func take_damage(amount: int):
	if current_state == EnemyState.DEAD:
		return
	
	health -= amount
	
	if debug_enabled:
		print("[%s] Took %d damage, health: %d" % [name, amount, health])
	
	if health <= 0:
		change_state(EnemyState.DEAD)
	elif current_state != EnemyState.STUNNED:
		# Brief stun when taking damage
		change_state(EnemyState.STUNNED)
		await get_tree().create_timer(0.3).timeout
		if current_state == EnemyState.STUNNED:
			change_state(EnemyState.CHASE if target_player else EnemyState.IDLE)

# Instantly kill from a qualified melee backstab (e.g., Spy knife)
func take_backstab() -> void:
	if current_state == EnemyState.DEAD:
		return
	# Allow specialized enemies to override this for resistances or reactions
	health = 0
	change_state(EnemyState.DEAD)

func _update_debug_display():
	if state_label and show_state_label:
		state_label.text = EnemyState.keys()[current_state]
		# Color code states
		match current_state:
			EnemyState.IDLE:
				state_label.modulate = Color.WHITE
			EnemyState.PATROL:
				state_label.modulate = Color.BLUE
			EnemyState.CHASE:
				state_label.modulate = Color.YELLOW
			EnemyState.ATTACK:
				state_label.modulate = Color.RED
			EnemyState.STUNNED:
				state_label.modulate = Color.ORANGE
			EnemyState.DEAD:
				state_label.modulate = Color.GRAY

# -----------------------------------------------------------------------------
# Death cleanup helpers
# -----------------------------------------------------------------------------
func _schedule_despawn() -> void:
	if death_cleanup_delay <= 0.0:
		queue_free()
		return
	await get_tree().create_timer(death_cleanup_delay).timeout
	if is_instance_valid(self):
		queue_free()
