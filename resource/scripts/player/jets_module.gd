extends Node3D
class_name JetsModule

## Jets Module for Angel Character
## Allows free 3D movement (like swimming) in the air for 5 seconds
## Has a 3 second cooldown after touching the ground

@export_group("Module Settings")
@export var enabled: bool = true

@export_group("Jets Settings")
@export var jets_duration: float = 5.0  # Seconds of free movement
@export var ground_cooldown: float = 3.0  # Cooldown after landing
@export var jets_activation_action: String = "pm_jump"  # Action to activate jets (default: jump while in air)
@export var jets_air_acceleration: float = 20.0  # Acceleration when jets are active
@export var jets_max_speed: float = 15.0  # Max speed when jets are active
@export var jets_vertical_control: float = 8.0  # Vertical movement speed
@export var jets_smoothing: float = 0.15  # Movement smoothing factor (0.0 = instant, 1.0 = very smooth)
@export var jets_friction: float = 15.0  # Friction when no input (stops player like noclip)
@export var jets_sound: AudioStream  # Optional sound effect for jets (should loop)
@export var jets_sound_min_volume_db: float = -20.0  # Minimum volume when not moving
@export var jets_sound_max_volume_db: float = 0.0  # Maximum volume at full speed
@export var jets_sound_volume_speed_scale: float = 1.0  # How much speed affects volume
@export var audio_bus: String = "sfx"

# Node references
var player: CharacterBody3D
var move_module: Node  # GoldGdt_Move module
var controls_module: Node  # GoldGdt_Controls module
var audio_player: AudioStreamPlayer  # 2D sound for local player
var audio_player_3d: AudioStreamPlayer3D  # 3D sound for other players

# State tracking
var jets_active: bool = false
var jets_timer: float = 0.0
var is_on_cooldown: bool = false
var cooldown_timer: float = 0.0
var was_on_floor_previous_frame: bool = false
var just_landed: bool = false
var time_since_left_ground: float = 0.0
const MIN_AIR_TIME: float = 0.05  # Minimum time in air before allowing jets (prevents ground jump bug)

signal jets_activated
signal jets_deactivated
signal jets_cooldown_started
signal jets_cooldown_ended

func _ready():
	# Get the player body
	player = get_node_or_null("../Body")
	if not player:
		player = get_node_or_null("../../Body")
	
	if not player:
		push_error("JetsModule: Could not find player Body node!")
		return
	
	# Setup 2D audio player (for local player)
	audio_player = AudioStreamPlayer.new()
	audio_player.bus = audio_bus
	audio_player.volume_db = jets_sound_min_volume_db
	add_child(audio_player)
	
	# Setup 3D audio player (for other players) - attach to player body
	if player:
		audio_player_3d = AudioStreamPlayer3D.new()
		audio_player_3d.bus = audio_bus
		audio_player_3d.volume_db = jets_sound_max_volume_db
		audio_player_3d.max_distance = 50.0
		audio_player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.add_child(audio_player_3d)
	
	# Find movement modules
	_find_movement_modules()
	
	print("JetsModule: Initialized for ", get_parent().name)

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

func _find_movement_modules():
	# Find GoldGdt_Move module
	var root = get_parent()
	move_module = _find_node_recursive(root, "Move Functions")
	if not move_module:
		move_module = _find_node_recursive(root, "GoldGdt_Move")
	
	# Find GoldGdt_Controls module
	controls_module = _find_node_recursive(root, "User Input")
	if not controls_module:
		controls_module = _find_node_recursive(root, "GoldGdt_Controls")
	
	if not move_module:
		push_warning("JetsModule: Could not find movement module. Jets may not work correctly.")
	else:
		print("JetsModule: Found movement module: ", move_module.name)

func _find_node_recursive(node: Node, node_name: String) -> Node:
	if not node:
		return null
	
	if node.name == node_name:
		return node
	
	for child in node.get_children():
		var result = _find_node_recursive(child, node_name)
		if result:
			return result
	
	return null

func _process(delta: float):
	if not enabled:
		return
	
	if not player:
		return
	
	# Only process input and update state for local player
	var is_local = _is_local_player()
	
	# Track ground state to prevent ground activation
	var is_currently_on_floor = player.is_on_floor()
	
	# Update time since leaving ground
	if is_currently_on_floor:
		time_since_left_ground = 0.0
		# Check if we just landed
		if not was_on_floor_previous_frame:
			just_landed = true
			# If jets were active, deactivate them and start cooldown
			if jets_active:
				deactivate_jets()
				start_ground_cooldown()
		was_on_floor_previous_frame = true
	else:
		if was_on_floor_previous_frame:
			# Just left the ground - reset timer
			time_since_left_ground = 0.0
		time_since_left_ground += delta
		was_on_floor_previous_frame = false
	
	# Update jets timer if active (only for local player)
	if jets_active and is_local:
		jets_timer -= delta
		if jets_timer <= 0.0:
			deactivate_jets()
			# Start cooldown if we're on ground
			if is_currently_on_floor:
				start_ground_cooldown()
		else:
			# Update jet sound volume based on speed
			_update_jet_sound_volume()
	
	# Update cooldown timer (only for local player)
	if is_on_cooldown and is_local:
		cooldown_timer -= delta
		if cooldown_timer <= 0.0:
			is_on_cooldown = false
			cooldown_timer = 0.0
			jets_cooldown_ended.emit()
			print("JetsModule: Cooldown ended")
	
	# Check for activation input (only for local player)
	if is_local and Input.is_action_just_pressed(jets_activation_action):
		# Can only activate while truly in midair (like double jump)
		if _is_truly_in_midair() and not is_on_cooldown and not jets_active:
			activate_jets()

