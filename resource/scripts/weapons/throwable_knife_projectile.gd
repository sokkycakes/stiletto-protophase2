extends RigidBody3D
class_name ThrowableKnifeProjectile

## Inherits ownership tracking from NetworkedProjectile
## Note: This class uses composition pattern with ownership utilities

signal stuck(location: Transform3D, normal: Vector3)

## Throwable knife projectile component
## Handles physics, damage, and collision for thrown knives

# Damage configuration
@export var damage: int = 1
@export var backstab_damage_multiplier: float = 2.0
@export var lifetime: float = 10.0  # Auto-destroy after this time

# Collision and hit detection
@export var collide_with_areas: bool = true
@export var collide_with_bodies: bool = true
@export var stick_to_surfaces: bool = true  # Whether knife sticks in walls
@export var penetration_depth: float = 0.1  # How deep knife goes into surface

# Visual feedback
@export var impact_effect_scene: PackedScene
@export var trail_effect_scene: PackedScene

# Audio feedback
@export var throw_sound: AudioStream
@export var impact_sound: AudioStream
@export var audio_bus: String = "SFX"
@export var throw_loop_sound: AudioStream
@export var doppler_pitch_multiplier: float = 0.02
@export var doppler_min_pitch: float = 0.7
@export var doppler_max_pitch: float = 1.5
@export var doppler_smoothing: float = 5.0

# Internal state
var _velocity: Vector3 = Vector3.ZERO
var _has_hit: bool = false
var _lifetime_timer: Timer
var _thrower: Node3D = null  # Reference to who threw the knife
var _thrower_peer_id: int = -1  # Network peer ID of thrower (for multiplayer collision checks)
var _initial_position: Vector3 = Vector3.ZERO
var _trail: Node3D = null
var _throw_loop_player: AudioStreamPlayer3D = null
var _previous_distance: float = -1.0
var _current_pitch: float = 1.0

func _ready() -> void:
	# Set up lifetime timer
	_lifetime_timer = Timer.new()
	_lifetime_timer.one_shot = true
	_lifetime_timer.wait_time = lifetime
	_lifetime_timer.timeout.connect(_on_lifetime_expired)
	add_child(_lifetime_timer)
	_lifetime_timer.start()
	
	# Set up collision detection
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	
	# Store initial position for distance calculations
	_initial_position = global_position
	
	# Spawn trail effect if configured
	if trail_effect_scene:
		_spawn_trail()

func _physics_process(delta: float) -> void:
	if _has_hit:
		return
	
	# Orient knife to face movement direction
	if linear_velocity.length() > 0.1:
		var forward = -linear_velocity.normalized()
		look_at(global_position + forward, Vector3.UP)
		# Rotate to make the knife point forward (tip first)
		rotate_object_local(Vector3.RIGHT, deg_to_rad(90))
	_update_throw_loop_audio(delta)

## Initialize the projectile with velocity and thrower reference
func throw(velocity: Vector3, thrower: Node3D = null, thrower_peer_id: int = -1) -> void:
	_velocity = velocity
	_thrower = thrower
	_thrower_peer_id = thrower_peer_id
	
	# If thrower_peer_id is provided but thrower is null, find the NetworkedPlayer by peer_id
	if _thrower == null and _thrower_peer_id >= 0:
		_thrower = _find_networked_player_by_peer_id(_thrower_peer_id)
	
	linear_velocity = velocity
	
	# Prevent immediate self-collision by adding collision exceptions with the thrower and any PhysicsBody children.
	if _thrower:
		if _thrower is PhysicsBody3D:
			add_collision_exception_with(_thrower)
		# Also add exceptions for all descendant PhysicsBody3D nodes (e.g. ragdoll bodies, hitboxes)
		for descendant in _thrower.get_children():
			_add_physics_body_exceptions_recursive(descendant)
	
	_start_throw_loop_audio()

