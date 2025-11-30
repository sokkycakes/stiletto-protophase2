extends Node3D
class_name HookMeleeAttack

## Melee attack system for hook-based weapons that performs a wide horizontal sweep
## Uses the hook mesh as a visualizer and an Area3D for hit detection

# Attack properties
@export var attack_damage: float = 25.0
@export var attack_range: float = 3.0  # How far the hook reaches
@export var attack_arc_degrees: float = 120.0  # Sweep arc in degrees
@export var attack_duration: float = 0.4  # How long the sweep takes
@export var attack_cooldown: float = 1.0

# Parry/Reflect properties
@export var can_parry_projectiles: bool = true  # Can this melee attack reflect projectiles?
@export var parry_reflect_speed_multiplier: float = 1.2  # Speed multiplier for reflected projectiles

# Visual properties
@export var hook_mesh_path: NodePath  # Path to the hook mesh (e.g., v_hook_arm or hook model)
@export var hook_rotation_speed: float = 1.0  # Multiplier for rotation speed
@export var sweep_direction: int = 1  # 1 for right-to-left, -1 for left-to-right

# Audio
@export var swing_sound: AudioStream
@export var hit_sound: AudioStream
@export var audio_bus: String = "sfx"

# Node references
@onready var attack_hitbox: Area3D = $AttackHitbox
var hook_mesh: Node3D = null
var _parry_component: ParryComponent = null
var _camera: Camera3D = null

# State
var can_attack: bool = true
var is_attacking: bool = false
var _attack_tween: Tween
var _initial_hook_rotation: Vector3
var _audio_player: AudioStreamPlayer
var _attacker_networked_player: Node = null
var _attacker_peer_id: int = -1

# Signals
signal attack_started
signal attack_ended
signal target_hit(target: Node)

func _ready() -> void:
	# Find camera (parent should be Camera3D)
	_camera = get_parent() as Camera3D
	if not _camera:
		# Try to find camera in parent hierarchy
		var node = get_parent()
		var depth = 0
		while node and depth < 5:
			if node is Camera3D:
				_camera = node as Camera3D
				break
			node = node.get_parent()
			depth += 1
	
	# Find ParryComponent if it exists
	_parry_component = _find_parry_component()
	if _parry_component:
		# Configure parry component
		_parry_component.camera = _camera
		_parry_component.melee_range = attack_range
		print("[HookMeleeAttack] ParryComponent found and configured")
	
	# Find hook mesh if path is provided
	if hook_mesh_path != NodePath(""):
		hook_mesh = get_node_or_null(hook_mesh_path)
		if hook_mesh:
			_initial_hook_rotation = hook_mesh.rotation
			# Hide mesh by default
			if hook_mesh is MeshInstance3D:
				hook_mesh.visible = false
			elif hook_mesh.has_method("set_visible"):
				hook_mesh.set_visible(false)
		else:
			push_warning("HookMeleeAttack: Hook mesh not found at path: " + str(hook_mesh_path))
	
	# Setup hitbox
	if not attack_hitbox:
		push_error("HookMeleeAttack: AttackHitbox not found!")
		return
	
	# Connect hitbox signals
	attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	attack_hitbox.area_entered.connect(_on_attack_hitbox_area_entered)
	
	# Initialize hitbox state
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = false
	
	# Create audio player
	_audio_player = AudioStreamPlayer.new()
	_audio_player.bus = audio_bus
	add_child(_audio_player)
	
	# Find the attacker's NetworkedPlayer for damage attribution
	_find_attacker_networked_player()

func perform_attack() -> void:
	"""Perform the melee attack sweep"""
	if not can_attack or is_attacking:
		return
	
	can_attack = false
	is_attacking = true
	attack_started.emit()
	
	# Sync attack to all clients (authority triggers RPC)
	if is_multiplayer_authority():
		sync_melee_attack.rpc()
	
	# Perform local attack (runs on all clients via RPC or directly)
	_perform_attack_local()

