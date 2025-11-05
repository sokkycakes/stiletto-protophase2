extends CharacterBody3D
class_name QuakeKnightReference

# -----------------------------------------------------------------------------
#  Authentic Quake Knight implementation for Godot 4.4
#  Based on original knight.qc with proper state machine and behavior
#  Integrates with existing project systems while maintaining Quake authenticity
# -----------------------------------------------------------------------------

# Quake-authentic state machine
enum State {
	IDLE,      # Standing still, looking for player
	AWARE,     # Just noticed player, brief pause before action
	CHASE,     # Running toward player
	MELEE,     # In melee range, attacking
	PAIN,      # Taking damage, brief stun
	DEAD       # Dead, no longer active
}

# Quake-authentic parameters (based on original knight.qc)
@export var health:           int   = 75     # Original Quake Knight HP
@export var walk_speed:       float = 3.0    # Walking speed (ai_walk)
@export var run_speed:        float = 4.8    # Running/chase speed (ai_run)
@export var melee_range:      float = 1.8    # Sword reach (melee distance)
@export var damage:           int   = 25     # Damage per sword swing
@export var attack_cooldown:  float = 1.0    # Time between attacks
@export var sight_range:      float = 10.0   # Detection range
@export var lose_range:       float = 12.0   # Range at which to lose player

# Behavior timing (based on original Quake)
@export var aware_duration:   float = 0.7    # Time to stay aware before chasing
@export var pain_duration:    float = 0.6    # Time stunned when taking damage
@export var turn_speed:       float = 5.0    # Rotation speed toward player
@export var turn_threshold:   float = 0.1    # Rotation accuracy threshold

# Integration with project systems
@export var player_path:      NodePath       # Manual player reference
@export var use_navigation:   bool = true    # Use NavigationAgent3D
@export var debug_enabled:    bool = false   # Debug output

# Animation system integration
@export var animation_player_path: NodePath  # Path to AnimationPlayer node
@onready var animation_player: AnimationPlayer
var _has_animations: bool = false

# Quake-authentic animation names (based on original knight.qc)
var _anim_stand: String = "stand"
var _anim_walk: String = "walk"
var _anim_run: String = "run"
var _anim_attack: String = "attack"
var _anim_pain: String = "pain"
var _anim_death: String = "death"

# Internal state
var _state: State = State.IDLE
var _previous_state: State = State.IDLE
var _player: Node3D
var _can_attack: bool = true
var _aware_timer: float = 0.0
var _pain_timer: float = 0.0
var _player_not_found_warning: bool = false

# Node references
@onready var _nav: NavigationAgent3D
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Sound effects - Quake-authentic audio resources
@export var attack_sounds: Array[AudioStream] = []
@export var pain_sound: AudioStream
@export var death_sound: AudioStream
@export var sight_sound: AudioStream
@export var idle_sound: AudioStream

# Audio system
@onready var audio_player: AudioStreamPlayer3D
var _audio_players: Array[AudioStreamPlayer3D] = []
var _max_audio_players: int = 3

# -----------------------------------------------------------------------------
# Initialization
# -----------------------------------------------------------------------------
func _ready() -> void:
	# Add to enemy group for project integration
	add_to_group("enemy")

	# Setup navigation if available
	if has_node("NavigationAgent3D"):
		_nav = $NavigationAgent3D
	else:
		_nav = null

	# Setup audio system
	_setup_audio_system()

	# Setup animation system
	_setup_animation_system()

	# Find player reference
	_resolve_player()

	# Setup attack system integration
	setup_attack_system()

	# Initialize state
	_change_state(State.IDLE)

	if debug_enabled:
		print("[Knight] Initialized - Health: ", health, " State: IDLE")

