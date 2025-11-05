extends "res://resource/scripts/weapons/base_weapon.gd"
class_name Knife

# Basic melee/backstab config
@export var melee_range: float = 2.2
@export var melee_radius: float = 0.25
@export var damage_normal: int = 40
@export var damage_backstab_multiplier: float = 2.0
@export var fire_cooldown: float = 0.5

# Optional: collision mask for hittables
@export var collide_with_areas: bool = true
@export var collide_with_bodies: bool = true

@export var backstab_speed_boost: float = 5.0  # Units/sec added to velocity
@export var backstab_boost_duration: float = 1.5

# Player reference - set this in the inspector
@export var player_node: Node3D

# Speed boost visual feedback
@export var speed_boost_color: Color = Color(0.5, 0.8, 1.0, 1.0)  # Light blue
@export var speedometer_path: NodePath = NodePath("../../../../../HUD/Control/Center/speedometer")

# Backstab feedback animations
@export var idle_animation_name: String = "idle"
@export var backstab_ready_animation_name: String = "backstab_ready"

# Backstab pitch stacking
@export var backstab_pitch_step: float = 0.05	# added to pitch_scale per stack
@export var backstab_pitch_max_stacks: int = 8
@export var backstab_pitch_window: float = 2.0	# seconds to keep/decay stacks

# ===== THROWABLE KNIFE CONFIGURATION =====
@export_group("Throwable Knife (Alt Fire)")
@export var throwable_knife_scene: PackedScene  # Scene containing the throwable knife projectile
@export var throw_velocity: float = 30.0  # Speed of thrown knife
@export var throw_cooldown: float = 1.0  # Cooldown between throws
@export var throw_arc: float = 0.0  # Upward arc angle in degrees (0 = straight)
@export var max_throw_knives: int = 3  # Maximum number of knives that can be thrown
@export var knife_recharge_time: float = 5.0  # Time to recharge one knife
@export var throw_sound: AudioStream  # Sound when throwing knife
@export var alt_fire_action: String = "bigshot"  # Input action for alt fire
@export var debug_logging: bool = false

# Internal boost state
var _speed_boost_active: bool = false
var _boost_timer: Timer
var _original_speeds: Dictionary = {}
var _speedometer: Label = null
var _animation_player: AnimationPlayer = null
var _backstab_pitch_stacks: int = 0
var _backstab_pitch_timer: Timer
var _backstab_player: AudioStreamPlayer

# Internal
var _can_attack: bool = true
var _cooldown_timer: Timer
var _weapon_manager: WeaponManager = null
var _camera: Camera3D = null
@export var swing_hit_delay: float = 0.25
var _swing_in_progress: bool = false
@export var backstab_hit_sound: AudioStream
@export var backstab_crit_sound: AudioStream

# Throwable knife internal state
var _thrown_knives_count: int = 0  # Current number of knives available to throw
var _can_throw: bool = true
var _throw_cooldown_timer: Timer
var _knife_recharge_timer: Timer

func _ready() -> void:
	# This melee weapon doesn't use ammo
	clip_size = 1
	ammo_in_clip = 1
	fire_rate = fire_cooldown
	reload_time = 0.0
	
	# Ensure BaseWeapon timers (_fire_timer, _reload_timer) are created
	super._ready()
	
	_cooldown_timer = Timer.new()
	_cooldown_timer.one_shot = true
	_cooldown_timer.timeout.connect(func(): _can_attack = true)
	add_child(_cooldown_timer)
	
	# Cache camera from parent WeaponManager
	_weapon_manager = get_parent() as WeaponManager
	if _weapon_manager:
		_camera = _weapon_manager.camera
	
	# Create boost timer
	_boost_timer = Timer.new()
	_boost_timer.wait_time = backstab_boost_duration
	_boost_timer.one_shot = true
	_boost_timer.timeout.connect(_end_speed_boost)
	add_child(_boost_timer)
	
	# Create backstab pitch timer
	_backstab_pitch_timer = Timer.new()
	_backstab_pitch_timer.wait_time = backstab_pitch_window
	_backstab_pitch_timer.one_shot = true
	_backstab_pitch_timer.timeout.connect(func(): _backstab_pitch_stacks = 0)
	add_child(_backstab_pitch_timer)

	# Create dedicated audio player for backstab pitch variations
	_backstab_player = AudioStreamPlayer.new()
	_backstab_player.bus = audio_bus
	add_child(_backstab_player)
	
	# Cache speedometer reference
	_speedometer = get_node_or_null(speedometer_path) as Label
	if _speedometer == null:
		push_warning("Speedometer not found at path: %s" % [str(speedometer_path)])
	
	# Cache animation player reference
	_animation_player = get_node_or_null("AnimationPlayer")
	if _animation_player == null:
		push_warning("AnimationPlayer not found on knife")
	else:
		# Start with idle animation
		_animation_player.play(idle_animation_name)
	
	# Initialize throwable knife system
	_init_throwable_knife_system()

