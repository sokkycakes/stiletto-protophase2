extends WeaponManager
class_name NetworkedWeaponManager

## Networked version of WeaponManager with server authority and client prediction
## Extends existing WeaponManager functionality with multiplayer synchronization

# --- Network Configuration ---
var player_peer_id: int = -1
var server_authority: bool = true

# --- Weapon Type References ---
# Melee knife variants use custom shoot() logic instead of generic hitscan.
const KnifeBaseScript = preload("res://resource/scripts/weapons/vagrant_knife.gd")
const KnifeScript = preload("res://resource/scripts/weapons/vagrant_knife_test1.gd")

# --- Client Prediction ---
var predicted_shots: Array[Dictionary] = []
var max_prediction_shots: int = 10
var prediction_timeout: float = 1.0

# --- Network State ---
var last_weapon_index: int = -1
var weapon_sync_timer: Timer

# --- Recoil & Spread Sync ---
var network_recoil: Vector2 = Vector2.ZERO
var network_spread_penalty: float = 0.0

# --- Reload Timer Display ---
@export var reload_timer_label_path: NodePath
var _reload_timer_label: Label = null

# --- New Signals ---
signal weapon_fired_networked(weapon_name: String, shot_data: Dictionary)
signal weapon_hit_confirmed(shot_id: int, hit_data: Dictionary)
signal weapon_hit_rejected(shot_id: int)

func _ready() -> void:
	super._ready()
	
	# Set up network sync timer
	weapon_sync_timer = Timer.new()
	weapon_sync_timer.wait_time = 0.1  # 10 FPS weapon state sync
	weapon_sync_timer.timeout.connect(_sync_weapon_state)
	add_child(weapon_sync_timer)
	
	if not is_authority():
		weapon_sync_timer.start()
	
	# Get reload timer label if path is provided
	if reload_timer_label_path != NodePath("") and has_node(reload_timer_label_path):
		_reload_timer_label = get_node(reload_timer_label_path)
		_update_reload_timer_display()

func _input(_event: InputEvent) -> void:
	# Only process input if we have authority
	if not is_authority():
		return
	# Use the global Input singleton to query actions (avoid binding to event types)
	# Handle firing with network prediction
	if Input.is_action_just_pressed(fire_action):
		print("NetworkedWeaponManager: Fire action pressed!")
		_fire_current_weapon_networked()
		return

	# Handle reloading
	if Input.is_action_just_pressed(reload_action):
		_reload_current_weapon_networked()
		return

	# Handle melee attack
	if Input.is_action_just_pressed("melee"):
		_perform_melee_attack_networked()
		return

	# Handle weapon switching
	for i in range(weapon_switch_actions.size()):
		if Input.is_action_just_pressed(weapon_switch_actions[i]):
			_switch_weapon_networked(i)
			break

# --- Network Authority Setup ---

func setup_for_player(peer_id: int) -> void:
	player_peer_id = peer_id
	set_multiplayer_authority(peer_id)
	
	# Only authority player processes input
	if not is_authority():
		set_process_input(false)
	
	print("NetworkedWeaponManager setup for peer: ", peer_id)

func is_authority() -> bool:
	return is_multiplayer_authority()

func is_server() -> bool:
	return MultiplayerManager.is_server()

## Helper to find NetworkedPlayer from parent hierarchy
func _find_networked_player() -> NetworkedPlayer:
	var node := get_parent()
	while node:
		if node is NetworkedPlayer:
			return node
		node = node.get_parent()
	return null

# --- Networked Weapon Actions ---