func _resolve_player() -> void:
	# Try multiple methods to find player
	if player_path != NodePath() and has_node(player_path):
		_player = get_node(player_path)
	else:
		# Look for player in groups
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			_player = players[0]
		else:
			# Try common player node names
			_player = get_tree().get_first_node_in_group("player")
			if not _player:
				_player = get_node_or_null("/root/Player")
			if not _player:
				_player = get_node_or_null("../Player")

	# Connect to player death signals if available
	if _player:
		_connect_player_signals()
		if debug_enabled:
			print("[Knight] Player found: ", _player.name)
	else:
		if not _player_not_found_warning:
			print("[Knight] Warning: No player found!")
			_player_not_found_warning = true

func _connect_player_signals() -> void:
	# Try to connect to player death signals for proper cleanup
	if _player.has_node("PlayerState"):
		var ps = _player.get_node("PlayerState")
		if ps and ps.has_signal("player_died"):
			if not ps.player_died.is_connected(_on_player_died):
				ps.player_died.connect(_on_player_died)

	# Fallback: health node
	var health_node = _player.get_node_or_null("Health")
	if health_node and health_node.has_signal("died"):
		if not health_node.died.is_connected(_on_player_died):
			health_node.died.connect(_on_player_died)

func _on_player_died() -> void:
	if debug_enabled:
		print("[Knight] Player died, returning to idle")
	_change_state(State.IDLE)

# -----------------------------------------------------------------------------
# Main physics loop - Quake-authentic state machine
# -----------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	# Dead knights don't move
	if _state == State.DEAD:
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Ensure we have a valid player (supports multiplayer)
	if not is_instance_valid(_player):
		_resolve_player()
		if not is_instance_valid(_player):
			if debug_enabled and not _player_not_found_warning:
				print("[Knight] Cannot find player. Ensure player has 'player' group or player_path is set.")
				_player_not_found_warning = true
			_stop_movement()
			move_and_slide()
			return

	# In multiplayer, periodically check for closer players
	if get_tree().get_nodes_in_group("player").size() > 1:
		_update_player_target()

	# Update state machine
	_update_state_machine(delta)

	# Apply movement
	move_and_slide()

# -----------------------------------------------------------------------------
# Quake-authentic state machine implementation
# -----------------------------------------------------------------------------
func _update_state_machine(delta: float) -> void:
	var dist := global_position.distance_to(_player.global_position)

	match _state:
		State.IDLE:
			_process_idle_state(delta, dist)
		State.AWARE:
			_process_aware_state(delta, dist)
		State.CHASE:
			_process_chase_state(delta, dist)
		State.MELEE:
			_process_melee_state(delta, dist)
		State.PAIN:
			_process_pain_state(delta, dist)

func _process_idle_state(delta: float, dist: float) -> void:
	_stop_movement()
	_play_animation(_anim_stand)

	# Quake behavior: detect player within sight range
	if dist < sight_range and _can_see_player():
		_play_sight_sound()
		_change_state(State.AWARE)

func _process_aware_state(delta: float, dist: float) -> void:
	_stop_movement()
	_face_player(delta)
	_play_animation(_anim_stand)

	# Count down awareness timer
	_aware_timer += delta

	# After awareness period, decide next action
	if _aware_timer >= aware_duration:
		if dist <= melee_range:
			_change_state(State.MELEE)
		elif dist < lose_range:
			_change_state(State.CHASE)
		else:
			_change_state(State.IDLE)

func _process_chase_state(delta: float, dist: float) -> void:
	# Check if we should transition to other states
	if dist <= melee_range:
		_change_state(State.MELEE)
	elif dist > lose_range:
		_change_state(State.IDLE)
	else:
		# Chase the player
		_chase_player()
		_face_player(delta)

		# Use run animation when moving fast, walk when slower
		var speed = velocity.length()
		if speed > run_speed * 0.7:
			_play_animation(_anim_run)
		elif speed > walk_speed * 0.5:
			_play_animation(_anim_walk)
		else:
			_play_animation(_anim_stand)