func _process(_delta: float) -> void:
	if not _animation_player:
		return
	
	# Check if we're in backstab range
	var backstab_ready = _check_backstab_ready()
	
	# Play appropriate animation
	if backstab_ready:
		if _animation_player.current_animation != backstab_ready_animation_name:
			_animation_player.play(backstab_ready_animation_name)
	else:
		if _animation_player.current_animation != idle_animation_name:
			_animation_player.play(idle_animation_name)

func shoot() -> void:
	if debug_logging:
		print("Knife shoot() called")
	if not _can_attack or _swing_in_progress:
		if debug_logging:
			print("Knife shoot() blocked - can_attack: %s swing_in_progress: %s" % [_can_attack, _swing_in_progress])
		return
	_can_attack = false
	_swing_in_progress = true
	_cooldown_timer.start(fire_cooldown)

	# Swing sound feedback
	if swing_sound:
		_play_sound(swing_sound)

	# Delay before applying the hit logic
	await get_tree().create_timer(swing_hit_delay).timeout
	if not is_inside_tree():
		_swing_in_progress = false
		return

	var hit: Dictionary = _melee_trace()
	if hit.is_empty():
		# Miss feedback for melee
		if miss_sound:
			_play_sound(miss_sound)
		emit_signal("fired")
		_swing_in_progress = false
		return

	var target: Object = hit.get("collider", null)
	if target == null:
		if miss_sound:
			_play_sound(miss_sound)
		emit_signal("fired")
		_swing_in_progress = false
		return

	var backstab: bool = false
	if target.has_method("take_damage"):
		backstab = _can_perform_backstab_against_target(target)  \
		or _is_npc_undetected_backstab(target)

	var dmg: int = damage_normal
	var played_backstab_audio: bool = false
	if backstab:
		if debug_logging:
			print("Backstab detected! Target: %s" % [str(target)])
		# Preferred API: let enemies handle instant-kill/backstab logic
		if target.has_method("take_backstab"):
			if debug_logging:
				print("Target has take_backstab method, calling it...")
			target.take_backstab()
			if debug_logging:
				print("Calling speed boost...")
			_apply_backstab_speed_boost()
			# Feedback and finish
			var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
			var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
			# Play layered backstab audio (base + crit pitch stack)
			played_backstab_audio = _play_backstab_audio()
			if bullet_decal_texture:
				_spawn_decal(hit_pos, hit_normal)
			emit_signal("fired")
			_swing_in_progress = false
			return
		# Fallback: compute heavy damage if enemy doesn't support the API
		if target.has_method("get_health"):
			var th: int = int(target.get_health())
			dmg = int(max(float(th) * damage_backstab_multiplier, float(damage_normal)))
		else:
			dmg = damage_normal * 10
		played_backstab_audio = _play_backstab_audio()

	_apply_damage(target, dmg, hit)

	# Impact feedback and decal on hit
	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
	var hit_normal: Vector3 = hit.get("normal", Vector3.UP)
	if impact_sound and not played_backstab_audio:
		_play_sound(impact_sound)
	if bullet_decal_texture:
		_spawn_decal(hit_pos, hit_normal)
	emit_signal("fired")
	_swing_in_progress = false