func _fire_current_weapon_networked() -> void:
	print("NetworkedWeaponManager: _fire_current_weapon_networked() called")
	if not current_weapon:
		print("NetworkedWeaponManager: No current weapon!")
		return
	
	var can_fire = _can_fire_weapon(current_weapon)
	print("NetworkedWeaponManager: can_fire=", can_fire, " ammo=", current_weapon.ammo_in_clip, " reload_timer=", current_weapon._reload_timer.time_left)
	if not can_fire:
		print("NetworkedWeaponManager: Cannot fire - blocked by _can_fire_weapon()")
		return

	# Special-case melee knives: let their custom shoot() handle traces, sounds, and decals.
	# These weapons already encapsulate their own hit logic and feedback.
	if current_weapon is KnifeBaseScript or current_weapon is KnifeScript:
		current_weapon.shoot()
		return
	
	# For weapons with shoot() method, call it and broadcast visual effects to other clients
	if current_weapon.has_method("shoot"):
		print("NetworkedWeaponManager: Calling current_weapon.shoot()")
		current_weapon.shoot()
		
		# Broadcast visual effects to other clients
		_broadcast_weapon_fire_visuals()
		return
	
	# Generate unique shot ID for prediction tracking
	var shot_id = int(Time.get_unix_time_from_system() * 1000.0) + randi() % 1000
	
	# Create shot data
	var shot_data = {
		"shot_id": shot_id,
		"weapon_name": current_weapon.name,
		"origin": _get_muzzle_position(),
		"direction": _get_fire_direction(),
		"spread": current_weapon.spread_degrees,
		"damage": current_weapon.bullet_damage,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if is_server():
		# Server has final authority
		_process_weapon_fire_server(shot_data)
	else:
		# Client prediction
		_process_weapon_fire_prediction(shot_data)
		
		# Request server validation
		request_weapon_fire.rpc_id(1, shot_data)

func _reload_current_weapon_networked() -> void:
	if not current_weapon or not _can_reload_weapon(current_weapon):
		return
	
	if is_server():
		_reload_current_weapon()
		sync_weapon_reload.rpc(current_weapon.name)
	else:
		# Request reload from server
		request_weapon_reload.rpc_id(1, current_weapon.name)

func _switch_weapon_networked(weapon_index: int) -> void:
	if weapon_index < 0 or weapon_index >= weapons.size():
		return
	
	if is_server():
		_switch_weapon(weapon_index)
		sync_weapon_switch.rpc(weapon_index)
	else:
		# Request weapon switch from server
		request_weapon_switch.rpc_id(1, weapon_index)

func _perform_melee_attack_networked() -> void:
	"""Perform melee attack - client-side only for now"""
	var hook_melee = get_node_or_null("../HookMeleeAttack")
	if hook_melee and hook_melee.has_method("perform_attack"):
		hook_melee.perform_attack()
	else:
		# Try finding it as a sibling of camera
		var camera = get_node_or_null("..")
		if camera:
			hook_melee = camera.get_node_or_null("HookMeleeAttack")
			if hook_melee and hook_melee.has_method("perform_attack"):
				hook_melee.perform_attack()

# --- Server Authority Methods ---

func _process_weapon_fire_server(shot_data: Dictionary) -> void:
	if not is_server():
		return
	
	# Validate shot on server
	if not _validate_shot(shot_data):
		# Reject shot
		reject_weapon_fire.rpc_id(player_peer_id, shot_data["shot_id"])
		return
	
	# Process the shot
	_execute_weapon_fire(shot_data)
	
	# Broadcast to all clients
	confirm_weapon_fire.rpc(shot_data)

func _validate_shot(shot_data: Dictionary) -> bool:
	# Server-side validation
	if not current_weapon:
		return false
	
	# Check if weapon can fire
	if not _can_fire_weapon(current_weapon):
		return false
	
	# Check timing (anti-cheat)
	var time_diff = Time.get_unix_time_from_system() - shot_data["timestamp"]
	if time_diff > 2.0:  # Allow 2 second tolerance for network lag
		return false
	
	# Check weapon name matches
	if shot_data["weapon_name"] != current_weapon.name:
		return false
	
	return true

func _execute_weapon_fire(shot_data: Dictionary) -> void:
	# Execute the actual shot with server authority
	if current_weapon:
		# Use the shot data to perform hitscan
		_perform_networked_hitscan(shot_data)
		
		# Update weapon state
		current_weapon.ammo_in_clip -= 1
		current_weapon.emit_signal("ammo_changed", current_weapon.ammo_in_clip, current_weapon.clip_size)
		
		# Handle fire rate
		current_weapon._can_fire = false
		current_weapon._fire_timer.start(current_weapon.fire_rate)
		
		# Emit fired signal
		current_weapon.emit_signal("fired")
		weapon_fired_networked.emit(shot_data["weapon_name"], shot_data)
		# If this weapon spawns a projectile, broadcast to other peers
		if current_weapon and "projectile_scene" in current_weapon and current_weapon.projectile_scene:
			var origin = _get_muzzle_position()
			var direction = _get_fire_direction()
			var projectile_path = ""
			if current_weapon.projectile_scene:
				projectile_path = current_weapon.projectile_scene.resource_path
			if projectile_path != "":
				# Get owner information for ownership tracking
				var owner_peer_id = player_peer_id
				var networked_player = _find_networked_player()
				if networked_player:
					owner_peer_id = networked_player.peer_id
				
				spawn_weapon_projectile.rpc(origin, direction, projectile_path, owner_peer_id)

# --- Client Prediction Methods ---

func _process_weapon_fire_prediction(shot_data: Dictionary) -> void:
	# Store for prediction tracking
	predicted_shots.append({
		"shot_data": shot_data,
		"timestamp": Time.get_unix_time_from_system()
	})
	
	# Limit prediction buffer
	if predicted_shots.size() > max_prediction_shots:
		predicted_shots.pop_front()
	
	# Perform client-side prediction
	_execute_prediction_fire(shot_data)

func _execute_prediction_fire(shot_data: Dictionary) -> void:
	# Visual/audio feedback for responsive gameplay
	if current_weapon:
		current_weapon._spawn_muzzle_flash()
		# Don't consume ammo or start timers - wait for server confirmation
		
		# Visual effects only
		_perform_prediction_hitscan(shot_data)

func _perform_prediction_hitscan(shot_data: Dictionary) -> void:
	# Perform hitscan for visual effects only (no damage)
	var origin = shot_data["origin"]
	var direction = shot_data["direction"]
	var max_distance = current_weapon.maximum_distance if current_weapon else 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * max_distance)
	query.exclude = [self]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	var hit_pos = origin + direction * max_distance
	var hit_normal = Vector3.UP
	
	if result:
		hit_pos = result.position
		hit_normal = result.normal
	
	# Visual effects only
	if current_weapon:
		current_weapon._spawn_bullet_trail(origin, hit_pos)
		current_weapon._spawn_impact(hit_pos, hit_normal)

