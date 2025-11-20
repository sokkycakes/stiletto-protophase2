extends Node

# Player state enum
enum PlayerState {
	NORMAL,
	STUNNED,
	DEAD
}

# State variables
var current_state: PlayerState = PlayerState.NORMAL
var stun_duration: float = 2.0
var stun_timer: float = 0.0
var player: CharacterBody3D

# Death camera settings
@export_group("Death Camera")
@export var death_camera_roll: float = 90.0 ## Rotation angle in degrees for death cam (Z-axis roll)

# Death effects settings
@export_group("Death Effects")
@export var death_sound: AudioStream ## Sound to play when player dies
@export var death_timescale: float = 0.1 ## Game timescale during death effect (0.1 = 10% speed)
@export var death_timescale_duration: float = 1.0 ## How long to hold the slow timescale (in real time seconds)
@export var death_timescale_return_speed: float = 2.0 ## How fast to return to normal speed (higher = faster transition)
@export var death_audio_bus: String = "sfx" ## Audio bus for death sound

# Pain effects settings
@export_group("Pain Effects")
@export var pain_sounds: Array[AudioStream] ## Array of pain sounds to randomly play when taking hits
@export var pain_audio_bus: String = "sfx" ## Audio bus for pain sounds

# Health component reference (will be looked up at runtime if not explicitly assigned)
@export var health_node_path: NodePath = NodePath("../Health")
var health: Node

# References to scripts that need to be disabled on death
var player_scripts_to_disable: Array[Node] = []

# GoldGdt Controls reference for movement control
var goldgdt_controls: Node = null

# Camera/view system references for death cam rotation
var death_camera: Camera3D = null
var original_camera_rotation: Vector3 = Vector3.ZERO

# Death effects references
var death_audio_player: AudioStreamPlayer = null
var death_timescale_timer: float = 0.0
var is_death_timescale_active: bool = false
var is_returning_to_normal_time: bool = false

# Pain effects references
var pain_audio_player: AudioStreamPlayer = null

# Cached viewmodel reference for performance
var viewmodel_node: Node3D = null

# Signals
signal state_changed(old_state: String, new_state: String)
signal hit_taken(current_hits: int, max_hits: int)
signal player_died
signal stunned_state_changed(is_stunned: bool)
signal respawn_requested  # Emitted when player requests respawn (for multiplayer)

func _ready() -> void:
	# Get the player node and cast it to CharacterBody3D
	player = get_parent() as CharacterBody3D
	if not player:
		push_error("PlayerState: Parent node is not a CharacterBody3D")
		return

	# Get reference to GoldGdt Controls for movement control
	_find_goldgdt_controls()

	# Find and cache camera components
	_find_death_camera()

	# Setup death audio player
	_setup_death_audio()

	# Setup pain audio player
	_setup_pain_audio()

	# Collect all player scripts that need to be disabled on death
	_collect_player_scripts()

	# Find and cache the viewmodel
	_find_viewmodel()

	# Resolve health component and connect signals if present
	health = get_node_or_null(health_node_path)
	if health and health.has_method("get_current_health"):
		if health.has_signal("damage_taken"):
			health.damage_taken.connect(_on_health_damage_taken)
		if health.has_signal("died"):
			health.died.connect(_on_health_died)
		# Initialise from component values
		# max_hits = health.max_health # This line is removed as per the edit hint
		# hits_taken = max_hits - health.get_current_health() # This line is removed as per the edit hint
	else:
		push_warning("PlayerState: Health node not found at %s – defaulting to internal hit counter" % health_node_path)
		# The following lines are removed as per the edit hint
		# if max_hits == 0:
		# 	max_hits = 2