func _perform_attack_local() -> void:
	"""Perform the local attack animation and effects"""
	# Activate parry component if present
	if _parry_component:
		_parry_component.activate()
	
	# Show mesh at start of attack
	if hook_mesh:
		if hook_mesh is MeshInstance3D:
			hook_mesh.visible = true
		elif hook_mesh.has_method("set_visible"):
			hook_mesh.set_visible(true)
	
	# Play swing sound
	if swing_sound:
		_audio_player.stream = swing_sound
		_audio_player.play()
	
	# Enable hitbox (only on authority for damage detection)
	if is_multiplayer_authority():
		attack_hitbox.monitoring = true
		attack_hitbox.monitorable = true
		
		# Exclude attacker's body from collisions
		_setup_collision_exclusions()
		
		print("[HookMeleeAttack] Hitbox enabled - monitoring: ", attack_hitbox.monitoring, ", mask: ", attack_hitbox.collision_mask)
	
	# Animate the hook sweep (visual on all clients)
	_animate_hook_sweep()
	
	# Wait for attack duration
	await get_tree().create_timer(attack_duration).timeout
	
	# Disable hitbox (only on authority)
	if is_multiplayer_authority():
		attack_hitbox.monitoring = false
		attack_hitbox.monitorable = false
	
	# Hide mesh at end of attack
	if hook_mesh:
		if hook_mesh is MeshInstance3D:
			hook_mesh.visible = false
		elif hook_mesh.has_method("set_visible"):
			hook_mesh.set_visible(false)
	
	is_attacking = false
	attack_ended.emit()
	
	# Start cooldown
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

@rpc("any_peer", "call_local", "reliable")
func sync_melee_attack() -> void:
	"""Sync melee attack animation to all clients"""
	# Only perform if not already attacking (prevents duplicate from local call)
	if not is_attacking:
		can_attack = false
		is_attacking = true
		attack_started.emit()
		_perform_attack_local()

func _animate_hook_sweep() -> void:
	"""Animate the hook mesh in a sweeping motion - linear animation from start to end"""
	if not hook_mesh:
		return
	
	# Store initial rotation if not already stored
	if _initial_hook_rotation == Vector3.ZERO:
		_initial_hook_rotation = hook_mesh.rotation
	
	# Reset to initial rotation at start of each attack
	hook_mesh.rotation = _initial_hook_rotation
	
	# Calculate target rotation (sweep horizontally)
	var sweep_angle = deg_to_rad(attack_arc_degrees) * sweep_direction
	var target_rotation = _initial_hook_rotation
	target_rotation.y += sweep_angle
	
	# Create tween for linear sweep motion
	if _attack_tween:
		_attack_tween.kill()
	
	_attack_tween = create_tween()
	_attack_tween.set_ease(Tween.EASE_IN_OUT)  # Linear motion
	_attack_tween.set_trans(Tween.TRANS_LINEAR)  # Linear interpolation
	
	# Animate the hook rotation linearly from start to end (no return)
	_attack_tween.tween_property(
		hook_mesh, 
		"rotation", 
		target_rotation, 
		attack_duration * hook_rotation_speed
	)
	
	# Also animate the hitbox position/rotation to match the sweep
	if attack_hitbox:
		var hitbox_initial_rot = Vector3.ZERO  # Reset hitbox rotation at start
		attack_hitbox.rotation = hitbox_initial_rot
		var hitbox_target_rot = hitbox_initial_rot
		hitbox_target_rot.y += sweep_angle
		
		_attack_tween.parallel().tween_property(
			attack_hitbox,
			"rotation",
			hitbox_target_rot,
			attack_duration * hook_rotation_speed
		)

# Removed _reset_hook_position() - hook stays at end position and mesh is hidden

func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	"""Handle when a body enters the attack hitbox"""
	# Only process damage on authority
	if not is_multiplayer_authority():
		return
	
	print("[HookMeleeAttack] Body entered hitbox: ", body.name, " (", body.get_class(), ")")
	
	# Find the damage receiver (NetworkedPlayer or node with take_damage)
	var receiver := _find_damage_receiver(body)
	if not receiver:
		print("[HookMeleeAttack] No damage receiver found for: ", body.name)
		return
	
	print("[HookMeleeAttack] Found damage receiver: ", receiver.name, " (", receiver.get_class(), ")")
	
	# Don't damage the attacker
	if _is_attacker(receiver):
		print("[HookMeleeAttack] Ignoring hit on attacker: ", receiver.name)
		return
	
	target_hit.emit(receiver)
	
	# Play hit sound
	if hit_sound:
		_audio_player.stream = hit_sound
		_audio_player.play()
	
	# Apply damage - handle NetworkedPlayer specially with RPC
	if receiver is NetworkedPlayer:
		var receiver_np := receiver as NetworkedPlayer
		var target_peer_id := receiver_np.peer_id if receiver_np else -1
		print("[HookMeleeAttack] Applying damage to NetworkedPlayer: ", receiver_np.player_name, " (peer_id: ", target_peer_id, ", attacker_peer_id: ", _attacker_peer_id, ")")
		receiver.apply_damage.rpc_id(target_peer_id, float(attack_damage), _attacker_peer_id, target_peer_id)
	elif receiver.has_method("take_damage"):
		print("[HookMeleeAttack] Applying damage to: ", receiver.name)
		receiver.take_damage(attack_damage)
	
	# Optional: Apply knockback
	if body is CharacterBody3D:
		_apply_knockback(body)

