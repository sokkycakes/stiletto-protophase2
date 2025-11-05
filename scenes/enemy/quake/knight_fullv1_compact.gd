extends CharacterBody3D
class_name QuakeKnightCompact

enum State { IDLE, AWARE, CHASE, MELEE, ATTACKING, PAIN, STUNNED, DEAD }
@export var health: int = 75
@export var run_speed: float = 4.8
@export var melee_range: float = 1.8
@export var damage: int = 25
@export var attack_cooldown: float = 1.0
@export var player_path: NodePath
@export var debug_enabled: bool = false
@export var turn_speed: float = 5.0
@export var turn_threshold: float = 0.1
@export var aware_duration: float = 0.7
@export var launch_force: float = 11.0
@export var launch_angle: float = 45.0
@export var aware_particles: GPUParticles3D
@export var path_refresh: float = 0.25
@export var active_distance: float = 40.0
@export var ignore_enemy_collisions: bool = true
@export var enemy_layer: int = 4
@export var ai_refresh: float = 0.05
var _state: State = State.IDLE
var _player: Node3D
var _can_attack: bool = true
var _aware_timer: float = 0.0
var _particles_emitted: bool = false
var _stun_timer: float = 0.0
var _force_chase: bool = false
var _path_timer: float = 0.0
var _nav_target_reachable: bool = false
var _unreachable_attempts: int = 0
var _ai_timer: float = 0.0
var _player_not_found_warning: bool = false
const MAX_UNREACHABLE_ATTEMPTS := 3
@onready var _nav: NavigationAgent3D = get_node_or_null("NavigationAgent3D")
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") * 1.5

class KnightAIProxy extends Node:
	enum States { IDLE, AWARE, CHASE }
	var awareness_threshold: float = 1.0
	var current_awareness: float = 1.0
	var player_in_range: bool = true
	var player: Node3D
	func change_state(state): pass
	func get_awareness_percentage(): return current_awareness

func _ready() -> void:
	add_to_group("enemy")
	if not has_node("AI"):
		var proxy := KnightAIProxy.new()
		proxy.name = "AI"
		add_child(proxy)
		proxy.player = _player
	if _nav: _nav.avoidance_enabled = false
	if ignore_enemy_collisions:
		collision_layer = 1 << (enemy_layer - 1)
		for i in range(20): set_collision_mask_value(i + 1, i != (enemy_layer - 1))
	_resolve_player()
	_path_timer = randf_range(0.0, path_refresh)
	_ai_timer = randf_range(0.0, ai_refresh)

func _resolve_player() -> void:
	_player = get_node_or_null(player_path) or (get_tree().get_nodes_in_group("player").front() if get_tree().get_nodes_in_group("player").size() > 0 else null)

func _physics_process(delta: float) -> void:
	if _state == State.DEAD: return
	if not is_on_floor(): velocity.y -= _gravity * delta
	if not is_instance_valid(_player):
		_resolve_player()
		if not is_instance_valid(_player):
			if debug_enabled and not _player_not_found_warning: print("[Knight] Cannot find player. Knight is idle.")
			velocity.x = move_toward(velocity.x, 0, 0.1); velocity.z = move_toward(velocity.z, 0, 0.1); move_and_slide(); return
	var dist := global_position.distance_to(_player.global_position)
	if dist > active_distance and not _force_chase: velocity.x = move_toward(velocity.x, 0, 0.1); velocity.z = move_toward(velocity.z, 0, 0.1); move_and_slide(); return
	_ai_timer -= delta
	var ai_due := _ai_timer <= 0.0
	if ai_due: _ai_timer += ai_refresh
	match _state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0, 0.1); velocity.z = move_toward(velocity.z, 0, 0.1)
			if dist < 10.0: _state = State.AWARE; _aware_timer = 0.0; _particles_emitted = false
		State.AWARE:
			velocity.x = move_toward(velocity.x, 0, 0.1); velocity.z = move_toward(velocity.z, 0, 0.1); _face_player(delta)
			if not _particles_emitted and aware_particles: aware_particles.restart(); _particles_emitted = true
			_aware_timer += delta
			if _aware_timer >= aware_duration: _state = State.CHASE
		State.CHASE:
			if dist <= melee_range: _state = State.MELEE
			elif dist > 10.0 and not _force_chase: _state = State.IDLE
			else: _chase(delta); if ai_due: _face_player(delta)
		State.MELEE:
			velocity.x = move_toward(velocity.x, 0, 0.1); velocity.z = move_toward(velocity.z, 0, 0.1); _face_player(delta)
			if dist > melee_range: _state = State.CHASE
			elif _can_attack and ai_due: _state = State.ATTACKING; _swing_sword()
		State.ATTACKING: velocity.x = 0; velocity.z = 0
		State.PAIN: velocity.x = move_toward(velocity.x, 0, 0.1); velocity.z = move_toward(velocity.z, 0, 0.1)
		State.STUNNED:
			if is_on_floor(): velocity.x = move_toward(velocity.x, 0, 8.0); velocity.z = move_toward(velocity.z, 0, 8.0)
			_stun_timer -= delta; if _stun_timer <= 0: _state = State.CHASE
	move_and_slide()