func _perform_networked_hitscan(shot_data: Dictionary) -> void:
	# Server authoritative hitscan with lag compensation
	var origin = shot_data["origin"]
	var direction = shot_data["direction"]
	var damage = shot_data["damage"]
	var max_distance = current_weapon.maximum_distance if current_weapon else 1000.0
	
	# Calculate lag compensation time
	var current_time = Time.get_ticks_msec() / 1000.0
	var shot_timestamp = shot_data.get("timestamp", current_time)
	
	# Calculate latency: time between when shot was fired and now
	# Add interpolation delay to account for client-side interpolation
	var latency = current_time - shot_timestamp
	var interpolation_delay = 0.05  # Client interpolation delay (matches NetworkedPlayer default)
	var total_lag = latency + interpolation_delay
	
	# Clamp lag compensation to reasonable bounds (0 to 200ms)
	total_lag = clamp(total_lag, 0.0, 0.2)
	
	# Calculate target time to rewind to
	var target_time = current_time - total_lag
	
	# Rewind all players (except shooter) to the time when the shot was fired
	var rewound_players: Array[NetworkedPlayer] = []
	if total_lag > 0.01:  # Only rewind if lag is significant (>10ms)
		rewound_players = NetworkedPlayer.rewind_all_players(target_time, player_peer_id)
	
	# Perform hitscan with rewound positions
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * max_distance)
	query.exclude = [self]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	var hit_pos = origin + direction * max_distance
	var hit_normal = Vector3.UP
	var hit_target = null
	
	if result:
		hit_pos = result.position
		hit_normal = result.normal
		hit_target = result.collider
		
		# Apply damage on server (using rewound positions)
		if hit_target and hit_target.has_method("take_damage"):
			hit_target.take_damage(damage, player_peer_id)
	
	# Restore all players to their real positions
	if rewound_players.size() > 0:
		NetworkedPlayer.restore_all_players(rewound_players)
	
	# Broadcast hit effects to all clients
	sync_weapon_hit.rpc(origin, hit_pos, hit_normal, hit_target != null)