func _on_body_entered(body: Node) -> void:
	if _has_hit:
		return
	
	# Don't collide with thrower - check both object reference and NetworkedPlayer peer_id
	if _is_thrower(body):
		return
	
	_has_hit = true
	_stop_throw_loop_audio()
	
	# Check for backstab/damage against a resolved damage receiver (e.g., NetworkedPlayer)
	var receiver := _find_damage_receiver(body)
	
	# Double-check: don't damage the thrower's NetworkedPlayer (even if collision exception failed)
	if receiver:
		var receiver_np := receiver as NetworkedPlayer
		if receiver_np and receiver_np.peer_id == _thrower_peer_id and _thrower_peer_id >= 0:
			# This is the thrower - don't apply damage, just stick to surface
			if stick_to_surfaces:
				_stick_to_surface(body)
			else:
				queue_free()
			return
	
	var is_backstab := false
	var final_damage := damage

	if receiver:
		# For thrown knives, always deal base damage (1hp) to players, regardless of backstab
		if receiver is NetworkedPlayer:
			# Thrown knives always deal 1hp to players
			final_damage = damage
		else:
			# For non-players (enemies), check for backstab
			is_backstab = _can_backstab(receiver)
			if is_backstab:
				if receiver.has_method("take_backstab"):
					receiver.take_backstab()
				else:
					# Fallback: multiply damage
					if receiver.has_method("get_health"):
						var health = int(receiver.get_health())
						final_damage = int(max(float(health) * backstab_damage_multiplier, float(damage)))
					else:
						final_damage = damage * 10
		
		var attacker_peer_id := -1
		var attacker_np := _get_networked_player_for(_thrower)
		if attacker_np:
			attacker_peer_id = attacker_np.peer_id
		
		if receiver is NetworkedPlayer:
			# Route damage via RPC so it is applied on the authoritative instance.
			# Pass receiver's peer_id for validation to prevent wrong player from taking damage
			var receiver_np := receiver as NetworkedPlayer
			var target_peer_id := receiver_np.peer_id if receiver_np else -1
			# Send RPC specifically to the authority peer (the player who owns this NetworkedPlayer)
			receiver.apply_damage.rpc_id(target_peer_id, final_damage, attacker_peer_id, target_peer_id)
		elif receiver.has_method("take_damage"):
			receiver.take_damage(final_damage)
	
	# Spawn impact effect
	if impact_effect_scene:
		_spawn_impact_effect(global_position, -linear_velocity.normalized())
	
	# Play impact sound
	if impact_sound:
		_play_sound(impact_sound)
	
	var impact_normal := Vector3.UP
	if linear_velocity.length() > 0.1:
		impact_normal = -linear_velocity.normalized()
	impact_normal = impact_normal.normalized()
	var anchor_transform := Transform3D(global_transform.basis, global_position)
	if stick_to_surfaces:
		anchor_transform = _stick_to_surface(body)
	else:
		queue_free()
	emit_signal("stuck", anchor_transform, impact_normal)

func _can_backstab(target: Object) -> bool:
	if not _thrower:
		return false
	
	var target_3d := target as Node3D
	if target_3d == null:
		return false
	
	var thrower_pos: Vector3 = _thrower.global_transform.origin
	var target_pos: Vector3 = target_3d.global_transform.origin
	
	var to_target: Vector3 = target_pos - thrower_pos
	to_target.y = 0.0
	if to_target.length() == 0.0:
		return false
	to_target = to_target.normalized()
	
	var thrower_fwd: Vector3 = -_thrower.global_transform.basis.z
	thrower_fwd.y = 0.0
	thrower_fwd = thrower_fwd.normalized()
	
	var target_fwd: Vector3 = -target_3d.global_transform.basis.z
	target_fwd.y = 0.0
	if target_fwd.length() == 0.0:
		return false
	target_fwd = target_fwd.normalized()
	
	var behind := to_target.dot(target_fwd) > 0.0
	var facing := to_target.dot(thrower_fwd) > 0.5
	var no_facestab := target_fwd.dot(thrower_fwd) > -0.3
	
	return behind and facing and no_facestab

func _find_damage_receiver(target: Object) -> Object:
	# Walk up the hierarchy from the collider to find a node that can receive damage.
	# When walking up from a collision body, if we find a NetworkedPlayer, that NetworkedPlayer
	# must own the body (since the body is a descendant). This ensures correct ownership identification.
	var node := target as Node
	while node:
		if node is NetworkedPlayer:
			# Found a NetworkedPlayer - since we walked UP to reach it, target must be below it
			# This means this NetworkedPlayer owns the collision body
			return node
		elif node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null

func _get_networked_player_for(node: Node) -> NetworkedPlayer:
	var n := node
	while n:
		if n is NetworkedPlayer:
			return n
		n = n.get_parent()
	return null

