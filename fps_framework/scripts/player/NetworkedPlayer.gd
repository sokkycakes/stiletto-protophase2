extends Node3D
class_name NetworkedPlayer

## Networked wrapper around GoldGdt_Pawn that adds multiplayer synchronization
## Preserves all existing GoldGdt functionality while adding network features

# --- Core Components ---
@export var pawn_scene: PackedScene
var pawn: GoldGdt_Pawn
var pawn_body: CharacterBody3D
var pawn_controls: Node
var pawn_camera: Camera3D
var pawn_horizontal_view: Node3D
var pawn_vertical_view: Node3D
var weapon_manager: NetworkedWeaponManager

# --- Network Identity ---
var peer_id: int = -1
var player_name: String = "Player"
var team_id: int = 0

# --- Player State ---
var health: float = 100.0
var max_health: float = 100.0
var is_alive: bool = true
var respawn_time: float = 5.0

# --- Network Sync ---
var last_position: Vector3 = Vector3.ZERO
var last_rotation: Vector3 = Vector3.ZERO
var last_view_yaw: float = 0.0
var last_view_pitch: float = 0.0
var position_threshold: float = 0.1
var rotation_threshold: float = 0.05

# --- Timers ---
var respawn_timer: Timer
var sync_timer: Timer

# --- Signals ---
signal health_changed(old_health: float, new_health: float)
signal player_died(killer_peer_id: int)
signal player_respawned()

func _ready() -> void:
	# Set up network authority
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
	
	# Create respawn timer
	respawn_timer = Timer.new()
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_respawn_player)
	add_child(respawn_timer)
	
	# Create sync timer for smooth network updates
	sync_timer = Timer.new()
	sync_timer.wait_time = 1.0 / 20.0  # 20 FPS sync rate
	sync_timer.timeout.connect(_sync_position)
	add_child(sync_timer)
	
	# Spawn the pawn
	_spawn_pawn()
	
	# Start sync timer
	if not is_multiplayer_authority():
		sync_timer.start()

func _physics_process(delta: float) -> void:
	if not pawn or not is_alive:
		return
	
	if pawn_body:
		global_position = pawn_body.global_position
	
	# Authority updates position for networking
	if is_multiplayer_authority():
		_check_position_sync()

# --- Pawn Management ---

func _spawn_pawn() -> void:
	# Determine which pawn scene to instantiate (support dynamic character_path)
	var effective_pawn_scene = pawn_scene
	if not effective_pawn_scene and has_meta("character_path"):
		var char_path = get_meta("character_path")
		if char_path and char_path != "":
			var loaded = load(char_path)
			if loaded:
				effective_pawn_scene = loaded
	# Instantiate chosen pawn scene
	if effective_pawn_scene:
		pawn = effective_pawn_scene.instantiate()
	else:
		# Try to find existing GoldGdt_Pawn in scene
		for child in get_children():
			if child is GoldGdt_Pawn:
				pawn = child
				break
		
		# If no pawn found, create basic one
		if not pawn:
			pawn = preload("res://GoldGdt/Pawn.tscn").instantiate()
	
	if pawn:
		add_child(pawn)
		
		# Cache key pawn components
		pawn_body = pawn.get_node_or_null("Body") as CharacterBody3D
		pawn_controls = pawn.get_node_or_null("User Input")
		pawn_camera = pawn.get_node_or_null("Interpolated Camera/Arm/Arm Anchor/Camera") as Camera3D
		pawn_horizontal_view = pawn.get_node_or_null("Body/Horizontal View") as Node3D
		pawn_vertical_view = pawn.get_node_or_null("Body/Horizontal View/Vertical View") as Node3D
		
		# Align initial network state
		var spawn_pos = pawn_body.global_position if pawn_body else pawn.global_position
		last_position = spawn_pos
		last_rotation = (pawn_body.global_rotation if pawn_body else pawn.global_rotation)
		last_view_yaw = pawn_horizontal_view.rotation.y if pawn_horizontal_view else 0.0
		last_view_pitch = pawn_vertical_view.rotation.x if pawn_vertical_view else 0.0
		
		# Disable input for non-authority players
		if not is_multiplayer_authority():
			_disable_pawn_input()
		else:
			_enable_pawn_input()
		
		# Set up weapon manager
		_setup_weapon_manager()
		
		print("Pawn spawned for player: ", player_name)
		
		if is_multiplayer_authority():
			force_sync()

func _disable_pawn_input() -> void:
	if not pawn:
		return
	
	# Disable input processing for remote players
	pawn.set_process(false)
	pawn.set_process_input(false)
	pawn.set_process_unhandled_input(false)
	pawn.set_physics_process(false)
	
	# Disable control scripts that would react to local input
	if pawn_controls:
		pawn_controls.set_process(false)
		pawn_controls.set_process_input(false)
		pawn_controls.set_physics_process(false)

	if pawn_camera:
		pawn_camera.current = false
	
	# Stop physics simulation on remote bodies; they will be driven by sync updates
	if pawn_body:
		pawn_body.set_physics_process(false)
		pawn_body.set_process(false)
		pawn_body.set_process_input(false)