# --- RPC Methods ---

@rpc("any_peer", "call_remote", "reliable")
func request_weapon_fire(shot_data: Dictionary) -> void:
	if is_server():
		_process_weapon_fire_server(shot_data)

@rpc("any_peer", "call_remote", "reliable")
func request_weapon_reload(weapon_name: String) -> void:
	if is_server() and current_weapon and current_weapon.name == weapon_name:
		_reload_current_weapon()
		sync_weapon_reload.rpc(weapon_name)

@rpc("any_peer", "call_remote", "reliable")
func request_weapon_switch(weapon_index: int) -> void:
	if is_server():
		_switch_weapon(weapon_index)
		sync_weapon_switch.rpc(weapon_index)

@rpc("authority", "call_local", "reliable")
func confirm_weapon_fire(shot_data: Dictionary) -> void:
	# Remove from prediction buffer if this was our shot
	_remove_predicted_shot(shot_data["shot_id"])
	
	# Execute visual effects if not authority
	if not is_authority():
		_execute_confirmed_fire(shot_data)

@rpc("authority", "call_remote", "reliable")
func reject_weapon_fire(shot_id: int) -> void:
	# Remove from prediction buffer
	_remove_predicted_shot(shot_id)
	weapon_hit_rejected.emit(shot_id)

@rpc("authority", "call_local", "reliable")
func sync_weapon_reload(weapon_name: String) -> void:
	if not is_authority() and current_weapon and current_weapon.name == weapon_name:
		current_weapon.start_reload()
		_update_reload_timer_display()

@rpc("authority", "call_local", "reliable")
func sync_weapon_switch(weapon_index: int) -> void:
	if not is_authority():
		_switch_weapon(weapon_index)

@rpc("any_peer", "call_remote", "reliable")
func sync_weapon_hit(origin: Vector3, hit_pos: Vector3, hit_normal: Vector3, _did_hit: bool) -> void:
	# This RPC is called by the shooting player to broadcast visual effects to other clients
	# Use "call_remote" to avoid double trails (shooter already spawned locally)
	if current_weapon:
		current_weapon._spawn_bullet_trail(origin, hit_pos)
		current_weapon._spawn_impact(hit_pos, hit_normal)

@rpc("authority", "call_local", "unreliable")
func sync_weapon_state(weapon_index: int, ammo: int, _is_reloading: bool) -> void:
	if not is_authority() and weapon_index < weapons.size():
		var weapon = weapons[weapon_index]
		weapon.ammo_in_clip = ammo
		# Update reload state if needed

# --- Helper Methods ---