func _find_viewmodel() -> void:
	"""Find and cache the viewmodel node"""
	# Try multiple possible paths for the viewmodel
	var possible_paths = [
		"../../Interpolated Camera/Arm/Arm Anchor/Camera/v_revolver",
		"../../../Interpolated Camera/Arm/Arm Anchor/Camera/v_revolver",
		"../../../../Interpolated Camera/Arm/Arm Anchor/Camera/v_revolver"
	]
	
	for path in possible_paths:
		viewmodel_node = player.get_node_or_null(path)
		if viewmodel_node:
			print("PlayerState: Found viewmodel at path: ", path)
			return
	
	# If direct paths don't work, search recursively
	print("PlayerState: Direct paths failed, searching for viewmodel recursively...")
	var root_player = player.get_parent()
	if root_player:
		viewmodel_node = _search_for_viewmodel(root_player)
		if viewmodel_node:
			print("PlayerState: Found viewmodel via recursive search: ", viewmodel_node.get_path())
			return
	
	print("PlayerState: WARNING - Could not find viewmodel node")

func _search_for_viewmodel(node: Node) -> Node3D:
	"""Recursively search for a node named 'v_revolver'"""
	if node.name == "v_revolver":
		return node as Node3D
	
	for child in node.get_children():
		var result = _search_for_viewmodel(child)
		if result:
			return result
	
	return null

func _set_viewmodel_visible(visible: bool) -> void:
	"""Set viewmodel visibility with error handling"""
	if viewmodel_node and is_instance_valid(viewmodel_node):
		viewmodel_node.visible = visible
		print("PlayerState: Set viewmodel visible to: ", visible)
	else:
		print("PlayerState: WARNING - Cannot set viewmodel visibility, node not found or invalid")

func _find_goldgdt_controls() -> void:
	"""Find and cache the GoldGdt Controls component"""
	# Get the root player node (parent of Body which is parent of this state module)
	var root_player = player.get_parent()
	if not root_player:
		push_warning("PlayerState: Could not find root player node for GoldGdt Controls")
		return
	
	# Try to find the Controls node (GoldGdt_Controls)
	var possible_paths = [
		"User Input",  # Based on the Pawn.tscn structure
		"Controls",
		"GoldGdt_Controls"
	]
	
	for path in possible_paths:
		goldgdt_controls = root_player.get_node_or_null(path)
		if goldgdt_controls and goldgdt_controls.has_method("disable_movement"):
			print("PlayerState: Found GoldGdt Controls at: ", path)
			return
	
	# If not found, search recursively
	goldgdt_controls = _search_for_goldgdt_controls(root_player)
	if goldgdt_controls:
		print("PlayerState: Found GoldGdt Controls via recursive search")
	else:
		push_warning("PlayerState: Could not find GoldGdt_Controls component")

func _search_for_goldgdt_controls(node: Node) -> Node:
	"""Recursively search for GoldGdt_Controls component"""
	if node.has_method("disable_movement") and node.has_method("enable_movement"):
		return node
	
	for child in node.get_children():
		var result = _search_for_goldgdt_controls(child)
		if result:
			return result
	
	return null

func _find_death_camera() -> void:
	"""Find and cache the actual camera for death cam rotation"""
	# Get the root player node (parent of Body which is parent of this state module)
	var root_player = player.get_parent()
	if not root_player:
		push_warning("PlayerState: Could not find root player node for camera")
		return
	
	# Try to find the actual Camera3D node (not the mount, which gets overridden by GoldGdt)
	var possible_paths = [
		"Interpolated Camera/Arm/Arm Anchor/Camera",  # Most likely path
		"Camera",
		"Body/Camera",
		"View Control/Camera"
	]
	
	for path in possible_paths:
		var cam_node = root_player.get_node_or_null(path)
		if cam_node and cam_node is Camera3D:
			death_camera = cam_node
			print("PlayerState: Found camera at: ", path)
			# Store the original rotation
			original_camera_rotation = death_camera.rotation_degrees
			return
	
	# If not found, search recursively for Camera3D nodes
	death_camera = _search_for_death_camera(root_player)
	if death_camera:
		print("PlayerState: Found camera via recursive search")
		original_camera_rotation = death_camera.rotation_degrees
	else:
		push_warning("PlayerState: Could not find camera for death cam rotation")

