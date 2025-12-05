extends "res://resource/scripts/weapons/base_weapon.gd"
class_name RevolverProjectile

# --- Revolver-specific projectile properties ----------------------------------
@export var projectile_scene: PackedScene  # Scene for physical bullet projectile
@export var projectile_speed: float = 80.0
@export var projectile_damage: int = 1  # Reduced from 25 to match 4 HP health system

# --- Audio properties ---------------------------------------------------------
@export var fire_sound: AudioStream  # Sound played when firing
@export var empty_sound: AudioStream  # Sound played when trying to fire with no ammo
@export var reload_sound: AudioStream  # Sound played when reloading

# --- Bullet-by-bullet reload settings -----------------------------------------
@export var reload_start_time: float = 0.8  # Time for reload_start animation
@export var reload_bullet_time: float = 0.4  # Time per bullet during reload_loop
@export var reload_end_time: float = 0.6  # Time for reload_end animation

# --- Auto-reload settings -----------------------------------------------------
@export var auto_reload_delay: float = 1.5  # Seconds of not firing before auto-reload starts
@export var auto_reload_enabled: bool = true

# --- Internal reload state tracking --------------------------------------------
var is_reloading: bool = false
var reload_stage: String = "none"  # "none", "start", "loop", "end"
var bullets_loaded: int = 0
var target_bullets: int = 0

# --- Timers for bullet-by-bullet reload ----------------------------------------
var reload_loop_timer: Timer
var auto_reload_timer: Timer
var last_fire_time: float = 0.0

# --- Override base values ------------------------------------------------------
func _ready() -> void:
	# Set revolver-specific defaults if not already set
	if clip_size == 6:  # Only override if using base default
		clip_size = 6
		ammo_in_clip = clip_size
	
	# Call base _ready to set up base timers
	super._ready()
	
	# Setup bullet-by-bullet reload loop timer
	reload_loop_timer = Timer.new()
	reload_loop_timer.one_shot = true
	reload_loop_timer.timeout.connect(_on_reload_loop_timeout)
	add_child(reload_loop_timer)
	
	# Setup auto-reload timer
	auto_reload_timer = Timer.new()
	auto_reload_timer.one_shot = true
	auto_reload_timer.timeout.connect(_on_auto_reload_timeout)
	add_child(auto_reload_timer)
	
	# Reset last fire time
	last_fire_time = Time.get_ticks_msec() / 1000.0
	
	# Ensure reload timer is stopped initially so weapon can fire
	_reload_timer.stop()

# --- Override shoot to use projectiles instead of hitscan ----------------------
func shoot() -> void:
	# Attempt to fire a single round (projectile-based)
	print("RevolverProjectile: shoot() called - _can_fire=", _can_fire, " ammo=", ammo_in_clip, " is_reloading=", is_reloading, " _reload_timer.time_left=", _reload_timer.time_left)
	
	# RELOAD CANCELLING: If we're reloading, cancel it and allow firing
	# This must be checked BEFORE _can_fire check so we can cancel reload and set _can_fire = true
	if is_reloading:
		print("RevolverProjectile: Cancelling reload to fire")
		# Cancel all reload timers
		_reload_timer.stop()
		reload_loop_timer.stop()
		if auto_reload_timer.time_left > 0:
			auto_reload_timer.stop()
		# Reset reload state
		is_reloading = false
		reload_stage = "none"
		bullets_loaded = 0
		target_bullets = 0
		# Allow firing immediately
		_can_fire = true
		# Reset reload timer wait time to ensure it's truly stopped
		_reload_timer.wait_time = 0.0
		print("RevolverProjectile: Reload cancelled, ready to fire")
	
	# BULLET JUMP COOLDOWN: Prevent firing during bullet jump cooldown
	var bullet_jump_module = _find_bullet_jump_module()
	if bullet_jump_module and bullet_jump_module.is_bullet_jump_on_cooldown():
		print("RevolverProjectile: Cannot fire - bullet jump on cooldown")
		return
	
	if not _can_fire:
		print("RevolverProjectile: Cannot fire - _can_fire is false")
		return
	if ammo_in_clip <= 0:
		print("RevolverProjectile: Cannot fire - no ammo")
		if empty_sound:
			_play_sound(empty_sound)
		return
	
	# Ensure reload timer is stopped when firing (weapon manager checks this)
	_reload_timer.stop()
	_reload_timer.wait_time = 0.0
	
	print("RevolverProjectile: shoot() called, firing projectile...")
	
	# Update last fire time and cancel auto-reload
	last_fire_time = Time.get_ticks_msec() / 1000.0
	if auto_reload_timer.time_left > 0:
		auto_reload_timer.stop()
	
	ammo_in_clip -= 1
	emit_signal("ammo_changed", ammo_in_clip, clip_size)
	
	# Play fire sound
	if fire_sound:
		_play_sound(fire_sound)
	
	_spawn_muzzle_flash()
	_fire_projectile()
	
	_can_fire = false
	_fire_timer.start(fire_rate)
	
	emit_signal("fired")
	
	# Start auto-reload timer if enabled and not full
	if auto_reload_enabled and ammo_in_clip < clip_size:
		auto_reload_timer.wait_time = auto_reload_delay
		auto_reload_timer.start()

