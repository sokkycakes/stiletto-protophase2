# FootstepManager.gd
# Replicates HL1-style footstep sound logic in Godot 4.3
# Attach this script to a Node3D within your player character scene.
# Requires child nodes: AudioStreamPlayer3D.

class_name FootstepManager
extends Node3D

# --- Configuration ---
@export var enabled: bool = true

@export_group("Timing & Speed")
@export var step_interval_walk: float = 0.6
@export var step_interval_run: float = 0.35
@export var walk_speed_threshold: float = 2.0

# Speed-based volume adjustment
@export var min_speed_for_full_volume: float = 1.0
@export var speed_volume_curve: float = 1.5

# Crouch timing multipliers (HL1-style)
@export var crouch_timing_multiplier_walk: float = 1.25
@export var crouch_timing_multiplier_run: float = 0.93

@export_group("Audio Variation")
@export var volume_base_db: float = 0.0
@export var volume_variation_db: float = 2.0
@export var pitch_base: float = 1.0
@export var pitch_variation: float = 0.05

# Crouch volume multipliers (HL1-style)
@export var crouch_volume_multiplier_walk: float = 0.7
@export var crouch_volume_multiplier_run: float = 0.3

@export_group("Footstep Sound")
@export var footstep_sounds: Array[AudioStream]
@export var footstep_sound: AudioStream
@export var land_sound: AudioStream

@export_group("Hard Landing")
@export var hard_land_sound: AudioStream
@export var hard_landing_velocity_threshold: float = 15.0
@export var hard_landing_airtime_threshold: float = 0.8

@export_group("Required Nodes")
@export var player_path: NodePath
@export var audio_player_path: NodePath = ^"FootstepAudioPlayer"

# --- Screen Shake (Landing Feedback) ---
@export_group("Landing Screen Shake")
@export var enable_shake_on_land: bool = true
@export var camera_path: NodePath
# Minimum absolute downward velocity (in m/s) to start shaking
@export var shake_min_velocity: float = 10.0
# Absolute downward velocity that produces maximum shake intensity
@export var shake_max_velocity: float = 25.0
# Maximum positional offset (in meters) applied to the camera at max intensity
@export var shake_max_magnitude: float = 0.1
# Duration of the screen shake in seconds
@export var shake_duration: float = 0.15

# --- Node References ---
@onready var player: CharacterBody3D = null
@onready var audio_player: AudioStreamPlayer3D = get_node_or_null(audio_player_path)
@onready var jump_audio_player: AudioStreamPlayer3D = null
# Use supplied camera_path if set; otherwise will attempt auto-detection in _ready
@onready var camera: Camera3D = get_node_or_null(camera_path) if not camera_path.is_empty() else null

# --- Internal State ---
var _is_moving: bool = false
var _is_running: bool = false
var _is_crouching: bool = false
var _has_user_input: bool = false
var _last_input_time: float = 0.0
var _input_timeout: float = 0.1
var _last_played_sound_index: int = -1
var _step_cycle: float = 0.0
var _next_step: float = 0.0

@export var min_step_speed: float = 1.0 # Minimum speed required to trigger step sounds

# Track previous on_floor state for landing detection
var _was_on_floor: bool = false
# Prevent footstep sound immediately after landing
var _just_landed: bool = false
var _land_cooldown_timer: float = 0.0
const LAND_COOLDOWN: float = 0.12

# --- Internal (screen shake) ---
var _prev_vertical_speed: float = 0.0
var _shake_time_left: float = 0.0
var _shake_magnitude_current: float = 0.0
var _camera_original_transform: Transform3D = Transform3D()
var _shake_direction: float = 1.0  # 1.0 for max, -1.0 for min
var _shake_speed: float = 0.0  # How fast to ping-pong

# --- Hard Landing (internal) ---
var _time_in_air: float = 0.0  # Accumulated time since leaving the ground