func _broadcast_weapon_fire_visuals() -> void:
	"""Broadcast weapon firing visuals (bullet trail, muzzle flash, projectile) to other clients"""
	if not current_weapon:
		return
	
	var origin = _get_muzzle_position()
	var direction = _get_fire_direction()
	
	# Check if this is a projectile weapon
	if "projectile_scene" in current_weapon and current_weapon.projectile_scene:
		var projectile_path = current_weapon.projectile_scene.resource_path
		if projectile_path != "":
			# Get owner information for ownership tracking
			var owner_peer_id = player_peer_id
			var networked_player = _find_networked_player()
			if networked_player:
				owner_peer_id = networked_player.peer_id
			
			# Broadcast projectile spawn to other clients
			spawn_weapon_projectile.rpc(origin, direction, projectile_path, owner_peer_id)
			print("[NetworkedWeaponManager] Broadcast projectile spawn to other clients")
	else:
		# Hitscan weapon - do a raycast to find hit position for visual effects
		var max_distance = current_weapon.maximum_distance if current_weapon else 1000.0
		
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * max_distance)
		query.exclude = [self]
		query.collide_with_areas = true
		query.collide_with_bodies = true
		
		var result = space_state.intersect_ray(query)
		
		var hit_pos = origin + direction * max_distance
		var hit_normal = Vector3.UP
		var did_hit = false
		
		if result:
			hit_pos = result.position
			hit_normal = result.normal
			did_hit = true
		
		# Broadcast visual effects to other clients
		sync_weapon_hit.rpc(origin, hit_pos, hit_normal, did_hit)
		print("[NetworkedWeaponManager] Broadcast hitscan visuals to other clients")

func _execute_confirmed_fire(_shot_data: Dictionary) -> void:
	# Execute server-confirmed shot for non-authority clients
	if current_weapon:
		current_weapon._spawn_muzzle_flash()
		# Don't need to do hitscan - server already sent hit results

func _remove_predicted_shot(shot_id: int) -> void:
	for i in range(predicted_shots.size() - 1, -1, -1):
		if predicted_shots[i]["shot_data"]["shot_id"] == shot_id:
			predicted_shots.remove_at(i)
			break

func _get_muzzle_position() -> Vector3:
	var muzzle = get_node_or_null(muzzle_path) if muzzle_path else null
	return muzzle.global_position if muzzle else global_position

func _get_fire_direction() -> Vector3:
	var muzzle = get_node_or_null(muzzle_path) if muzzle_path else null
	var weapon_basis = muzzle.global_transform.basis if muzzle else global_transform.basis
	var direction = -weapon_basis.z
	
	# Apply spread
	if current_weapon and current_weapon.spread_degrees > 0.0:
		var spread_rad = deg_to_rad(current_weapon.spread_degrees)
		direction = direction.rotated(weapon_basis.x, randf_range(-spread_rad, spread_rad))
		direction = direction.rotated(weapon_basis.y, randf_range(-spread_rad, spread_rad))
		direction = direction.normalized()
	
	return direction

func _process(_delta: float) -> void:
	super._process(_delta)
	# Update reload timer display during reload
	if current_weapon and _reload_timer_label:
		_update_reload_timer_display()

func _sync_weapon_state() -> void:
	if is_authority() and current_weapon:
		var is_reloading = current_weapon._reload_timer.time_left > 0
		# Use unreliable RPC via the annotated method's rpc() call
		sync_weapon_state.rpc(_current_weapon_index, current_weapon.ammo_in_clip, is_reloading)

func _cleanup_old_predictions() -> void:
	var current_time = Time.get_unix_time_from_system()
	for i in range(predicted_shots.size() - 1, -1, -1):
		if current_time - predicted_shots[i]["timestamp"] > prediction_timeout:
			predicted_shots.remove_at(i)

func get_remaining_reload_time() -> float:
	"""Calculate the remaining reload time for the current weapon"""
	if not current_weapon:
		return 0.0
	
	# Check if weapon is reloading
	var time_left = current_weapon._reload_timer.time_left
	if time_left > 0:
		return time_left
	
	# For weapons with custom reload systems (like revolver with bullet-by-bullet)
	if current_weapon.has_method("is_weapon_reloading") and current_weapon.is_weapon_reloading():
		# Try to get remaining time from weapon's custom method
		if current_weapon.has_method("get_remaining_reload_time"):
			return current_weapon.get_remaining_reload_time()
		# Fallback: check reload timer again
		return max(0.0, current_weapon._reload_timer.time_left)
	
	return 0.0