func _search_for_death_camera(node: Node) -> Node3D:
	"""Recursively search for Camera3D node"""
	if node is Camera3D:
		return node as Node3D
	
	for child in node.get_children():
		var result = _search_for_death_camera(child)
		if result:
			return result
	
	return null

func _set_camera_rotation(rotation_degrees: Vector3) -> void:
	"""Set camera rotation with error handling"""
	if death_camera and is_instance_valid(death_camera):
		death_camera.rotation_degrees = rotation_degrees
		print("PlayerState: Set camera rotation to: ", rotation_degrees)
	else:
		print("PlayerState: WARNING - Cannot set camera rotation, camera not found or invalid")

func _setup_death_audio() -> void:
	"""Setup the audio player for death sounds"""
	death_audio_player = AudioStreamPlayer.new()
	death_audio_player.bus = death_audio_bus
	add_child(death_audio_player)
	print("PlayerState: Death audio player created")

func _play_death_sound() -> void:
	"""Play the death sound if configured"""
	if death_sound and death_audio_player:
		death_audio_player.stream = death_sound
		death_audio_player.play()
		print("PlayerState: Death sound played")
	else:
		print("PlayerState: No death sound configured or audio player missing")

func _start_death_timescale() -> void:
	"""Start the death timescale effect - DISABLED for multiplayer"""
	# Timescale effect disabled for multiplayer compatibility
	# if death_timescale_duration > 0.0 and death_timescale != 1.0:
	# 	Engine.time_scale = death_timescale
	# 	death_timescale_timer = death_timescale_duration
	# 	is_death_timescale_active = true
	# 	is_returning_to_normal_time = false
	# 	print("PlayerState: Death timescale started - scale: ", death_timescale, " duration: ", death_timescale_duration)
	pass

func _setup_pain_audio() -> void:
	"""Setup the audio player for pain sounds"""
	pain_audio_player = AudioStreamPlayer.new()
	pain_audio_player.bus = pain_audio_bus
	add_child(pain_audio_player)
	print("PlayerState: Pain audio player created")

func _play_pain_sound() -> void:
	"""Play a random pain sound from the array"""
	if pain_sounds.size() > 0 and pain_audio_player:
		var random_sound = pain_sounds[randi() % pain_sounds.size()]
		pain_audio_player.stream = random_sound
		pain_audio_player.play()
		print("PlayerState: Pain sound played (", pain_sounds.find(random_sound), "/", pain_sounds.size() - 1, ")")
	else:
		print("PlayerState: No pain sounds configured or audio player missing")

func _process(delta: float) -> void:
	# Handle kill key input (only works when alive)
	if current_state != PlayerState.DEAD and Input.is_action_just_pressed("pm_kill"):
		print("PlayerState: Kill key pressed - forcing death")
		die()
		return
	
	# Handle death timescale effect - DISABLED for multiplayer
	# _update_death_timescale(delta)
	
	if current_state == PlayerState.STUNNED:
		stun_timer -= delta
		if stun_timer <= 0:
			set_state(PlayerState.NORMAL)
	
	# Handle respawn input when dead
	if current_state == PlayerState.DEAD:
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("pm_jump") or Input.is_action_just_pressed("fire"):
			# Emit signal first (for multiplayer to handle)
			emit_signal("respawn_requested")
			# Then call local respawn (for single-player fallback)
			respawn()

func _update_death_timescale(delta: float) -> void:
	"""Update the death timescale effect - DISABLED for multiplayer"""
	# Timescale effect disabled for multiplayer compatibility
	# if is_death_timescale_active:
	# 	# Use unscaled delta for real time tracking
	# 	var real_delta = delta / Engine.time_scale
	# 	death_timescale_timer -= real_delta
	# 	
	# 	if death_timescale_timer <= 0.0:
	# 		# Start returning to normal time
	# 		is_death_timescale_active = false
	# 		is_returning_to_normal_time = true
	# 		print("PlayerState: Death timescale hold period ended, returning to normal")
	# 
	# if is_returning_to_normal_time:
	# 	# Gradually return to normal timescale
	# 	var real_delta = delta / Engine.time_scale
	# 	Engine.time_scale = move_toward(Engine.time_scale, 1.0, death_timescale_return_speed * real_delta)
	# 	
	# 	if Engine.time_scale >= 1.0:
	# 		Engine.time_scale = 1.0
	# 		is_returning_to_normal_time = false
	# 		print("PlayerState: Timescale returned to normal")
	pass