# --- Override reload to use bullet-by-bullet system ---------------------------
func start_reload() -> void:
	if is_reloading or ammo_in_clip >= clip_size:
		return
	
	# Cancel auto-reload timer if it's running
	if auto_reload_timer.time_left > 0:
		auto_reload_timer.stop()
	
	is_reloading = true
	reload_stage = "start"
	bullets_loaded = 0
	target_bullets = clip_size - ammo_in_clip
	_can_fire = false
	
	# Play reload sound
	if reload_sound:
		_play_sound(reload_sound)
	
	emit_signal("reload_started")
	
	# Start reload sequence
	_reload_timer.wait_time = reload_start_time
	_reload_timer.start()
	
	# Debug: Ensure reload timer is actually running
	print("Revolver: start_reload() - is_reloading=", is_reloading, " _reload_timer.time_left=", _reload_timer.time_left)

# --- Fire physical projectile -------------------------------------------------
func _fire_projectile() -> void:
	print("RevolverProjectile: _fire_projectile() called")
	if projectile_scene == null:
		printerr("RevolverProjectile: projectile_scene not assigned!")
		return
	print("RevolverProjectile: projectile_scene is assigned: ", projectile_scene.resource_path)
	
	var muzzle: Node3D = get_node_or_null(muzzle_path)
	if muzzle == null:
		muzzle = self
	
	var origin: Vector3 = muzzle.global_position
	var weapon_basis: Basis = muzzle.global_transform.basis
	var direction: Vector3 = -weapon_basis.z
	
	# Apply spread (same as base weapon)
	if spread_degrees > 0.0:
		direction = direction.rotated(weapon_basis.x, deg_to_rad(randf_range(-spread_degrees, spread_degrees)))
		direction = direction.rotated(weapon_basis.y, deg_to_rad(randf_range(-spread_degrees, spread_degrees)))
		direction = direction.normalized()
	
	# Instantiate projectile
	var projectile = projectile_scene.instantiate()
	if not projectile:
		printerr("RevolverProjectile: Failed to instantiate projectile!")
		return
	
	# Get owner information for ownership tracking
	var owner_node = _get_owner_node()
	var owner_id = _get_owner_peer_id()
	
	print("RevolverProjectile: Owner node: ", owner_node, ", Owner peer_id: ", owner_id)
	
	# Get all collision bodies from owner to exclude from projectile collisions
	var owner_collision_bodies = _get_owner_collision_bodies(owner_node)
	
	# Set projectile properties BEFORE adding to scene (like weapon_system.gd does)
	if "damage" in projectile:
		var final_damage = projectile_damage if projectile_damage > 0 else bullet_damage
		projectile.damage = final_damage
	
	if "speed" in projectile:
		projectile.speed = projectile_speed
	
	# Set decal properties if projectile supports them
	if "bullet_decal_texture" in projectile:
		projectile.bullet_decal_texture = bullet_decal_texture
	if "bullet_decal_size" in projectile:
		projectile.bullet_decal_size = bullet_decal_size
	if "bullet_decal_lifetime" in projectile:
		projectile.bullet_decal_lifetime = bullet_decal_lifetime
	
	# Add to scene tree first
	var scene_root = get_tree().current_scene
	scene_root.add_child(projectile)
	
	# Set the projectile as top-level so position is in global space
	if projectile is Node3D:
		(projectile as Node3D).set_as_top_level(true)
		# Set global position first to ensure it's in the right place
		(projectile as Node3D).global_position = origin
	
	# Initialize projectile with owner info
	if projectile.has_method("initialize"):
		# Use initialize method if available (like Projectile class)
		projectile.initialize(origin, direction, owner_node, owner_id)
		# Ensure global position is correct after initialize (in case initialize changed it)
		if projectile is Node3D:
			(projectile as Node3D).global_position = origin
		print("RevolverProjectile: Projectile initialized at ", origin, " with direction ", direction)
	else:
		# Fallback: set properties directly
		if projectile is Node3D:
			projectile.global_position = origin
			projectile.look_at(origin + direction)
			print("RevolverProjectile: Projectile positioned at ", origin)
	
	# Set owner info using various methods (for compatibility)
	# Note: initialize() already sets owner info, but we call this as a fallback
	if projectile.has_method("set_owner_info"):
		projectile.set_owner_info(owner_node, owner_id)
	
	# Set owner exclusions directly if projectile supports it
	# (initialize() and set_owner_info() should handle this, but set it directly as backup)
	if "owner_exclusions" in projectile:
		projectile.owner_exclusions = owner_collision_bodies

