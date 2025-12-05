extends Node3D
class_name BulletJumpModule

## Bullet Jump Module for Beaumont Character
## Allows spending 2 bullets from magazine to perform a double jump

@export_group("Module Settings")
@export var enabled: bool = true

@export_group("Bullet Jump Settings")
@export var bullet_cost: int = 2  # Number of bullets required for bullet jump
@export var jump_force: float = 4.5  # Vertical velocity applied on bullet jump
@export var cooldown_time: float = 0.6  # Seconds between bullet jumps
@export var bullet_jump_sound: AudioStream  # Optional sound effect for bullet jump
@export var audio_bus: String = "sfx"

# Node references
var player: CharacterBody3D
var weapon_manager: Node  # NetworkedWeaponManager or WeaponManager
var current_weapon: BaseWeapon  # Current weapon (RevolverProjectile)
var audio_player: AudioStreamPlayer
var viewmodel_node: Node3D  # Viewmodel to hide during bullet jump
var player_state: Node  # PlayerState node for viewmodel access

# Cooldown tracking
var cooldown_timer: float = 0.0
var is_on_cooldown: bool = false

# Ground detection tracking
var was_on_floor_previous_frame: bool = false
var time_since_left_ground: float = 0.0
const MIN_AIR_TIME: float = 0.05  # Minimum time in air before allowing bullet jump (prevents ground jump bug)

func _ready():
	# Get the player body
	player = get_node_or_null("../Body")
	if not player:
		# Try alternative path
		player = get_node_or_null("../../Body")
	
	if not player:
		push_error("BulletJumpModule: Could not find player Body node!")
		return
	
	# Setup audio player
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = audio_bus
	add_child(audio_player)
	
	# Find weapon manager - try multiple paths
	weapon_manager = _find_weapon_manager()
	
	if not weapon_manager:
		push_warning("BulletJumpModule: Could not find weapon manager. Bullet jump may not work.")
	else:
		print("BulletJumpModule: Found weapon manager: ", weapon_manager.name)
	
	# Find viewmodel node
	_find_viewmodel()
	
	# Find PlayerState node for viewmodel access (fallback)
	_find_player_state()
	
	print("BulletJumpModule: Initialized for ", get_parent().name)

func _is_local_player() -> bool:
	"""Check if this module belongs to the local player"""
	var networked_player = _find_networked_player()
	if networked_player:
		return networked_player.is_local_player()
	return false

func _find_networked_player() -> Node:
	"""Find the NetworkedPlayer parent node"""
	var node: Node = self
	while node:
		# Check if this is a NetworkedPlayer by checking for the is_local_player method
		# NetworkedPlayer is the only class that has this method in the player hierarchy
		if node.has_method("is_local_player") and node.has_method("get_pawn"):
			return node
		node = node.get_parent()
	return null

func _play_sound_3d(sound: AudioStream, position: Vector3) -> void:
	"""Play a 3D positional sound at the given position for all players"""
	if not sound:
		return
	
	var player_3d = AudioStreamPlayer3D.new()
	player_3d.stream = sound
	player_3d.bus = audio_bus
	player_3d.global_position = position
	player_3d.max_distance = 50.0
	player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	
	# Add to scene tree
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(player_3d)
		player_3d.play()
		# Clean up when finished
		player_3d.finished.connect(func(): player_3d.queue_free())

func _process(delta: float):
	if not enabled:
		return
	
	if not player:
		return
	
	# Only process input for local player
	if not _is_local_player():
		return
	
	# Track ground state to prevent ground jumps
	var is_currently_on_floor = player.is_on_floor()
	
	# Update time since leaving ground
	if is_currently_on_floor:
		time_since_left_ground = 0.0
		was_on_floor_previous_frame = true
	else:
		if was_on_floor_previous_frame:
			# Just left the ground - reset timer
			time_since_left_ground = 0.0
		time_since_left_ground += delta
		was_on_floor_previous_frame = false
	
	# Update cooldown timer
	if is_on_cooldown:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			is_on_cooldown = false
			cooldown_timer = 0.0
			# Restore viewmodel when cooldown ends
			_set_viewmodel_visible(true)
	
	# BULLET JUMP: Only works while in midair (not on ground)
	# Normal jump handles ground jumps, this only handles air jumps
	# Can be used repeatedly in midair as long as there's ammo and cooldown is ready
	if Input.is_action_just_pressed("pm_jump"):
		# CRITICAL: Multiple checks to ensure we're truly in midair
		# Check 1: is_on_floor() - primary check
		# Check 2: get_floor_normal() - if we have a floor normal, we're on ground
		# Check 3: velocity.y - if we're moving up significantly, we might have just jumped from ground
		# Check 4: time_since_left_ground - must have been in air for a minimum time
		if _is_truly_in_midair():
			attempt_bullet_jump()