func _ready():
	# --- Initial Validation ---
	var setup_valid = true
	_find_player_node()
	if not player:
		push_error("FootstepManager: Player node not found. Please check the player_path setting.")
		setup_valid = false
	if not audio_player:
		push_error("FootstepManager: AudioStreamPlayer3D node not found at path: ", audio_player_path)
		setup_valid = false
	if footstep_sounds.is_empty() and not footstep_sound:
		push_warning("FootstepManager: No footstep sounds assigned. Please assign sounds in the inspector.")
	elif not footstep_sounds.is_empty() and footstep_sound:
		push_warning("FootstepManager: Both footstep_sounds array and footstep_sound are set. Using footstep_sounds array.")
	if not setup_valid:
		push_error("FootstepManager disabled due to missing node references.")
		set_physics_process(false)
		set_process(false)
		enabled = false
		return

	# Set up a second audio player for jump sounds if needed
	if has_node("JumpAudioPlayer"):
		jump_audio_player = get_node("JumpAudioPlayer")

	# Attempt to auto-find a camera within the player if none supplied
	if enable_shake_on_land and camera == null and player:
		for child in player.get_children():
			if child is Camera3D:
				camera = child
				break
	if camera:
		_camera_original_transform = camera.transform
		# Calculate shake speed based on duration and desired ping-pong frequency
		_shake_speed = 2.0 * PI / (shake_duration * 0.5)  # 2 full cycles per duration

# Try multiple approaches to find the player node
func _find_player_node():
	if not player_path.is_empty():
		player = get_node_or_null(player_path)
	if not player and get_parent() is CharacterBody3D:
		player = get_parent()
	if not player:
		var scene_root = get_tree().get_root()
		for child in scene_root.get_children():
			if child is CharacterBody3D:
				player = child
				break

func _physics_process(delta):
	if not enabled:
		return
	if not player or not player.is_inside_tree():
		push_warning("FootstepManager: Player node invalid or not in tree.")
		set_physics_process(false)
		return
	# --- Landing Detection ---
	var is_on_floor = player.is_on_floor()

	# Track airtime when off the ground
	if not is_on_floor:
		_time_in_air += delta
	else:
		# Detect landing transition
		if not _was_on_floor:
			var impact_speed := abs(_prev_vertical_speed)
			var hard_landing: bool = impact_speed >= hard_landing_velocity_threshold or _time_in_air >= hard_landing_airtime_threshold

			play_landing_sound(hard_landing)
			_apply_landing_shake()
			_just_landed = true
			_land_cooldown_timer = LAND_COOLDOWN

		# Reset airtime counter once grounded
		_time_in_air = 0.0

	# --- Land cooldown update ---
	if _just_landed:
		_land_cooldown_timer -= delta
		if _land_cooldown_timer <= 0.0:
			_just_landed = false
	# --- Check Player State ---
	var can_step = _can_step()
	var horizontal_velocity = player.velocity * Vector3(1, 0, 1)
	var current_speed = horizontal_velocity.length()
	var was_moving = _is_moving
	# Check for user input by looking at the player's input state
	var has_input = false
	if player.has_method("get_input_dir"):
		var input_dir = player.get_input_dir()
		has_input = input_dir.length() > 0.1
	elif player.has_method("get_wish_dir"):
		var wish_dir = player.get_wish_dir()
		has_input = wish_dir.length() > 0.1
	else:
		has_input = current_speed > 0.1
	if has_input:
		_has_user_input = true
		_last_input_time = Time.get_ticks_msec() / 1000.0
	elif Time.get_ticks_msec() / 1000.0 - _last_input_time > _input_timeout:
		_has_user_input = false
	_is_crouching = _check_if_crouching()
	_is_moving = can_step and _has_user_input and current_speed > 0.1
	if not can_step:
		_is_moving = false
	_is_running = _is_moving and current_speed >= walk_speed_threshold
	_progress_step_cycle(current_speed, delta)
	_update_screen_shake(delta)
	# Update landing state for next frame
	_was_on_floor = is_on_floor
	_prev_vertical_speed = player.velocity.y

func _check_if_crouching() -> bool:
	if player is GoldGdt_Body:
		return player.ducked or player.ducking
	if player.has_method("is_ducking"):
		return player.is_ducking()
	elif player.has_method("is_crouching"):
		return player.is_crouching()
	elif player.has_method("get_duck_amount"):
		return player.get_duck_amount() > 0.5
	if player.get("ducking") != null:
		return player.ducking
	elif player.get("is_ducked") != null:
		return player.is_ducked
	return false

func _can_step() -> bool:
	return player != null and player.is_on_floor()