func _melee_trace() -> Dictionary:
	var cam: Camera3D = _camera
	if cam == null:
		var origin: Vector3 = global_position
		var dir: Vector3 = -global_transform.basis.z
		return _ray(origin, origin + dir * melee_range)
	
	var origin: Vector3 = cam.global_position
	var dir: Vector3 = -cam.global_transform.basis.z
	return _ray(origin, origin + dir * melee_range)

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [self]
	q.collide_with_areas = collide_with_areas
	q.collide_with_bodies = collide_with_bodies
	var result: Dictionary = space_state.intersect_ray(q)
	# Always return a Dictionary; use {} for "no hit"
	return result if result.has("position") else {}

func _apply_damage(target: Object, amount: int, hit: Dictionary) -> void:
	if target and target.has_method("take_damage"):
		target.take_damage(amount)
	
	if impact_effect_scene:
		var pos: Vector3 = hit.get("position", Vector3.ZERO)
		var normal: Vector3 = hit.get("normal", Vector3.UP)
		_spawn_impact(pos, normal)

func _can_perform_backstab_against_target(target: Object) -> bool:
	var vagrant: Node3D = _get_owner_player()
	if vagrant == null:
		if debug_logging:
			print("Backstab check failed: vagrant is null")
		return false
	
	var t3d := target as Node3D
	if t3d == null:
		if debug_logging:
			print("Backstab check failed: target is not Node3D")
		return false
	
	var vagrant_pos: Vector3 = vagrant.global_transform.origin
	var target_pos: Vector3 = t3d.global_transform.origin
	
	var to_target: Vector3 = target_pos - vagrant_pos
	to_target.y = 0.0
	if to_target.length() == 0.0:
		if debug_logging:
			print("Backstab check failed: target too close")
		return false
	to_target = to_target.normalized()
	
	var vagrant_fwd: Vector3 = -vagrant.global_transform.basis.z
	vagrant_fwd.y = 0.0
	vagrant_fwd = vagrant_fwd.normalized()
	
	var tgt_fwd: Vector3 = -t3d.global_transform.basis.z
	tgt_fwd.y = 0.0
	if tgt_fwd.length() == 0.0:
		if debug_logging:
			print("Backstab check failed: target has no forward direction")
		return false
	tgt_fwd = tgt_fwd.normalized()
	
	var behind := to_target.dot(tgt_fwd) > 0.0
	var facing := to_target.dot(vagrant_fwd) > 0.5
	var no_facestab := tgt_fwd.dot(vagrant_fwd) > -0.3
	
	if debug_logging:
		print("Backstab geometric check - behind: %s facing: %s no_facestab: %s" % [behind, facing, no_facestab])
	return behind and facing and no_facestab

func _get_owner_player() -> Node3D:
	# Use manually set player node if available
	if player_node != null:
		if debug_logging:
			print("Using manually set player node: %s" % [player_node.name])
		return player_node
	
	# Fallback to automatic detection
	if debug_logging:
		print("Player node not set, attempting automatic detection...")
	var n := self.get_parent()
	var depth = 0
	while n and depth < 10:  # Prevent infinite loops
		if debug_logging:
			print("Checking node at depth %s: %s (%s)" % [depth, n.name, n.get_class()])
			print("  - is Node3D: %s" % [n is Node3D])
			print("  - has take_damage: %s" % [n.has_method("take_damage")])
			print("  - has get_health: %s" % [n.has_method("get_health")])
			print("  - is CharacterBody3D: %s" % [n.is_class("CharacterBody3D")])
		
		if n is Node3D and (n.has_method("take_damage") or n.has_method("get_health") or n.is_class("CharacterBody3D")):
			if debug_logging:
				print("Found player node: %s" % [n.name])
			return n as Node3D
		n = n.get_parent()
		depth += 1
	if debug_logging:
		print("No player node found after checking %s levels up" % [depth])
	return null

func _check_backstab_ready() -> bool:
	var hit: Dictionary = _melee_trace()
	if hit.is_empty():
		return false
	
	var target: Object = hit.get("collider", null)
	if target == null:
		return false
	
	# Check if target can be backstabbed
	if not target.has_method("take_damage"):
		return false
	
	# Check geometric backstab conditions
	var can_geometric_backstab = _can_perform_backstab_against_target(target)
	var can_npc_backstab = _is_npc_undetected_backstab(target)
	
	return can_geometric_backstab or can_npc_backstab