func _on_attack_hitbox_area_entered(area: Area3D) -> void:
	"""Handle when an area enters the attack hitbox"""
	# Only process on authority
	if not is_multiplayer_authority():
		return
	
	print("[HookMeleeAttack] Area entered hitbox: ", area.name, " (", area.get_class(), ")")
	
	# Check if it's a projectile that can be parried
	if can_parry_projectiles and _is_projectile(area):
		_parry_projectile(area)
		return
	
	# Find the damage receiver
	var receiver := _find_damage_receiver(area)
	if not receiver:
		return
	
	# Don't damage the attacker
	if _is_attacker(receiver):
		return
	
	target_hit.emit(receiver)
	
	# Play hit sound
	if hit_sound:
		_audio_player.stream = hit_sound
		_audio_player.play()
	
	# Apply damage - handle NetworkedPlayer specially with RPC
	if receiver is NetworkedPlayer:
		var receiver_np := receiver as NetworkedPlayer
		var target_peer_id := receiver_np.peer_id if receiver_np else -1
		receiver.apply_damage.rpc_id(target_peer_id, float(attack_damage), _attacker_peer_id, target_peer_id)
	elif receiver.has_method("take_damage"):
		receiver.take_damage(attack_damage)

func _find_damage_receiver(target: Node) -> Node:
	"""Find the damage receiver node (NetworkedPlayer or node with take_damage)"""
	var node := target
	while node:
		if node is NetworkedPlayer or node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null

func _find_attacker_networked_player() -> void:
	"""Find the NetworkedPlayer that owns this attack"""
	var node := get_parent()
	var depth = 0
	while node and depth < 10:
		if node is NetworkedPlayer:
			_attacker_networked_player = node
			_attacker_peer_id = node.peer_id if "peer_id" in node else -1
			# Set multiplayer authority to match the attacker
			var authority = node.get_multiplayer_authority() if node.has_method("get_multiplayer_authority") else -1
			if authority > 0:
				set_multiplayer_authority(authority)
			return
		node = node.get_parent()
		depth += 1

func _is_attacker(receiver: Node) -> bool:
	"""Check if the receiver is the attacker"""
	if not receiver:
		return false
	
	# Check by NetworkedPlayer peer_id
	if receiver is NetworkedPlayer:
		var receiver_np := receiver as NetworkedPlayer
		if receiver_np.peer_id == _attacker_peer_id and _attacker_peer_id >= 0:
			return true
	
	# Check if receiver is part of attacker's hierarchy
	if _attacker_networked_player:
		var node := receiver
		while node:
			if node == _attacker_networked_player:
				return true
			node = node.get_parent()
	
	return false

func _setup_collision_exclusions() -> void:
	"""Exclude the attacker's body from hitbox collisions"""
	if not _attacker_networked_player:
		return
	
	# Find the attacker's CharacterBody3D (Body node)
	var attacker_body = _attacker_networked_player.get_node_or_null("Body")
	if attacker_body and attacker_body is CharacterBody3D:
		# Add attacker's body and all its collision shapes to exclusion list
		var exclude_list: Array = [attacker_body]
		
		# Recursively find all CollisionObject3D children
		var nodes_to_process: Array = [attacker_body]
		while nodes_to_process.size() > 0:
			var n: Node = nodes_to_process.pop_back()
			for child in n.get_children():
				nodes_to_process.append(child)
				if child is CollisionObject3D:
					exclude_list.append(child)
		
		# Note: Area3D doesn't have direct exclusion, but we check in _is_attacker()
		# The exclusion is handled in the signal handler

func _is_projectile(area: Area3D) -> bool:
	"""Check if an area is a projectile that can be parried"""
	# Check if it has projectile properties
	if area.has_method("set_owner_info") or area.has_method("set_owner"):
		return true
	
	# Check for common projectile properties
	if "owner_peer_id" in area or "owner_node" in area or "direction" in area:
		return true
	
	# Check if it's a known projectile class
	if area is Projectile or area.get_script() and "Projectile" in str(area.get_script().resource_path):
		return true
	
	return false