func _process_melee_state(delta: float, dist: float) -> void:
	_stop_movement()
	_face_player(delta)
	_play_animation(_anim_stand)

	# Check if player moved out of range
	if dist > melee_range:
		_change_state(State.CHASE)
	elif _can_attack and _is_facing_player():
		_perform_attack()

func _process_pain_state(delta: float, dist: float) -> void:
	_stop_movement()

	# Play pain animation once when entering state
	if _previous_state != State.PAIN:
		_play_animation(_anim_pain, true)

	# Count down pain timer
	_pain_timer += delta

	# Return to appropriate state after pain
	if _pain_timer >= pain_duration:
		if dist <= melee_range:
			_change_state(State.MELEE)
		elif dist < lose_range:
			_change_state(State.CHASE)
		else:
			_change_state(State.IDLE)

# -----------------------------------------------------------------------------
# State management
# -----------------------------------------------------------------------------
func _change_state(new_state: State) -> void:
	if _state == new_state:
		return

	var old_state = _state
	_previous_state = _state
	_state = new_state

	# Reset state-specific timers
	match new_state:
		State.AWARE:
			_aware_timer = 0.0
		State.PAIN:
			_pain_timer = 0.0

	if debug_enabled:
		print("[Knight] State: ", State.keys()[old_state], " -> ", State.keys()[new_state])

# -----------------------------------------------------------------------------
# Movement and rotation helpers
# -----------------------------------------------------------------------------
func _stop_movement() -> void:
	velocity.x = move_toward(velocity.x, 0, 0.1)
	velocity.z = move_toward(velocity.z, 0, 0.1)

func _is_facing_player() -> bool:
	if not is_instance_valid(_player):
		return false

	var target_dir = (_player.global_position - global_position).normalized()
	target_dir.y = 0
	var forward_dir = -transform.basis.z.normalized()

	var dot_product = forward_dir.dot(target_dir)
	return dot_product > (1.0 - turn_threshold)

func _face_player(delta: float) -> void:
	if not is_instance_valid(_player):
		return

	var target_dir = (_player.global_position - global_position).normalized()
	target_dir.y = 0  # Keep rotation only on Y axis

	if target_dir.length() > 0:
		var target_transform = transform.looking_at(global_position + target_dir, Vector3.UP)
		transform = transform.interpolate_with(target_transform, turn_speed * delta)

func _chase_player() -> void:
	var dir: Vector3

	# Use navigation if available and target is reachable
	if use_navigation and _nav and _nav.is_target_reachable():
		_nav.target_position = _player.global_position
		dir = (_nav.get_next_path_position() - global_position).normalized()
	else:
		# Direct movement toward player
		dir = (_player.global_position - global_position).normalized()

	dir.y = 0.0

	# Apply movement with Quake-style acceleration
	velocity = velocity.lerp(dir * run_speed, 0.1)

func _can_see_player() -> bool:
	if not is_instance_valid(_player):
		return false

	# Simple line-of-sight check (can be enhanced with raycasting)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.5,
		_player.global_position + Vector3.UP * 0.5
	)
	query.exclude = [self]

	var result = space_state.intersect_ray(query)
	return result.is_empty() or result.collider == _player

# -----------------------------------------------------------------------------
# Combat system - Integrated with project attack system
# -----------------------------------------------------------------------------
func _perform_attack() -> void:
	_can_attack = false

	if debug_enabled:
		print("[Knight] Performing sword attack!")

	# Play attack animation and sound
	_play_animation(_anim_attack, true)
	_play_attack_sound()

	# Use project's attack system if available
	if has_node("AttackSystem"):
		var attack_system = $AttackSystem
		if attack_system.has_method("perform_attack"):
			attack_system.perform_attack()
		else:
			# Fallback to direct damage
			_damage_player_direct()
	else:
		# Fallback to direct damage
		_damage_player_direct()

	# Start attack cooldown
	await get_tree().create_timer(attack_cooldown).timeout
	_can_attack = true