func _apply_backstab_speed_boost() -> void:
	var player: CharacterBody3D = _get_owner_player() as CharacterBody3D
	if player == null:
		return
	
	# Find the GoldGdt User Input component that has Parameters
	var controls_component: Node = player.get_node_or_null("../User Input")
	if controls_component == null:
		push_warning("Controls component not found for backstab speed boost")
		return
	
	var params: PlayerParameters = controls_component.get("Parameters")
	if params == null:
		push_warning("Parameters not found on controls component")
		return
	
	# If boost is already active, just reset the timer
	if _speed_boost_active:
		if debug_logging:
			print("Speed boost already active, resetting timer")
		_boost_timer.start(backstab_boost_duration)
		return
	
	# Store original speeds only on first activation
	_original_speeds["MAX_SPEED"] = params.MAX_SPEED
	_original_speeds["FORWARD_SPEED"] = params.FORWARD_SPEED
	_original_speeds["SIDE_SPEED"] = params.SIDE_SPEED
	
	# Apply speed boost
	params.MAX_SPEED += backstab_speed_boost
	params.FORWARD_SPEED += backstab_speed_boost
	params.SIDE_SPEED += backstab_speed_boost
	
	# Change speedometer color
	if _speedometer:
		_speedometer.modulate = speed_boost_color
	
	# Activate boost and start timer
	_speed_boost_active = true
	_boost_timer.start(backstab_boost_duration)
	
	if debug_logging:
		print("Backstab speed boost applied! New speeds - MAX: %s FORWARD: %s SIDE: %s" % [params.MAX_SPEED, params.FORWARD_SPEED, params.SIDE_SPEED])

func _end_speed_boost() -> void:
	if not _speed_boost_active:
		return
	
	var player: CharacterBody3D = _get_owner_player() as CharacterBody3D
	if player == null:
		_speed_boost_active = false
		return
	
	var controls_component: Node = player.get_node_or_null("../User Input")
	if controls_component == null:
		_speed_boost_active = false
		return
	
	var params: PlayerParameters = controls_component.get("Parameters")
	if params == null:
		_speed_boost_active = false
		return
	
	# Restore original speeds
	params.MAX_SPEED = _original_speeds.get("MAX_SPEED", params.MAX_SPEED)
	params.FORWARD_SPEED = _original_speeds.get("FORWARD_SPEED", params.FORWARD_SPEED)
	params.SIDE_SPEED = _original_speeds.get("SIDE_SPEED", params.SIDE_SPEED)
	
	# Restore speedometer color to its original state
	if _speedometer:
		# Reset to the speedometer's default color (white with alpha)
		_speedometer.modulate = Color(1, 1, 1, 0.552)
	
	_speed_boost_active = false
	if debug_logging:
		print("Backstab speed boost ended! Restored speeds - MAX: %s FORWARD: %s SIDE: %s" % [params.MAX_SPEED, params.FORWARD_SPEED, params.SIDE_SPEED])

func _play_backstab_audio() -> bool:
	var played := false
	if backstab_hit_sound:
		_play_sound(backstab_hit_sound)
		played = true
	if backstab_crit_sound:
		_play_backstab_crit_sound_with_pitch()
		played = true
	if not played and impact_sound:
		_play_sound(impact_sound)
		played = true
	return played

func _play_backstab_crit_sound_with_pitch() -> void:
	if backstab_crit_sound == null:
		return
	# Compute current pitch based on stacks
	var stacks: int = min(_backstab_pitch_stacks, backstab_pitch_max_stacks)
	var pitch_scale_value: float = 1.0 + float(stacks) * backstab_pitch_step
	_backstab_player.stop()
	_backstab_player.stream = backstab_crit_sound
	_backstab_player.pitch_scale = pitch_scale_value
	_backstab_player.play()
	# Increment stacks and restart decay timer
	_backstab_pitch_stacks = min(_backstab_pitch_stacks + 1, backstab_pitch_max_stacks)
	_backstab_pitch_timer.start(backstab_pitch_window)
	if debug_logging:
		print("Backstab pitch stacks: %s pitch: %s" % [_backstab_pitch_stacks, pitch_scale_value])