func _enable_pawn_input() -> void:
	if not pawn:
		return
	
	pawn.set_process(true)
	pawn.set_process_input(true)
	pawn.set_process_unhandled_input(true)
	pawn.set_physics_process(true)
	
	if pawn_controls:
		pawn_controls.set_process(true)
		pawn_controls.set_process_input(true)
		pawn_controls.set_physics_process(true)
	
	if pawn_body:
		pawn_body.set_physics_process(true)
		pawn_body.set_process(true)

	if pawn_camera:
		pawn_camera.current = true

func _setup_weapon_manager() -> void:
	# Find existing weapon manager or create one
	weapon_manager = pawn.get_node_or_null("WeaponManager") as NetworkedWeaponManager
	
	if not weapon_manager:
		# Convert existing WeaponManager to NetworkedWeaponManager
		var existing_wm = pawn.get_node_or_null("WeaponManager") as WeaponManager
		if existing_wm:
			# Create networked version
			weapon_manager = NetworkedWeaponManager.new()
			weapon_manager.name = "WeaponManager"
			
			# Copy settings from existing manager
			weapon_manager.fire_action = existing_wm.fire_action
			weapon_manager.reload_action = existing_wm.reload_action
			weapon_manager.weapon_switch_actions = existing_wm.weapon_switch_actions
			weapon_manager.camera = existing_wm.camera
			weapon_manager.muzzle_path = existing_wm.muzzle_path
			
			# Replace old manager
			existing_wm.queue_free()
			pawn.add_child(weapon_manager)
	
	if weapon_manager:
		weapon_manager.setup_for_player(peer_id)

# --- Health System ---

func take_damage(amount: float, attacker_peer_id: int = -1) -> void:
	if not is_multiplayer_authority() or not is_alive:
		return
	
	var old_health = health
	health = max(0.0, health - amount)
	
	health_changed.emit(old_health, health)
	update_health.rpc(health)
	
	if health <= 0.0 and is_alive:
		_die(attacker_peer_id)

func heal(amount: float) -> void:
	if not is_multiplayer_authority():
		return
	
	var old_health = health
	health = min(max_health, health + amount)
	
	if old_health != health:
		health_changed.emit(old_health, health)
		update_health.rpc(health)

func _die(killer_peer_id: int = -1) -> void:
	if not is_alive:
		return
	
	is_alive = false
	
	# Hide/disable pawn
	if pawn:
		pawn.visible = false
		pawn.set_physics_process(false)
		pawn.set_process_input(false)
	
	# Notify game rules
	if GameRulesManager:
		GameRulesManager.on_player_killed(killer_peer_id, peer_id)
	
	player_died.emit(killer_peer_id)
	player_died_networked.rpc(killer_peer_id)
	
	# Start respawn timer
	respawn_timer.start(respawn_time)
	
	print("Player ", player_name, " died")

func _respawn_player() -> void:
	health = max_health
	is_alive = true
	
	# Re-enable pawn
	if pawn:
		pawn.visible = true
		pawn.set_physics_process(true)
		if is_multiplayer_authority():
			pawn.set_process_input(true)
	
	# Teleport to spawn point
	var spawn_pos = _get_spawn_position()
	global_position = spawn_pos
	
	if pawn:
		pawn.global_position = spawn_pos
	
	if pawn_body:
		pawn_body.global_position = spawn_pos
		if is_multiplayer_authority():
			pawn_body.set_physics_process(true)
	
	player_respawned.emit()
	player_respawned_networked.rpc()
	update_health.rpc(health)
	force_sync()
	
	print("Player ", player_name, " respawned")

func _get_spawn_position() -> Vector3:
	# Try to find team spawn points
	var spawn_points = get_tree().get_nodes_in_group("spawn_points")
	var team_spawns = []
	
	for spawn in spawn_points:
		if spawn.has_method("get_team_id") and spawn.get_team_id() == team_id:
			team_spawns.append(spawn)
	
	# Use team spawns if available, otherwise use any spawn
	var available_spawns = team_spawns if team_spawns.size() > 0 else spawn_points
	
	if available_spawns.size() > 0:
		var spawn = available_spawns[randi() % available_spawns.size()]
		return spawn.global_position
	
	# Default spawn position
	return Vector3(0, 1, 0)

# --- Network Synchronization ---

func _check_position_sync() -> void:
	if not pawn:
		return
	
	var current_pos = pawn_body.global_position if pawn_body else pawn.global_position
	var current_rot = pawn_body.global_rotation if pawn_body else pawn.global_rotation
	var current_view_yaw = pawn_horizontal_view.rotation.y if pawn_horizontal_view else 0.0
	var current_view_pitch = pawn_vertical_view.rotation.x if pawn_vertical_view else 0.0
	
	# Check if position/rotation changed significantly
	if current_pos.distance_to(last_position) > position_threshold or \
	   current_rot.distance_to(last_rotation) > rotation_threshold or \
	   absf(current_view_yaw - last_view_yaw) > rotation_threshold or \
	   absf(current_view_pitch - last_view_pitch) > rotation_threshold:
		
		last_position = current_pos
		last_rotation = current_rot
		last_view_yaw = current_view_yaw
		last_view_pitch = current_view_pitch
		sync_transform.rpc(current_pos, current_rot, current_view_yaw, current_view_pitch)