# --- Get owner node for projectile ownership tracking -------------------------
func _get_owner_node() -> Node3D:
	# Walk up the tree to find the player/owner
	var node = get_parent()
	while node:
		if node.has_method("take_damage") or node.is_in_group("player"):
			return node as Node3D
		node = node.get_parent()
	return null

# --- Get all collision bodies from owner for exclusion ------------------------
func _get_owner_collision_bodies(owner: Node3D) -> Array:
	var collision_bodies: Array = []
	if not owner:
		return collision_bodies
	
	# Recursively collect all CollisionObject3D nodes (CharacterBody3D, RigidBody3D, StaticBody3D, Area3D)
	var nodes_to_check: Array = [owner]
	while nodes_to_check.size() > 0:
		var current_node = nodes_to_check.pop_back()
		
		if current_node is CollisionObject3D:
			collision_bodies.append(current_node)
		
		# Add children to check
		for child in current_node.get_children():
			nodes_to_check.append(child)
	
	return collision_bodies

# --- Get owner peer ID for networked ownership tracking -----------------------
func _get_owner_peer_id() -> int:
	# Use universal ownership utility to find NetworkedPlayer and get peer_id
	var networked_player = NetworkedProjectileOwnership.get_owner_networked_player(self)
	if networked_player:
		print("[RevolverProjectile] Found NetworkedPlayer in hierarchy: ", networked_player.player_name, " (peer_id: ", networked_player.peer_id, ")")
		return networked_player.peer_id
	else:
		# Debug: Walk up the tree to see what we find
		print("[RevolverProjectile] WARNING: Could not find NetworkedPlayer in parent hierarchy!")
		var node = self
		var path = ""
		while node:
			path = node.name + " -> " + path
			node = node.get_parent()
		print("[RevolverProjectile] Hierarchy: ", path)
	
	# Fallback: try to find owner node and get peer_id from it
	var owner = _get_owner_node()
	if owner:
		if owner.has_method("get_peer_id"):
			return owner.get_peer_id()
		# Check if owner has a peer_id property (for NetworkedPlayer, etc.)
		if "peer_id" in owner:
			return owner.peer_id
	return -1