func _parry_projectile(projectile: Area3D) -> void:
	"""Parry/reflect a projectile back at its original shooter"""
	if not projectile:
		return
	
	print("[HookMeleeAttack] Parrying projectile: ", projectile.name)
	
	# Get the original shooter's peer_id
	var original_shooter_peer_id: int = -1
	if "owner_peer_id" in projectile:
		original_shooter_peer_id = projectile.owner_peer_id
	elif projectile.has_method("get_owner_peer_id"):
		original_shooter_peer_id = projectile.get_owner_peer_id()
	
	# Find the original shooter's position (to reflect back at them)
	var original_shooter_position: Vector3 = Vector3.ZERO
	if original_shooter_peer_id >= 0:
		var scene_root = get_tree().current_scene if get_tree() else null
		if scene_root:
			var original_shooter = NetworkedProjectileOwnership.find_networked_player_by_peer_id(scene_root, original_shooter_peer_id)
			if original_shooter:
				var shooter_body = original_shooter.get_node_or_null("Body")
				if shooter_body and shooter_body is Node3D:
					original_shooter_position = shooter_body.global_position
				else:
					original_shooter_position = original_shooter.global_position
	
	# If we couldn't find the shooter, reflect in the opposite direction
	var reflect_direction: Vector3
	if original_shooter_position != Vector3.ZERO:
		reflect_direction = (original_shooter_position - projectile.global_position).normalized()
	else:
		# Reverse the current direction
		if "direction" in projectile:
			reflect_direction = -projectile.direction.normalized()
		else:
			# Fallback: reflect away from parrier
			var parrier_body = _attacker_networked_player.get_node_or_null("Body") if _attacker_networked_player else null
			if parrier_body and parrier_body is Node3D:
				reflect_direction = (projectile.global_position - parrier_body.global_position).normalized()
			else:
				reflect_direction = Vector3.FORWARD
	
	# Update projectile direction
	if "direction" in projectile:
		projectile.direction = reflect_direction * parry_reflect_speed_multiplier
		# Update speed if projectile has it
		if "speed" in projectile and parry_reflect_speed_multiplier != 1.0:
			projectile.speed *= parry_reflect_speed_multiplier
	
	# Change ownership to the parrier
	var parrier_node = _attacker_networked_player.get_node_or_null("Body") if _attacker_networked_player else null
	if not parrier_node:
		parrier_node = _attacker_networked_player
	
	# Use set_owner_info if available (preferred method)
	if projectile.has_method("set_owner_info"):
		projectile.set_owner_info(parrier_node, _attacker_peer_id)
	else:
		# Direct property assignment (works for all projectiles)
		if "owner_node" in projectile:
			projectile.owner_node = parrier_node
		if "owner_peer_id" in projectile:
			projectile.owner_peer_id = _attacker_peer_id
		# Update owner exclusions
		if "owner_exclusions" in projectile and parrier_node:
			projectile.owner_exclusions = _get_parrier_collision_bodies(parrier_node)
	
	# Update projectile rotation to face new direction
	if projectile is Node3D:
		var proj_node = projectile as Node3D
		proj_node.look_at(proj_node.global_position + reflect_direction)
	
	print("[HookMeleeAttack] Projectile parried! New owner: ", _attacker_peer_id, ", direction: ", reflect_direction)

func _get_parrier_collision_bodies(parrier: Node3D) -> Array:
	"""Get all collision bodies from the parrier for exclusion"""
	var collision_bodies: Array = []
	if not parrier:
		return collision_bodies
	
	# Recursively collect all CollisionObject3D nodes
	var nodes_to_check: Array = [parrier]
	while nodes_to_check.size() > 0:
		var current_node = nodes_to_check.pop_back()
		
		if current_node is CollisionObject3D:
			collision_bodies.append(current_node)
		
		# Add children to check
		for child in current_node.get_children():
			nodes_to_check.append(child)
	
	return collision_bodies

func _apply_knockback(target: CharacterBody3D) -> void:
	"""Apply horizontal knockback to the target"""
	var direction = (target.global_position - global_position).normalized()
	direction.y = 0  # Keep horizontal
	direction = direction.normalized()
	
	# Apply horizontal knockback
	target.velocity += direction * 5.0  # Adjust force as needed

func _find_parry_component() -> ParryComponent:
	"""Find ParryComponent in children"""
	for child in get_children():
		if child is ParryComponent:
			return child as ParryComponent
	return null