func _is_facing_player() -> bool:
	if not is_instance_valid(_player): return false
	var target_dir = (_player.global_position - global_position).normalized(); target_dir.y = 0
	return -transform.basis.z.normalized().dot(target_dir) > (1.0 - turn_threshold)

func _face_player(delta: float) -> void:
	if not is_instance_valid(_player): return
	var target_dir = (_player.global_position - global_position).normalized(); target_dir.y = 0
	if target_dir.length() > 0: transform = transform.interpolate_with(transform.looking_at(global_position + target_dir, Vector3.UP), turn_speed * delta)

func _chase(delta: float) -> void:
	var dir: Vector3 = Vector3.ZERO
	var should_move: bool = false
	
	if _nav:
		_path_timer -= delta
		if _path_timer <= 0.0:
			_path_timer = path_refresh; _nav.target_position = _player.global_position; _nav_target_reachable = _nav.is_target_reachable()
			if not _nav_target_reachable:
				_unreachable_attempts += 1
				if _unreachable_attempts >= MAX_UNREACHABLE_ATTEMPTS: _nav = null; print_debug("[Knight] Navigation disabled – unreachable target")
			else: _unreachable_attempts = 0
		
		# Only move if we have a valid navigation path
		if _nav_target_reachable and not _nav.is_navigation_finished():
			var next_pos = _nav.get_next_path_position()
			if next_pos != Vector3.ZERO:
				dir = (next_pos - global_position).normalized()
				should_move = true
		else:
			# If navigation is finished or target unreachable, stop moving
			should_move = false
	else:
		# No navigation agent, use direct path but be more conservative
		dir = (_player.global_position - global_position).normalized()
		# Only move if we're not too close to walls (simple distance check)
		var distance_to_player = global_position.distance_to(_player.global_position)
		if distance_to_player > melee_range * 1.5:  # Give some buffer
			should_move = true
	
	dir.y = 0.0
	if should_move:
		velocity = velocity.lerp(dir * run_speed, 0.1)
	else:
		# Stop moving if no valid path or too close to obstacles
		velocity.x = move_toward(velocity.x, 0, 0.1)
		velocity.z = move_toward(velocity.z, 0, 0.1)

func _swing_sword() -> void:
	_can_attack = false
	if debug_enabled: print("[Knight] Slash!")
	if _player.has_method("take_damage"): _player.take_damage(damage)
	if _player is CharacterBody3D:
		var launch_direction = (_player.global_position - global_position).normalized(); launch_direction.y = 0
		var launch_vector = launch_direction * launch_force; launch_vector.y = sin(deg_to_rad(launch_angle)) * launch_force
		(_player as CharacterBody3D).velocity = launch_vector
	var player_state = _player.get_node_or_null("PlayerState")
	if player_state and player_state.has_method("take_hit"): player_state.take_hit()
	await get_tree().create_timer(0.7).timeout
	await get_tree().create_timer(attack_cooldown).timeout
	_can_attack = true
	if _state == State.ATTACKING: _state = State.MELEE

func take_damage(amount: int) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	if health <= 0:
		_die()
	else:
		_pain()

func apply_stun(duration: float) -> void:
	if _state != State.DEAD:
		_state = State.STUNNED
		_stun_timer = duration

func _pain() -> void:
	_state = State.PAIN
	if debug_enabled: print("[Knight] Pain!")
	await get_tree().create_timer(0.2).timeout
	if _state != State.DEAD: _state = State.CHASE

func _die() -> void:
	_state = State.DEAD
	if debug_enabled: print("[Knight] Dead.")
	queue_free()

func boost_speed(multiplier: float):
	run_speed *= multiplier; _force_chase = true
	if _state != State.DEAD: _state = State.CHASE 