func _sync_position() -> void:
	if is_multiplayer_authority() or not pawn:
		return
	
	# Smooth interpolation for remote players
	var target_pos = last_position
	var target_rot = last_rotation
	
	if pawn_body:
		pawn_body.global_position = pawn_body.global_position.lerp(target_pos, 0.15)
		pawn_body.global_rotation = pawn_body.global_rotation.lerp(target_rot, 0.15)
		# Keep wrapper aligned with body for any dependent logic
		global_position = pawn_body.global_position
	else:
		pawn.global_position = pawn.global_position.lerp(target_pos, 0.15)
		pawn.global_rotation = pawn.global_rotation.lerp(target_rot, 0.15)
	
	if pawn_horizontal_view:
		var current_yaw = pawn_horizontal_view.rotation.y
		var new_yaw = lerp_angle(current_yaw, last_view_yaw, 0.2)
		pawn_horizontal_view.rotation.y = new_yaw
		pawn_horizontal_view.orthonormalize()
	
	if pawn_vertical_view:
		var current_pitch = pawn_vertical_view.rotation.x
		var new_pitch = lerp_angle(current_pitch, last_view_pitch, 0.2)
		pawn_vertical_view.rotation.x = new_pitch
		pawn_vertical_view.orthonormalize()

func force_sync(target_peer_id: int = 0) -> void:
	if not is_multiplayer_authority() or not pawn:
		return
	
	var pos = pawn_body.global_position if pawn_body else pawn.global_position
	var rot = pawn_body.global_rotation if pawn_body else pawn.global_rotation
	var view_yaw = pawn_horizontal_view.rotation.y if pawn_horizontal_view else 0.0
	var view_pitch = pawn_vertical_view.rotation.x if pawn_vertical_view else 0.0
	
	last_position = pos
	last_rotation = rot
	last_view_yaw = view_yaw
	last_view_pitch = view_pitch
	
	if target_peer_id > 0:
		sync_transform.rpc_id(target_peer_id, pos, rot, view_yaw, view_pitch)
	else:
		sync_transform.rpc(pos, rot, view_yaw, view_pitch)

# --- RPC Methods ---

@rpc("authority", "call_remote", "unreliable")
func sync_transform(pos: Vector3, rot: Vector3, view_yaw: float, view_pitch: float) -> void:
	last_position = pos
	last_rotation = rot
	last_view_yaw = view_yaw
	last_view_pitch = view_pitch
	
	# Snap wrapper immediately for consistency when interpolation disabled
	if pawn_body:
		pawn_body.global_position = pos
		pawn_body.global_rotation = rot
		global_position = pos
	else:
		global_position = pos
	
	if pawn_horizontal_view:
		pawn_horizontal_view.rotation.y = view_yaw
		pawn_horizontal_view.orthonormalize()
	
	if pawn_vertical_view:
		pawn_vertical_view.rotation.x = view_pitch
		pawn_vertical_view.orthonormalize()

@rpc("authority", "call_remote", "reliable")
func update_health(new_health: float) -> void:
	health = new_health

@rpc("authority", "call_remote", "reliable")
func player_died_networked(killer_peer_id: int) -> void:
	if not is_multiplayer_authority():
		_die(killer_peer_id)

@rpc("authority", "call_remote", "reliable")
func player_respawned_networked() -> void:
	if not is_multiplayer_authority():
		_respawn_player()

# --- Public API ---

## Initialize player with network info
func initialize_player(id: int, name: String, team: int = 0) -> void:
	peer_id = id
	player_name = name
	team_id = team
	
	set_multiplayer_authority(peer_id)
	
	print("Initialized networked player: ", name, " (ID: ", id, ", Team: ", team, ")")

## Get the underlying GoldGdt_Pawn
func get_pawn() -> GoldGdt_Pawn:
	return pawn

## Get current health percentage
func get_health_percentage() -> float:
	return health / max_health

## Check if this is the local player
func is_local_player() -> bool:
	return peer_id == MultiplayerManager.get_local_peer_id()

## Get player info dictionary
func get_player_info() -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": player_name,
		"team": team_id,
		"health": health,
		"max_health": max_health,
		"is_alive": is_alive,
		"position": global_position if pawn else Vector3.ZERO
	}

## Set team (updates visual indicators, spawning, etc.)
func set_team(new_team_id: int) -> void:
	team_id = new_team_id
	# Could add team-based visual changes here (colors, etc.)

## Force respawn (admin/debug function)
func force_respawn() -> void:
	if is_multiplayer_authority():
		_respawn_player()

## Check if player has valid pawn
func has_valid_pawn() -> bool:
	return pawn != null and is_alive