func _find_weapon_manager() -> Node:
	# Try to find NetworkedWeaponManager or WeaponManager
	var root = get_tree().get_first_node_in_group("player")
	if not root:
		root = get_parent()
	
	# Search for weapon manager in common locations
	var search_paths = [
		"../Interpolated Camera/Arm/Arm Anchor/Camera/WeaponManager",
		"../../Interpolated Camera/Arm/Arm Anchor/Camera/WeaponManager",
		"../../../Interpolated Camera/Arm/Arm Anchor/Camera/WeaponManager",
	]
	
	for path_str in search_paths:
		var path = NodePath(path_str)
		var node = get_node_or_null(path)
		if node and (node is NetworkedWeaponManager or node.has_method("get_current_weapon")):
			return node
	
	# Recursive search
	return _find_weapon_manager_recursive(root)

func _find_weapon_manager_recursive(node: Node) -> Node:
	if not node:
		return null
	
	# Check if this node is a weapon manager
	if node is NetworkedWeaponManager or (node.has_method("get_current_weapon") and node.has_method("_fire_current_weapon")):
		return node
	
	# Search children
	for child in node.get_children():
		var result = _find_weapon_manager_recursive(child)
		if result:
			return result
	
	return null

func _is_truly_in_midair() -> bool:
	# Multiple checks to ensure player is truly in midair, not on ground
	if not player:
		return false
	
	# Check 1: is_on_floor() - primary floor detection (MOST IMPORTANT)
	if player.is_on_floor():
		return false
	
	# Check 2: Must have been in air for minimum time (prevents ground jump bug)
	# This ensures we didn't just leave the ground this frame
	if time_since_left_ground < MIN_AIR_TIME:
		return false
	
	# Check 3: get_floor_normal() - if we have a floor normal, we're touching ground
	# Note: This might not always work with GoldGdt, but it's an extra safety check
	var floor_normal = player.get_floor_normal()
	if floor_normal != Vector3.ZERO and floor_normal.length() > 0.1:
		return false
	
	# Check 4: If velocity.y is very positive, we might have just jumped from ground
	# Block if we have very large upward velocity (definitely just jumped from ground)
	if player.velocity.y > 3.0:
		# Very large upward velocity suggests we just jumped from ground
		return false
	
	return true

func attempt_bullet_jump() -> bool:
	# CRITICAL: Bullet jump can ONLY be used while in midair
	# This is checked first to prevent any ground usage with multiple validation checks
	if not _is_truly_in_midair():
		print("BulletJumpModule: Cannot bullet jump - player is on ground or just jumped from ground")
		return false
	
	if not enabled:
		return false
	
	# Check cooldown
	if is_on_cooldown:
		print("BulletJumpModule: Bullet jump on cooldown (", cooldown_timer, "s remaining)")
		return false
	
	# Get current weapon
	if not _update_current_weapon():
		print("BulletJumpModule: No weapon available")
		return false
	
	if not current_weapon:
		print("BulletJumpModule: Current weapon is null")
		return false
	
	# Check if weapon has enough ammo
	var ammo = _get_weapon_ammo()
	if ammo < bullet_cost:
		print("BulletJumpModule: Not enough ammo. Have: ", ammo, ", Need: ", bullet_cost)
		return false
	
	# Consume bullets
	if not _consume_bullets(bullet_cost):
		print("BulletJumpModule: Failed to consume bullets")
		return false
	
	# Apply jump force
	player.velocity.y = jump_force
	
	# Start cooldown timer
	is_on_cooldown = true
	cooldown_timer = cooldown_time
	
	# Hide viewmodel during bullet jump cooldown
	_set_viewmodel_visible(false)
	
	# Play sound effect
	if bullet_jump_sound:
		if _is_local_player():
			# Local player: play 2D sound (always audible)
		audio_player.stream = bullet_jump_sound
		audio_player.play()
		
		# All players: play 3D positional sound at player location
		_play_sound_3d(bullet_jump_sound, player.global_position)
	
	print("BulletJumpModule: Bullet jump executed! Consumed ", bullet_cost, " bullets. Remaining ammo: ", _get_weapon_ammo(), " (cooldown: ", cooldown_time, "s)")
	return true