func _is_thrower(body: Node) -> bool:
	"""Check if the body belongs to the thrower (using universal ownership utilities)"""
	if not body:
		return false
	
	# Use universal ownership checking (same logic as NetworkedProjectile)
	# Direct object reference match
	if body == _thrower:
		return true
	
	# Check if body is part of thrower's hierarchy
	if _thrower:
		var node := body
		while node:
			if node == _thrower:
				return true
			node = node.get_parent()
	
	# Check by NetworkedPlayer peer_id (works across network)
	if _thrower_peer_id >= 0:
		var body_np := _get_networked_player_for(body)
		if body_np and body_np.peer_id == _thrower_peer_id:
			return true
	
	return false

func _find_networked_player_by_peer_id(peer_id: int) -> Node3D:
	"""Find a NetworkedPlayer node by peer_id in the scene (using universal utilities)"""
	var scene_root = get_tree().current_scene if get_tree() else null
	return NetworkedProjectileOwnership.get_pawn_by_peer_id(scene_root, peer_id)

func _stick_to_surface(surface: Node) -> Transform3D:
	# Disable physics
	freeze = true
	
	# Adjust position to penetrate surface slightly
	global_position += -global_transform.basis.z * penetration_depth
	
	# Optionally parent to the surface for moving platforms
	if surface is RigidBody3D or surface is CharacterBody3D:
		# For moving objects, we might want to parent it
		# For now, just freeze in place
		pass
	return Transform3D(global_transform.basis, global_position)

func _on_lifetime_expired() -> void:
	_stop_throw_loop_audio()
	queue_free()

func _play_sound(sound: AudioStream) -> void:
	if sound:
		var player := AudioStreamPlayer3D.new()
		player.stream = sound
		player.bus = audio_bus
		add_child(player)
		player.play()
		player.finished.connect(func(): player.queue_free())

func _spawn_impact_effect(pos: Vector3, normal: Vector3) -> void:
	if impact_effect_scene == null:
		return
	var impact := impact_effect_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = pos
	if impact is Node3D:
		impact.look_at(pos + normal, Vector3.UP)

func _spawn_trail() -> void:
	if trail_effect_scene == null:
		return
	_trail = trail_effect_scene.instantiate()
	add_child(_trail)

func _start_throw_loop_audio() -> void:
	_stop_throw_loop_audio()
	var stream: AudioStream = throw_loop_sound if throw_loop_sound else throw_sound
	if stream == null:
		return
	_force_stream_loop(stream)
	_throw_loop_player = AudioStreamPlayer3D.new()
	_throw_loop_player.stream = stream
	_throw_loop_player.bus = audio_bus
	_throw_loop_player.pitch_scale = 1.0
	_throw_loop_player.attenuation_filter_cutoff_hz = 5000.0
	_throw_loop_player.unit_size = 1.0
	add_child(_throw_loop_player)
	_current_pitch = 1.0
	_previous_distance = -1.0
	_throw_loop_player.play()

func _stop_throw_loop_audio() -> void:
	if _throw_loop_player:
		_throw_loop_player.stop()
		_throw_loop_player.queue_free()
		_throw_loop_player = null
	_previous_distance = -1.0
	_current_pitch = 1.0

func _update_throw_loop_audio(delta: float) -> void:
	if _throw_loop_player == null:
		return
	
	# Try to find thrower by peer_id if we don't have a direct reference
	if _thrower == null and _thrower_peer_id >= 0:
		_thrower = _find_networked_player_by_peer_id(_thrower_peer_id)
	
	var target_pitch: float = 1.0
	if _thrower:
		var current_distance: float = global_position.distance_to(_thrower.global_transform.origin)
		if _previous_distance < 0.0:
			_previous_distance = current_distance
			return
		var distance_delta: float = (_previous_distance - current_distance) / max(delta, 0.0001)
		target_pitch = 1.0 + distance_delta * doppler_pitch_multiplier
		_previous_distance = current_distance
	else:
		var relative_speed: float = linear_velocity.length()
		target_pitch = 1.0 + relative_speed * doppler_pitch_multiplier * 0.01
	target_pitch = clamp(target_pitch, doppler_min_pitch, doppler_max_pitch)
	var lerp_weight: float = clamp(delta * doppler_smoothing, 0.0, 1.0)
	_current_pitch = lerp(_current_pitch, target_pitch, lerp_weight)
	_throw_loop_player.pitch_scale = _current_pitch


func _force_stream_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var sample := stream as AudioStreamWAV
		if sample.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = true
	elif stream is AudioStreamMP3:
		var mp3 := stream as AudioStreamMP3
		mp3.loop = true

func _add_physics_body_exceptions_recursive(node: Node) -> void:
	if node is PhysicsBody3D:
		add_collision_exception_with(node)
	for child in node.get_children():
		_add_physics_body_exceptions_recursive(child)