func _physics_process(delta: float):
	if not enabled:
		return
	
	if not player:
		return
	
	# Only apply jets movement if active and this is the local player
	if jets_active and _is_local_player() and not player.is_on_floor():
		# Override normal air movement with jets movement
		# We apply jets movement which effectively replaces normal air acceleration
		# by applying stronger acceleration in the desired direction
		_apply_jets_movement(delta)

func activate_jets():
	if not enabled:
		return
	
	if jets_active:
		return
	
	if is_on_cooldown:
		print("JetsModule: Cannot activate - on cooldown (", cooldown_timer, "s remaining)")
		return
	
	if player.is_on_floor():
		print("JetsModule: Cannot activate - on ground")
		return
	
	jets_active = true
	jets_timer = jets_duration
	
	# Play looping sound
	if jets_sound:
		# Local player: play 2D sound (always audible for the player who triggered it)
		if _is_local_player() and audio_player:
			audio_player.stream = jets_sound
			audio_player.volume_db = jets_sound_min_volume_db
			audio_player.play()
		
		# All players: play 3D positional sound (follows player, heard by everyone)
		# This plays for the player who owns this module, so others can hear it
		if audio_player_3d:
			audio_player_3d.stream = jets_sound
			audio_player_3d.volume_db = jets_sound_max_volume_db
			audio_player_3d.play()
	
	jets_activated.emit()
	print("JetsModule: Jets activated for ", jets_duration, " seconds")

func deactivate_jets():
	if not jets_active:
		return
	
	jets_active = false
	jets_timer = 0.0
	
	# Stop sounds
	if audio_player:
		audio_player.stop()
	if audio_player_3d:
		audio_player_3d.stop()
	
	jets_deactivated.emit()
	print("JetsModule: Jets deactivated")

func start_ground_cooldown():
	if is_on_cooldown:
		return
	
	is_on_cooldown = true
	cooldown_timer = ground_cooldown
	
	jets_cooldown_started.emit()
	print("JetsModule: Ground cooldown started (", ground_cooldown, "s)")

func is_jets_active() -> bool:
	return jets_active

func is_jets_on_cooldown() -> bool:
	return is_on_cooldown

func get_jets_time_remaining() -> float:
	return max(0.0, jets_timer)

func get_cooldown_time_remaining() -> float:
	return max(0.0, cooldown_timer)

func _update_jet_sound_volume():
	if not jets_sound:
		return
	
	if not player:
		return
	
	# Calculate current speed
	var current_speed = player.velocity.length()
	
	# Calculate max speed (with decay applied)
	var time_elapsed = jets_duration - jets_timer
	var decay_duration = 4.0
	var speed_multiplier = 1.0
	if time_elapsed < decay_duration:
		speed_multiplier = 1.0 - (time_elapsed / decay_duration)
	else:
		speed_multiplier = 0.0
	var max_speed = jets_max_speed * speed_multiplier
	
	# Calculate speed ratio (0.0 to 1.0)
	var speed_ratio = 0.0
	if max_speed > 0.0:
		speed_ratio = clamp(current_speed / max_speed, 0.0, 1.0)
	
	# Map speed ratio to volume (min_volume to max_volume)
	var volume_range = jets_sound_max_volume_db - jets_sound_min_volume_db
	var target_volume = jets_sound_min_volume_db + (volume_range * speed_ratio * jets_sound_volume_speed_scale)
	
	# Clamp to ensure we don't go below minimum
	target_volume = max(jets_sound_min_volume_db, target_volume)
	
	# Update volume for local player (2D sound)
	if _is_local_player() and audio_player:
		audio_player.volume_db = target_volume
	
	# Update volume for 3D sound (all players hear this)
	if audio_player_3d:
		# For 3D sound, use max volume as base (distance attenuation handles the rest)
		audio_player_3d.volume_db = jets_sound_max_volume_db + (target_volume - jets_sound_min_volume_db)