# --- Bullet-by-bullet reload system -------------------------------------------
func _on_reload_timeout() -> void:
	# Override base class reload timeout to use bullet-by-bullet system
	if reload_stage == "start":
		start_reload_loop()
	elif reload_stage == "end":
		complete_reload()
	else:
		# Fallback to base behavior if somehow in wrong state
		super._on_reload_timeout()

func start_reload_loop() -> void:
	reload_stage = "loop"
	bullets_loaded = 0
	
	# Stop the base reload timer so weapon manager knows we can fire during loop
	# (We use reload_loop_timer for the actual bullet loading)
	_reload_timer.stop()
	_reload_timer.wait_time = 0.0  # Reset to ensure it's truly stopped
	
	# Start loading first bullet
	reload_loop_timer.wait_time = reload_bullet_time
	reload_loop_timer.start()
	
	print("Revolver: start_reload_loop() - _reload_timer.time_left=", _reload_timer.time_left)

func _on_reload_loop_timeout() -> void:
	load_bullet()

func load_bullet() -> void:
	bullets_loaded += 1
	ammo_in_clip += 1
	emit_signal("ammo_changed", ammo_in_clip, clip_size)
	
	print("Revolver: Bullet loaded: ", bullets_loaded, "/", target_bullets)
	
	if bullets_loaded >= target_bullets:
		# All bullets loaded, finish reload
		finish_reload()
	else:
		# Continue loading next bullet
		reload_loop_timer.start()

func finish_reload() -> void:
	reload_stage = "end"
	
	# Use base reload timer for end stage
	_reload_timer.wait_time = reload_end_time
	_reload_timer.start()

func complete_reload() -> void:
	is_reloading = false
	reload_stage = "none"
	bullets_loaded = 0
	target_bullets = 0
	_can_fire = true
	
	# Ensure reload timer is stopped so weapon manager knows we can fire
	_reload_timer.stop()
	_reload_timer.wait_time = 0.0  # Reset wait time to ensure it's truly stopped
	
	print("Revolver: Reload complete! Ammo: ", ammo_in_clip, " _reload_timer.time_left=", _reload_timer.time_left)
	emit_signal("ammo_changed", ammo_in_clip, clip_size)
	emit_signal("reload_finished")

# --- Auto-reload system -------------------------------------------------------
func _on_auto_reload_timeout() -> void:
	# Check if we should start auto-reload
	if auto_reload_enabled and not is_reloading and ammo_in_clip < clip_size:
		start_reload()


# --- Override to fix weapon manager compatibility ------------------------------
# The weapon manager checks _reload_timer.time_left, but we use is_reloading
# We need to ensure _reload_timer is stopped when we're not actively blocking firing
# This is handled by stopping _reload_timer in complete_reload() and start_reload_loop()

# --- Getter functions for external systems ------------------------------------
func is_weapon_reloading() -> bool:
	return is_reloading

func get_reload_stage() -> String:
	return reload_stage

func get_bullets_loaded() -> int:
	return bullets_loaded

func get_target_bullets() -> int:
	return target_bullets

func _find_bullet_jump_module() -> Node:
	"""Find BulletJumpModule in the player hierarchy"""
	# Walk up the tree to find the player/owner
	var node = get_parent()
	while node:
		# Check if this node has a BulletJump child
		var bullet_jump = node.get_node_or_null("BulletJump")
		if bullet_jump and bullet_jump.has_method("is_bullet_jump_on_cooldown"):
			return bullet_jump
		
		# Also check if this node itself is the bullet jump module
		if node.has_method("is_bullet_jump_on_cooldown"):
			return node
		
		node = node.get_parent()
	
	return null