func _damage_player_direct() -> void:
	if not is_instance_valid(_player):
		return

	# Try different damage methods for compatibility
	if _player.has_method("take_damage"):
		_player.take_damage(damage)
	elif _player.has_method("take_hit"):
		_player.take_hit()
	elif _player.has_method("hurt"):
		_player.hurt(damage)
	else:
		if debug_enabled:
			print("[Knight] Warning: Player has no damage method")

	# Apply knockback effect
	_apply_knockback()

func _apply_knockback() -> void:
	if not is_instance_valid(_player) or not _player is CharacterBody3D:
		return

	var player_body = _player as CharacterBody3D
	var knock_dir := (_player.global_position - global_position).normalized()
	knock_dir.y = 0

	# Apply Quake-style knockback
	player_body.velocity += knock_dir * 6.0

# -----------------------------------------------------------------------------
# Integration with BaseEnemyAttackSystem
# -----------------------------------------------------------------------------
func setup_attack_system() -> void:
	# Create and configure attack system if it doesn't exist
	if not has_node("AttackSystem"):
		var attack_system_scene = preload("res://scenes/enemy/base_enemy_attack_system_lite.gd")
		var attack_system = Node.new()
		attack_system.set_script(attack_system_scene)
		attack_system.name = "AttackSystem"
		add_child(attack_system)

		# Configure attack system for knight
		if attack_system.has_method("setup"):
			attack_system.setup(damage, melee_range, attack_cooldown)

		# Connect signals if available
		if attack_system.has_signal("attack_hit"):
			attack_system.attack_hit.connect(_on_attack_hit)
		if attack_system.has_signal("attack_missed"):
			attack_system.attack_missed.connect(_on_attack_missed)

func _on_attack_hit(target: Node) -> void:
	if debug_enabled:
		print("[Knight] Attack hit: ", target.name)

	# Play hit sound
	_play_attack_sound()

func _on_attack_missed() -> void:
	if debug_enabled:
		print("[Knight] Attack missed")

# -----------------------------------------------------------------------------
# BaseEnemyAILite compatibility methods
# -----------------------------------------------------------------------------
func get_player() -> Node3D:
	return _player

func get_current_state() -> State:
	return _state

func is_player_in_range() -> bool:
	if not is_instance_valid(_player):
		return false
	return global_position.distance_to(_player.global_position) <= melee_range

func get_distance_to_player() -> float:
	if not is_instance_valid(_player):
		return INF
	return global_position.distance_to(_player.global_position)

# -----------------------------------------------------------------------------
# Audio system setup and management
# -----------------------------------------------------------------------------
func _setup_audio_system() -> void:
	# Create main audio player if it doesn't exist
	if not has_node("AudioStreamPlayer3D"):
		audio_player = AudioStreamPlayer3D.new()
		audio_player.name = "AudioStreamPlayer3D"
		add_child(audio_player)

		# Configure 3D audio settings for knight
		audio_player.max_distance = 20.0
		audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		audio_player.unit_size = 1.0
	else:
		audio_player = $AudioStreamPlayer3D

	# Create additional audio players for overlapping sounds
	for i in range(_max_audio_players - 1):
		var extra_player = AudioStreamPlayer3D.new()
		extra_player.name = "AudioStreamPlayer3D_" + str(i + 2)
		extra_player.max_distance = 20.0
		extra_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		extra_player.unit_size = 1.0
		add_child(extra_player)
		_audio_players.append(extra_player)

	_audio_players.append(audio_player)

func _setup_animation_system() -> void:
	# Setup animation player if available
	if animation_player_path != NodePath():
		animation_player = get_node_or_null(animation_player_path)
	elif has_node("AnimationPlayer"):
		animation_player = $AnimationPlayer

	if animation_player:
		_has_animations = true
		if debug_enabled:
			print("[Knight] Animation system initialized")
			print("[Knight] Available animations: ", animation_player.get_animation_list())
	else:
		_has_animations = false
		if debug_enabled:
			print("[Knight] No animation system found")