func _update_current_weapon() -> bool:
	if not weapon_manager:
		weapon_manager = _find_weapon_manager()
		if not weapon_manager:
			return false
	
	# Get current weapon from weapon manager
	if weapon_manager.has_method("get_current_weapon"):
		current_weapon = weapon_manager.get_current_weapon()
	elif "current_weapon" in weapon_manager:
		current_weapon = weapon_manager.current_weapon
	else:
		# Try to get from weapons array
		if "weapons" in weapon_manager and weapon_manager.weapons.size() > 0:
			if "current_weapon_index" in weapon_manager:
				var index = weapon_manager.current_weapon_index
				if index >= 0 and index < weapon_manager.weapons.size():
					current_weapon = weapon_manager.weapons[index]
			else:
				current_weapon = weapon_manager.weapons[0]
	
	return current_weapon != null

func _get_weapon_ammo() -> int:
	if not current_weapon:
		return 0
	
	# Try different methods to get ammo
	if "ammo_in_clip" in current_weapon:
		return current_weapon.ammo_in_clip
	elif current_weapon.has_method("get_current_ammo"):
		return current_weapon.get_current_ammo()
	elif "current_ammo" in current_weapon:
		return current_weapon.current_ammo
	
	return 0

func _consume_bullets(amount: int) -> bool:
	if not current_weapon:
		return false
	
	# Directly modify ammo_in_clip if available
	if "ammo_in_clip" in current_weapon:
		if current_weapon.ammo_in_clip >= amount:
			current_weapon.ammo_in_clip -= amount
			# Emit ammo changed signal if available
			if current_weapon.has_signal("ammo_changed"):
				var max_ammo = current_weapon.clip_size if "clip_size" in current_weapon else 6
				current_weapon.emit_signal("ammo_changed", current_weapon.ammo_in_clip, max_ammo)
			return true
	
	# Try method-based consumption
	if current_weapon.has_method("consume_ammo"):
		return current_weapon.consume_ammo(amount)
	
	return false

func _find_viewmodel() -> void:
	"""Find and cache the viewmodel node"""
	# Try multiple possible paths for the viewmodel
	var possible_paths = [
		"../Interpolated Camera/Arm/Arm Anchor/Camera/WeaponManager/revolver_projectile/v_revolver",
		"../../Interpolated Camera/Arm/Arm Anchor/Camera/WeaponManager/revolver_projectile/v_revolver",
		"../../../Interpolated Camera/Arm/Arm Anchor/Camera/WeaponManager/revolver_projectile/v_revolver",
	]
	
	for path_str in possible_paths:
		var path = NodePath(path_str)
		viewmodel_node = get_node_or_null(path)
		if viewmodel_node:
			print("BulletJumpModule: Found viewmodel at path: ", path_str)
			return
	
	# If direct paths don't work, search recursively
	print("BulletJumpModule: Direct paths failed, searching for viewmodel recursively...")
	var root = get_parent()
	if root:
		viewmodel_node = _search_for_viewmodel(root)
		if viewmodel_node:
			print("BulletJumpModule: Found viewmodel via recursive search: ", viewmodel_node.get_path())
			return
	
	print("BulletJumpModule: WARNING - Could not find viewmodel node")

func _search_for_viewmodel(node: Node) -> Node3D:
	"""Recursively search for a node named 'v_revolver'"""
	if node.name == "v_revolver" and node is Node3D:
		return node as Node3D
	
	for child in node.get_children():
		var result = _search_for_viewmodel(child)
		if result:
			return result
	
	return null

func _find_player_state() -> void:
	"""Find PlayerState node as fallback for viewmodel access"""
	var possible_paths = [
		"../Body/PlayerState",
		"../../Body/PlayerState",
	]
	
	for path_str in possible_paths:
		var path = NodePath(path_str)
		player_state = get_node_or_null(path)
		if player_state:
			print("BulletJumpModule: Found PlayerState at path: ", path_str)
			return
	
	print("BulletJumpModule: WARNING - Could not find PlayerState node")

func _set_viewmodel_visible(visible: bool) -> void:
	"""Set viewmodel visibility with error handling"""
	# Try direct viewmodel node first
	if viewmodel_node and is_instance_valid(viewmodel_node):
		viewmodel_node.visible = visible
		print("BulletJumpModule: Set viewmodel visible to: ", visible)
		return
	
	# Fallback: Try using PlayerState's method if available
	if player_state and player_state.has_method("_set_viewmodel_visible"):
		# Note: This is a private method, but we can try calling it
		player_state.call("_set_viewmodel_visible", visible)
		print("BulletJumpModule: Set viewmodel via PlayerState to: ", visible)
		return
	
	print("BulletJumpModule: WARNING - Cannot set viewmodel visibility, node not found or invalid")

func is_bullet_jump_on_cooldown() -> bool:
	"""Public method to check if bullet jump is on cooldown (for weapon system)"""
	return is_on_cooldown