func _update_reload_timer_display() -> void:
	"""Update the reload timer label with countdown"""
	if not _reload_timer_label:
		return
	
	var remaining_time = get_remaining_reload_time()
	
	if remaining_time > 0:
		# Format to 1 decimal place, countdown
		_reload_timer_label.text = "%.1f" % remaining_time
		_reload_timer_label.visible = true
	else:
		_reload_timer_label.visible = false
		_reload_timer_label.text = "0.0"

# --- Override parent methods to add networking ---

func _reload_current_weapon() -> void:
	super._reload_current_weapon()
	_update_reload_timer_display()

func _connect_weapon_signals() -> void:
	super._connect_weapon_signals()
	if not current_weapon:
		return
	
	# Connect to reload_started signal if available
	if current_weapon.has_signal("reload_started"):
		if not current_weapon.reload_started.is_connected(_on_weapon_reload_started):
			current_weapon.reload_started.connect(_on_weapon_reload_started)

func _on_weapon_reload_started() -> void:
	_update_reload_timer_display()

func _on_weapon_reloaded() -> void:
	# Call parent implementation
	super._on_weapon_reloaded()
	# Update reload timer display
	_update_reload_timer_display()

func _switch_weapon(weapon_index: int) -> void:
	super._switch_weapon(weapon_index)
	last_weapon_index = weapon_index
	_update_reload_timer_display()
 
@rpc("any_peer", "call_remote", "unreliable")
func spawn_weapon_projectile(origin: Vector3, direction: Vector3, projectile_path: String, owner_peer_id: int = -1) -> void:
	# Only spawn on non-authoritative peers; server already spawned locally
	if is_authority():
		return
	# Spawn a projectile on all peers, using the provided projectile scene path
	if projectile_path == "" or projectile_path == null:
		return
	var scene = load(projectile_path) as PackedScene
	if not scene:
		return
	var proj = scene.instantiate() as Node3D
	if not proj:
		return
	
	# Add to scene tree first (needed for some initialization methods)
	get_tree().current_scene.add_child(proj)
	
	# Set the projectile as top-level so position is in global space
	if proj is Node3D:
		(proj as Node3D).set_as_top_level(true)
		(proj as Node3D).global_position = origin
	
	# Mark as visual-only since this is a remote copy (original deals damage)
	if "is_visual_only" in proj:
		proj.is_visual_only = true
		print("[NetworkedWeaponManager] Projectile marked as visual-only (remote copy)")
	
	# Initialize projectile with owner info if it supports initialize()
	if proj.has_method("initialize"):
		# Projectile class uses initialize(start_position, direction, owner_ref, owner_id)
		proj.initialize(origin, direction, null, owner_peer_id)
		print("[NetworkedWeaponManager] Projectile initialized with owner_peer_id: ", owner_peer_id)
	else:
		# Fallback: set position and velocity manually
		if proj is RigidBody3D:
			(proj as RigidBody3D).linear_velocity = direction * 1000
		elif proj.has_method("initialize_velocity"):
			proj.call("initialize_velocity", direction * 1000)
		
		# Set projectile owner using universal ownership system
		_set_projectile_owner(proj, null, owner_peer_id)

## Helper to set projectile owner using universal ownership system
func _set_projectile_owner(projectile: Node, owner_ref: Node3D = null, owner_id: int = -1) -> void:
	if not projectile:
		return
	
	# Try universal ownership methods
	if projectile.has_method("set_owner"):
		# NetworkedProjectile base class
		projectile.call("set_owner", owner_ref, owner_id)
	elif projectile.has_method("throw"):
		# ThrowableKnifeProjectile pattern
		projectile.call("throw", Vector3.ZERO, owner_ref, owner_id)
	elif projectile.has_method("set_owner_info"):
		# Generic pattern
		projectile.call("set_owner_info", owner_ref, owner_id)
	elif projectile.has_method("initialize") and owner_id >= 0:
		# Try to pass owner info through initialize if it supports it
		# This is a fallback - specific projectile classes should implement set_owner
		pass