func _play_animation(anim_name: String, force: bool = false) -> void:
	if not _has_animations or not animation_player:
		return

	# Don't interrupt important animations unless forced
	if not force and animation_player.is_playing():
		var current = animation_player.current_animation
		if current in [_anim_attack, _anim_pain, _anim_death]:
			return

	if animation_player.has_animation(anim_name):
		animation_player.play(anim_name)
		if debug_enabled:
			print("[Knight] Playing animation: ", anim_name)
	elif debug_enabled:
		print("[Knight] Animation not found: ", anim_name)

func _get_available_audio_player() -> AudioStreamPlayer3D:
	# Find an available audio player
	for player in _audio_players:
		if not player.playing:
			return player

	# If all are busy, use the main one (will interrupt current sound)
	return audio_player

# -----------------------------------------------------------------------------
# Sound effects - Quake-authentic audio implementation
# -----------------------------------------------------------------------------
func _play_attack_sound() -> void:
	if attack_sounds.size() == 0:
		if debug_enabled:
			print("[Knight] No attack sounds configured")
		return

	# Random attack sound like original knight.qc
	var sound = attack_sounds[randi() % attack_sounds.size()]
	var player = _get_available_audio_player()
	player.stream = sound
	player.play()

	if debug_enabled:
		print("[Knight] Playing attack sound")

func _play_sight_sound() -> void:
	if not sight_sound:
		if debug_enabled:
			print("[Knight] No sight sound configured")
		return

	var player = _get_available_audio_player()
	player.stream = sight_sound
	player.play()

	if debug_enabled:
		print("[Knight] Playing sight sound")

func _play_pain_sound() -> void:
	if not pain_sound:
		if debug_enabled:
			print("[Knight] No pain sound configured")
		return

	var player = _get_available_audio_player()
	player.stream = pain_sound
	player.play()

	if debug_enabled:
		print("[Knight] Playing pain sound")

func _play_death_sound() -> void:
	if not death_sound:
		if debug_enabled:
			print("[Knight] No death sound configured")
		return

	var player = _get_available_audio_player()
	player.stream = death_sound
	player.play()

	if debug_enabled:
		print("[Knight] Playing death sound")

func _play_idle_sound() -> void:
	if not idle_sound:
		return

	var player = _get_available_audio_player()
	player.stream = idle_sound
	player.play()

	if debug_enabled:
		print("[Knight] Playing idle sound")

# -----------------------------------------------------------------------------
# Damage and death system - Quake-authentic behavior
# -----------------------------------------------------------------------------
func take_damage(amount: int) -> void:
	if _state == State.DEAD:
		return

	health -= amount

	if debug_enabled:
		print("[Knight] Took ", amount, " damage. Health: ", health)

	if health <= 0:
		_die()
	else:
		_enter_pain_state()

func _enter_pain_state() -> void:
	# Don't interrupt pain state with more pain
	if _state == State.PAIN:
		return

	_play_pain_sound()
	_change_state(State.PAIN)

	if debug_enabled:
		print("[Knight] Entering pain state")

func _die() -> void:
	_change_state(State.DEAD)
	_play_death_sound()
	_play_animation(_anim_death, true)

	# Disable collision
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", true)

	# Notify GameMaster for kill statistics (project integration)
	for gm in get_tree().get_nodes_in_group("gamemaster"):
		if gm.has_method("register_kill"):
			gm.register_kill(1)

	if debug_enabled:
		print("[Knight] Died. Cleaning up...")

	# Wait for death animation to complete, or use default time
	var death_time = 2.0
	if _has_animations and animation_player and animation_player.has_animation(_anim_death):
		var anim_length = animation_player.get_animation(_anim_death).length
		death_time = max(anim_length, 1.0)  # At least 1 second

	await get_tree().create_timer(death_time).timeout
	queue_free()