func _collect_player_scripts() -> void:
	"""Collect all player scripts that should be disabled when dead"""
	player_scripts_to_disable.clear()
	
	# Get the root player node (parent of Body which is parent of this state module)
	var root_player = player.get_parent()
	if not root_player:
		push_warning("PlayerState: Could not find root player node")
		return
	
	# Collect scripts from common player nodes
	var nodes_to_check = [
		# Movement and control scripts
		"View Control",
		"Controls",
		"Move Functions", 
		"Body",
		
		# Weapon and action systems
		"WeaponSystem",
		"HookController",
		"Kickback",
		"GunJump",
		"GamepadController",
		
		# Player-specific modules in Body
		"WallJumpModule",
		"WallMovement",
		
		# Camera and view scripts
		"Interpolated Camera",
		"Interpolated Camera/Arm",
		"Interpolated Camera/Arm/Arm Anchor/Camera/v_revolver",
	]
	
	for node_path in nodes_to_check:
		var node = root_player.get_node_or_null(node_path)
		if node and node.get_script():
			player_scripts_to_disable.append(node)
		
		# Also check child nodes for scripts
		if node:
			_collect_scripts_from_children(node)

func _collect_scripts_from_children(parent_node: Node) -> void:
	"""Recursively collect scripts from child nodes"""
	for child in parent_node.get_children():
		if child.get_script() and child not in player_scripts_to_disable:
			# Skip this PlayerState script itself
			if child != self:
				player_scripts_to_disable.append(child)
		
		# Recursively check children (but limit depth to avoid infinite loops)
		if child.get_child_count() > 0:
			_collect_scripts_from_children(child)

func _enable_disable_player_scripts(enable: bool) -> void:
	"""Enable or disable all collected player scripts"""
	for script_node in player_scripts_to_disable:
		if script_node and is_instance_valid(script_node):
			script_node.set_process_mode(Node.PROCESS_MODE_INHERIT if enable else Node.PROCESS_MODE_DISABLED)
			print("PlayerState: %s script on node: %s" % ["Enabled" if enable else "Disabled", script_node.name])

func take_hit(amount: int = 1) -> void:
	print("PlayerState: take_hit() called")

	if current_state == PlayerState.DEAD:
		print("PlayerState: Player is dead, ignoring hit")
		return

	if health and health.has_method("take_damage"):
		health.take_damage(amount)
	else:
		print("PlayerState: No health component found, cannot take damage")