func _progress_step_cycle(speed: float, delta: float):
	var current_speed = player.velocity.length()
	# Prevent footstep sound right after landing
	if _just_landed:
		return
	if current_speed > min_step_speed and _has_input():
		var interval = step_interval_walk if _is_crouching else step_interval_run
		_step_cycle += current_speed * delta
		if _step_cycle > _next_step:
			_next_step = _step_cycle + interval
			_play_footstep_sound()
	else:
		_step_cycle = 0.0
		_next_step = 0.0

func _has_input() -> bool:
	# Use GoldGdt input mapping names
	return Input.is_action_pressed("pm_moveforward") or Input.is_action_pressed("pm_movebackward") or Input.is_action_pressed("pm_moveleft") or Input.is_action_pressed("pm_moveright")

func _is_walking() -> bool:
	# Replace with your own walk/run logic
	return true

func _play_footstep_sound():
	if not player.is_on_floor():
		return
	if footstep_sounds.size() < 2:
		return
	# Pick a random sound (not index 0)
	var n = randi_range(1, footstep_sounds.size() - 1)
	audio_player.stream = footstep_sounds[n]
	audio_player.play()
	# Swap so this sound isn't picked next time
	var temp = footstep_sounds[n]
	footstep_sounds[n] = footstep_sounds[0]
	footstep_sounds[0] = temp 

# Play landing sound and set next step delay
func play_landing_sound(is_hard: bool = false):
	if not audio_player:
		return

	var stream_to_play: AudioStream = null

	if is_hard and hard_land_sound:
		stream_to_play = hard_land_sound
	elif land_sound:
		stream_to_play = land_sound

	if stream_to_play:
		audio_player.stream = stream_to_play
		audio_player.play()
		_next_step = _step_cycle + 0.5

# Play two random footstep sounds at once for jumping
func play_jump_sounds():
	if footstep_sounds.size() < 2:
		return
	# Pick two different random indices
	var indices = []
	while indices.size() < 2:
		var idx = randi_range(0, footstep_sounds.size() - 1)
		if idx not in indices:
			indices.append(idx)
	# Play first sound on main audio player
	if audio_player:
		audio_player.stream = footstep_sounds[indices[0]]
		audio_player.play()
	# Play second sound on jump audio player if available, else play after a short delay on main
	if jump_audio_player:
		jump_audio_player.stream = footstep_sounds[indices[1]]
		jump_audio_player.play()
	else:
		# If only one player, play the second sound after a short delay
		await get_tree().create_timer(0.05).timeout
		audio_player.stream = footstep_sounds[indices[1]]
		audio_player.play() 

# --- Screen Shake Implementation ---
func _apply_landing_shake():
	if not enable_shake_on_land:
		return
	if camera == null:
		return
	# Impact speed is the absolute value of the downward velocity from previous frame
	var impact_speed := abs(_prev_vertical_speed)
	if impact_speed < shake_min_velocity:
		return
	var t := clamp((impact_speed - shake_min_velocity) / (shake_max_velocity - shake_min_velocity), 0.0, 1.0)
	_shake_magnitude_current = lerp(0.0, shake_max_magnitude, t)
	_shake_time_left = shake_duration
	_shake_direction = 1.0  # Start at max
	# Ensure we store the original transform to restore later
	_camera_original_transform = camera.transform

func _update_screen_shake(delta: float):
	if _shake_time_left <= 0.0:
		return
	_shake_time_left -= delta
	# Calculate progress and apply exponential decay
	var progress := 1.0 - (_shake_time_left / shake_duration)
	var decay_factor := exp(-progress * 3.0)  # Exponential decay for smooth fade-out
	
	# Sine wave pattern with decay for smooth oscillation
	var sine_value := sin(progress * PI * 6.0)  # 3 full cycles
	var decayed_magnitude := _shake_magnitude_current * decay_factor
	var shake_rotation_value := sine_value * decayed_magnitude
	
	# Apply rotation around X-axis (pitch) for vertical shake effect
	var shake_rotation := Vector3(shake_rotation_value, 0, 0)
	camera.rotation = _camera_original_transform.basis.get_euler() + shake_rotation
	
	if _shake_time_left <= 0.0:
		camera.rotation = _camera_original_transform.basis.get_euler() 