# -----------------------------------------------------------------------------
# Alternative integration approach - extend BaseEnemyAILite
# -----------------------------------------------------------------------------
# Uncomment this section if you want to extend BaseEnemyAILite instead:
#
# extends BaseEnemyAILite
# class_name QuakeKnightIntegrated
#
# # Override BaseEnemyAILite methods with Quake-authentic behavior
# func _process_ai_state(delta: float) -> void:
#     # Use our Quake state machine instead of base class
#     _update_state_machine(delta)
#
# func _should_chase_player() -> bool:
#     # Use Quake detection logic
#     var dist = global_position.distance_to(player.global_position)
#     return dist < sight_range and _can_see_player()
#
# func _get_chase_speed() -> float:
#     # Use Quake run speed
#     return run_speed

# -----------------------------------------------------------------------------
# Debug and utility methods
# -----------------------------------------------------------------------------
func get_debug_info() -> Dictionary:
	return {
		"state": State.keys()[_state],
		"health": health,
		"distance_to_player": global_position.distance_to(_player.global_position) if _player else -1,
		"can_attack": _can_attack,
		"aware_timer": _aware_timer,
		"pain_timer": _pain_timer,
		"facing_player": _is_facing_player(),
		"can_see_player": _can_see_player()
	}

func force_state(new_state: State) -> void:
	"""Force knight into a specific state (for debugging/testing)"""
	_change_state(new_state)

func reset_knight() -> void:
	"""Reset knight to initial state"""
	health = 75
	_change_state(State.IDLE)
	_can_attack = true
	_aware_timer = 0.0
	_pain_timer = 0.0
	velocity = Vector3.ZERO

# -----------------------------------------------------------------------------
# GameMaster integration - Overwhelm system support
# -----------------------------------------------------------------------------
func boost_speed(multiplier: float) -> void:
	"""Called by GameMaster during overwhelm state"""
	if debug_enabled:
		print("[Knight] Speed boosted by ", multiplier, "x for overwhelm")

	# Apply speed boost to movement speeds
	var original_walk = walk_speed
	var original_run = run_speed

	walk_speed *= multiplier
	run_speed *= multiplier

	# Store original speeds for potential restoration
	if not has_meta("original_walk_speed"):
		set_meta("original_walk_speed", original_walk)
		set_meta("original_run_speed", original_run)

	# Force into chase state if not already aggressive
	if _state in [State.IDLE, State.AWARE]:
		_change_state(State.CHASE)

func restore_normal_speed() -> void:
	"""Restore original speeds after overwhelm ends"""
	if has_meta("original_walk_speed"):
		walk_speed = get_meta("original_walk_speed")
		run_speed = get_meta("original_run_speed")
		remove_meta("original_walk_speed")
		remove_meta("original_run_speed")

		if debug_enabled:
			print("[Knight] Speed restored to normal")

# -----------------------------------------------------------------------------
# Enemy spawner integration
# -----------------------------------------------------------------------------
func set_spawner_reference(spawner: Node) -> void:
	"""Called by enemy spawners to track this knight"""
	set_meta("spawner", spawner)

func get_spawner_reference() -> Node:
	"""Get the spawner that created this knight"""
	return get_meta("spawner", null)

# -----------------------------------------------------------------------------
# Player group integration
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Multiplayer integration
# -----------------------------------------------------------------------------
func _get_closest_player() -> Node3D:
	"""Find closest player in multiplayer scenarios"""
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null

	var closest_player = null
	var closest_distance = INF

	for player in players:
		if not is_instance_valid(player):
			continue

		var distance = global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_player = player

	return closest_player

func _update_player_target() -> void:
	"""Update player target for multiplayer support"""
	var new_player = _get_closest_player()
	if new_player != _player:
		_player = new_player
		if debug_enabled and _player:
			print("[Knight] Switched target to player: ", _player.name)