func set_state(new_state: PlayerState) -> void:
	print("PlayerState: set_state() called with state: ", new_state)
	if current_state == new_state:
		print("PlayerState: State unchanged")
		return
		
	var old_state = current_state
	current_state = new_state
	emit_signal("state_changed", _state_to_string(old_state), _state_to_string(current_state))
	
	match current_state:
		PlayerState.NORMAL:
			print("PlayerState: Entering NORMAL state")
			# Re-enable all player scripts
			_enable_disable_player_scripts(true)
			
			# Re-enable GoldGdt movement control
			if goldgdt_controls:
				goldgdt_controls.enable_all_input()
				print("PlayerState: GoldGdt movement controls enabled")
			
			# Reset any active death effects
			_reset_death_effects()
			
			# Restore original camera rotation
			_set_camera_rotation(original_camera_rotation)
			
			# Show viewmodel
			_set_viewmodel_visible(true)
			emit_signal("stunned_state_changed", false)
			
		PlayerState.STUNNED:
			print("PlayerState: Entering STUNNED state")
			# Disable GoldGdt movement control (but keep camera for now)
			if goldgdt_controls:
				goldgdt_controls.disable_movement()
				goldgdt_controls.enable_camera()  # Allow camera look during stun
				print("PlayerState: GoldGdt movement disabled, camera enabled")
			
			# Play pain sound when taking a hit
			_play_pain_sound()
			
			# Apply stun effects (scripts will check state and disable input)
			_set_viewmodel_visible(false)
			emit_signal("stunned_state_changed", true)
			
		PlayerState.DEAD:
			print("PlayerState: Entering DEAD state")
			# Disable GoldGdt movement control (but keep camera like stunned state)
			if goldgdt_controls:
				goldgdt_controls.disable_movement()
				goldgdt_controls.enable_camera()  # Allow camera look while dead
				print("PlayerState: GoldGdt movement disabled, camera enabled (death cam)")
			
			# Rotate camera on Z axis (roll) for death cam effect like GoldSrc/HL1
			var death_rotation = original_camera_rotation + Vector3(0, 0, death_camera_roll)
			_set_camera_rotation(death_rotation)
			
			# Play death sound
			_play_death_sound()
			
			# Start death timescale effect
			_start_death_timescale()
			
			# Hide viewmodel
			_set_viewmodel_visible(false)
			emit_signal("stunned_state_changed", false)
			
			print("PlayerState: Player is dead. Press [SPACE], [ENTER], or [LEFT CLICK] to respawn.")

func die() -> void:
	set_state(PlayerState.DEAD)
	emit_signal("player_died")

func respawn() -> void:
	"""Restart the current scene to respawn the player (single-player only)"""
	print("PlayerState: Respawning player...")
	# Reset timescale before respawning
	_reset_death_effects()
	
	# In multiplayer, NetworkedPlayer handles respawn via respawn_requested signal
	# Don't do single-player respawn logic
	if multiplayer and multiplayer.has_multiplayer_peer():
		print("PlayerState: Multiplayer detected - NetworkedPlayer will handle respawn")
		return
	
	# Single-player: Use BaseGameMaster respawn if available
	if Engine.has_singleton("BaseGameMaster"):
		var base_gamemaster = get_node("/root/BaseGameMaster")
		if base_gamemaster:
			print("PlayerState: Using BaseGameMaster respawn")
			base_gamemaster.respawn_player()
			return
	
	# Fallback to scene reload
	print("PlayerState: Fallback to scene reload")
	get_tree().reload_current_scene()

func _reset_death_effects() -> void:
	"""Reset all death effects to normal state"""
	# Timescale reset disabled for multiplayer compatibility
	# Engine.time_scale = 1.0
	is_death_timescale_active = false
	is_returning_to_normal_time = false
	death_timescale_timer = 0.0
	print("PlayerState: Death effects reset")

func is_stunned() -> bool:
	return current_state == PlayerState.STUNNED

func is_in_stunned_state() -> bool:
	return current_state == PlayerState.STUNNED

func is_dead() -> bool:
	return current_state == PlayerState.DEAD

func is_in_dead_state() -> bool:
	return current_state == PlayerState.DEAD

func get_current_state() -> PlayerState:
	return current_state

func get_hits_taken() -> int:
	return 0 # No internal hit counter, health component handles it

# ------------------------------------------------------------------
# Health component callbacks
# ------------------------------------------------------------------

func _on_health_damage_taken(amount: int, current_health: int, max_health_in: int) -> void:
	print("PlayerState: Health damage taken - amount: ", amount, ", current: ", current_health, ", max: ", max_health_in)
	
	# Emit hit_taken signal for UI compatibility (convert health to hits)
	var hits_taken = max_health_in - current_health
	emit_signal("hit_taken", hits_taken, max_health_in)

	if current_health <= 0:
		die()
	else:
		set_state(PlayerState.STUNNED)
		stun_timer = stun_duration

func _on_health_died() -> void:
	die() 

func _state_to_string(state: PlayerState) -> String:
	match state:
		PlayerState.NORMAL:
			return "NORMAL"
		PlayerState.STUNNED:
			return "STUNNED"
		PlayerState.DEAD:
			return "DEAD"
		_:
			return str(state) 