func _is_npc_undetected_backstab(target: Object) -> bool:
	if target is BaseEnemy:
		var e := target as BaseEnemy
		# Undetected if idle and currently does not see the player
		var is_idle = e.current_state == BaseEnemy.EnemyState.IDLE
		var cant_see_player = not e.can_see_player()
		if debug_logging:
			print("NPC undetected backstab check - is_idle: %s cant_see_player: %s" % [is_idle, cant_see_player])
		return is_idle and cant_see_player
	if debug_logging:
		print("NPC undetected backstab check failed: target is not BaseEnemy")
	return false

# ===== THROWABLE KNIFE SYSTEM =====

func _init_throwable_knife_system() -> void:
	"""Initialize throwable knife timers and state"""
	# Start with max knives available
	_thrown_knives_count = max_throw_knives
	
	# Create throw cooldown timer
	_throw_cooldown_timer = Timer.new()
	_throw_cooldown_timer.one_shot = true
	_throw_cooldown_timer.timeout.connect(func(): _can_throw = true)
	add_child(_throw_cooldown_timer)
	
	# Create knife recharge timer (continuous timer for recharging knives)
	_knife_recharge_timer = Timer.new()
	_knife_recharge_timer.one_shot = false
	_knife_recharge_timer.wait_time = knife_recharge_time
	_knife_recharge_timer.timeout.connect(_recharge_knife)
	add_child(_knife_recharge_timer)
	_knife_recharge_timer.start()
	
	if debug_logging:
		print("Throwable knife system initialized - Starting knives: %s" % [_thrown_knives_count])

func _input(event: InputEvent) -> void:
	"""Handle alt fire input for throwing knives"""
	if event.is_action_pressed(alt_fire_action):
		alt_fire()

func alt_fire() -> void:
	"""Throw a knife as alt fire"""
	if debug_logging:
		print("Alt fire called - can_throw: %s knives: %s" % [_can_throw, _thrown_knives_count])
	
	if not _can_throw:
		if debug_logging:
			print("Alt fire blocked: on cooldown")
		return
	
	if _thrown_knives_count <= 0:
		if debug_logging:
			print("Alt fire blocked: no knives available")
		return
	
	if throwable_knife_scene == null:
		push_warning("Alt fire blocked: throwable_knife_scene not set!")
		return
	
	# Throw the knife
	_throw_knife()
	
	# Consume a knife
	_thrown_knives_count -= 1
	if debug_logging:
		print("Knife thrown! Remaining knives: %s" % [_thrown_knives_count])
	
	# Start cooldown
	_can_throw = false
	_throw_cooldown_timer.start(throw_cooldown)

func _throw_knife() -> void:
	"""Spawn and throw a knife projectile"""
	# Get camera for aiming
	var cam: Camera3D = _camera
	if cam == null:
		push_warning("Cannot throw knife: camera not found")
		return
	
	# Calculate throw direction
	var origin: Vector3 = cam.global_position
	var direction: Vector3 = -cam.global_transform.basis.z
	
	# Apply throw arc (upward angle)
	if throw_arc > 0.0:
		var up_vector: Vector3 = cam.global_transform.basis.y
		direction = direction.rotated(cam.global_transform.basis.x, deg_to_rad(-throw_arc))
	direction = direction.normalized()
	
	# Calculate velocity
	var velocity: Vector3 = direction * throw_velocity
	
	# Spawn knife projectile
	var knife: Node3D = throwable_knife_scene.instantiate()
	get_tree().current_scene.add_child(knife)
	knife.global_position = origin
	knife.global_rotation = cam.global_rotation
	
	# Initialize knife if it has the throw method
	if knife.has_method("throw"):
		var thrower = _get_owner_player()
		knife.throw(velocity, thrower)
	
	# Play throw sound
	if throw_sound:
		_play_sound(throw_sound)
	
	if debug_logging:
		print("Knife thrown from: %s with velocity: %s" % [origin, velocity])

func _recharge_knife() -> void:
	"""Recharge one knife over time"""
	if _thrown_knives_count < max_throw_knives:
		_thrown_knives_count += 1
		if debug_logging:
			print("Knife recharged! Current knives: %s" % [_thrown_knives_count])

## Get current number of throwable knives available
func get_throwable_knives_count() -> int:
	return _thrown_knives_count

## Get max throwable knives
func get_max_throwable_knives() -> int:
	return max_throw_knives