func _is_truly_in_midair() -> bool:
	# Multiple checks to ensure player is truly in midair, not on ground
	if not player:
		return false
	
	# Check 1: is_on_floor() - primary floor detection
	if player.is_on_floor():
		return false
	
	# Check 2: Must have been in air for minimum time (prevents ground jump bug)
	if time_since_left_ground < MIN_AIR_TIME:
		return false
	
	# Check 3: get_floor_normal() - if we have a floor normal, we're touching ground
	var floor_normal = player.get_floor_normal()
	if floor_normal != Vector3.ZERO and floor_normal.length() > 0.1:
		return false
	
	# Check 4: If velocity.y is very positive, we might have just jumped from ground
	if player.velocity.y > 3.0:
		# Very large upward velocity suggests we just jumped from ground
		return false
	
	return true

func _apply_jets_movement(delta: float):
	# Calculate how long jets have been active
	var time_elapsed = jets_duration - jets_timer
	
	# Check if we've reached 4 seconds - forcefully zero velocity
	if time_elapsed >= 4.0:
		player.velocity = Vector3.ZERO
		return
	
	# Get gravity value from player parameters
	var gravity_value = 20.32  # Default gravity
	if player and "Parameters" in player:
		gravity_value = player.Parameters.GRAVITY
	elif controls_module and "Parameters" in controls_module:
		gravity_value = controls_module.Parameters.GRAVITY
	
	# Fully counteract gravity (set to 0)
	# Gravity is applied in Body._physics_process, so we add it back to cancel it
	player.velocity.y += gravity_value * delta
	
	# Get movement input (similar to how Controls does it)
	var movement_input = Vector2.ZERO
	if Input.is_action_pressed("pm_moveforward"):
		movement_input.y -= 1.0
	if Input.is_action_pressed("pm_movebackward"):
		movement_input.y += 1.0
	if Input.is_action_pressed("pm_moveleft"):
		movement_input.x -= 1.0
	if Input.is_action_pressed("pm_moveright"):
		movement_input.x += 1.0
	
	# Get vertical input (jump/duck for up/down)
	var vertical_input = 0.0
	if Input.is_action_pressed("pm_jump"):
		vertical_input += 1.0
	if Input.is_action_pressed("pm_duck"):
		vertical_input -= 1.0
	
	# Get camera/view direction
	var view_node = null
	if controls_module and "View" in controls_module:
		view_node = controls_module.View
	else:
		# Try to find View node
		view_node = _find_node_recursive(get_parent(), "View Control")
	
	if not view_node:
		return
	
	var horizontal_view = null
	if "horizontal_view" in view_node:
		horizontal_view = view_node.horizontal_view
	else:
		horizontal_view = _find_node_recursive(view_node, "Horizontal View")
	
	if not horizontal_view:
		return
	
	# Calculate movement direction in camera space (swimming-like)
	# Forward/backward maps to camera forward, left/right to camera right, jump/duck to camera up
	var forward = -horizontal_view.global_transform.basis.z
	var right = horizontal_view.global_transform.basis.x
	var up = horizontal_view.global_transform.basis.y
	
	var move_dir = forward * -movement_input.y + right * movement_input.x + up * vertical_input
	
	# Check if there's any input
	var has_input = move_dir.length_squared() > 0.01
	
	# If no input, apply friction to stop the player (like noclip/spectator mode)
	if not has_input:
		# Apply friction to slow down and stop
		var friction = jets_friction * delta
		var speed = player.velocity.length()
		
		if speed > 0.0:
			var friction_amount = min(friction, speed)
			player.velocity = player.velocity.normalized() * (speed - friction_amount)
			
			# Stop completely if speed is very small
			if player.velocity.length() < 0.1:
				player.velocity = Vector3.ZERO
		
		# Gravity is already canceled, just return
		return
	
	move_dir = move_dir.normalized()
	
	# Calculate speed decay over time
	# Speed decays from full to zero over 4 seconds (reaches zero at 4 seconds)
	var decay_duration = 4.0  # Speed reaches zero at this time
	var speed_multiplier = 1.0
	
	if time_elapsed >= decay_duration:
		# After 4 seconds, speed is zero
		speed_multiplier = 0.0
	else:
		# Linear decay from 1.0 to 0.0 over decay_duration seconds
		speed_multiplier = 1.0 - (time_elapsed / decay_duration)
	
	# Calculate wish speed with decay applied
	var wish_speed = jets_max_speed * speed_multiplier
	
	# Apply jets acceleration (swimming-like movement)
	# Use high acceleration to effectively override normal air movement
	var accel = jets_air_acceleration * delta
	var current_vel = player.velocity
	
	# Calculate desired velocity
	var wish_vel = move_dir * wish_speed
	
	# Apply smoothing to movement
	# Use lerp for smooth interpolation between current and desired velocity
	var smoothing_factor = clamp(jets_smoothing, 0.0, 1.0)
	var smoothed_vel = current_vel.lerp(wish_vel, 1.0 - smoothing_factor)
	
	# Accelerate towards smoothed velocity (full 3D movement)
	var vel_diff = smoothed_vel - current_vel
	var accel_vec = vel_diff.normalized() * min(accel * wish_speed, vel_diff.length())
	
	# Apply jets acceleration (full 3D movement with gravity = 0)
	player.velocity += accel_vec
