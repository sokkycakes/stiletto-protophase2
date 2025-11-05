extends "res://resource/scripts/weapons/base_weapon.gd"
class_name Pistol

# Pistol-specific default values ------------------------------------------------
@export var pistol_clip_size: int = 6
@export var pistol_fire_rate: float = 0.2
@export var pistol_reload_time: float = 1.4
@export var pistol_damage: int = 10
@export var pistol_spread: float = 2.0
@export var pistol_max_distance: float = 1000.0

# Pistol-specific visual and audio settings
@export var pistol_muzzle_flash_scene: PackedScene
@export var pistol_impact_effect_scene: PackedScene
@export var pistol_bullet_trail_scene: PackedScene
@export var pistol_muzzle_path: NodePath

# Pistol-specific audio
@export var pistol_fire_sound: AudioStream
@export var pistol_reload_sound: AudioStream
@export var pistol_empty_sound: AudioStream
@export var pistol_audio_bus: String = "SFX"

# Pistol-specific visual effects
@export var pistol_muzzle_flash_duration: float = 0.1
@export var pistol_bullet_trail_duration: float = 0.2
@export var pistol_impact_effect_duration: float = 1.0

# Pistol-specific gameplay tweaks
@export var pistol_allow_rapid_fire: bool = true
@export var pistol_auto_reload_on_empty: bool = false
@export var pistol_show_ammo_counter: bool = true
@export var pistol_use_accuracy_penalty: bool = true
@export var pistol_accuracy_penalty_per_shot: float = 0.1
@export var pistol_accuracy_recovery_rate: float = 0.5

# Pistol-specific recoil settings
@export var pistol_recoil_vertical: float = 2.0
@export var pistol_recoil_horizontal: float = 1.0
@export var pistol_recoil_recovery_time: float = 0.3

# Internal variables for pistol-specific features
var _current_accuracy_penalty: float = 0.0
var _current_recoil_offset: Vector2 = Vector2.ZERO
var _recoil_recovery_timer: Timer

func _ready() -> void:
	# Override the base values before base _ready sets up signals/timers
	clip_size = pistol_clip_size
	ammo_in_clip = clip_size
	fire_rate = pistol_fire_rate
	reload_time = pistol_reload_time
	bullet_damage = pistol_damage
	spread_degrees = pistol_spread
	maximum_distance = pistol_max_distance
	
	# Override base weapon scenes with pistol-specific ones if provided
	if pistol_muzzle_flash_scene:
		muzzle_flash_scene = pistol_muzzle_flash_scene
	if pistol_impact_effect_scene:
		impact_effect_scene = pistol_impact_effect_scene
	if pistol_bullet_trail_scene:
		bullet_trail_scene = pistol_bullet_trail_scene
	if pistol_muzzle_path != NodePath(""):
		muzzle_path = pistol_muzzle_path

	super._ready()
	
	# Setup recoil recovery timer
	_recoil_recovery_timer = Timer.new()
	_recoil_recovery_timer.one_shot = true
	_recoil_recovery_timer.timeout.connect(_on_recoil_recovery_timeout)
	add_child(_recoil_recovery_timer)

func _process(delta: float) -> void:
	# Recover accuracy over time
	recover_accuracy(delta)

# Override base shoot function to add pistol-specific features
func shoot() -> void:
	if not _can_fire or ammo_in_clip <= 0:
		if pistol_empty_sound:
			_play_sound(pistol_empty_sound)
		return

	# Apply accuracy penalty if enabled
	if pistol_use_accuracy_penalty:
		_current_accuracy_penalty += pistol_accuracy_penalty_per_shot
		spread_degrees = pistol_spread + _current_accuracy_penalty

	# Apply recoil
	_apply_recoil()

	# Play pistol-specific fire sound
	if pistol_fire_sound:
		_play_sound(pistol_fire_sound)

	# Call base shoot function
	super.shoot()

	# Auto-reload if enabled and clip is empty
	if pistol_auto_reload_on_empty and ammo_in_clip <= 0:
		start_reload()

# Override base reload function to add pistol-specific features
func start_reload() -> void:
	if pistol_reload_sound:
		_play_sound(pistol_reload_sound)
	
	super.start_reload()

# Pistol-specific helper functions
func _apply_recoil() -> void:
	var recoil_x = randf_range(-pistol_recoil_horizontal, pistol_recoil_horizontal)
	var recoil_y = randf_range(0, pistol_recoil_vertical)
	_current_recoil_offset += Vector2(recoil_x, recoil_y)
	
	# Start recoil recovery
	_recoil_recovery_timer.start(pistol_recoil_recovery_time)

func _on_recoil_recovery_timeout() -> void:
	_current_recoil_offset = Vector2.ZERO

func _play_sound(sound: AudioStream) -> void:
	if sound:
		var audio_player = AudioStreamPlayer.new()
		audio_player.stream = sound
		audio_player.bus = pistol_audio_bus
		add_child(audio_player)
		audio_player.play()
		audio_player.finished.connect(func(): audio_player.queue_free())

# Getter functions for external systems
func get_current_accuracy_penalty() -> float:
	return _current_accuracy_penalty

func get_current_recoil_offset() -> Vector2:
	return _current_recoil_offset

func get_effective_spread() -> float:
	return pistol_spread + _current_accuracy_penalty

# Accuracy recovery function (can be called externally)
func recover_accuracy(delta: float) -> void:
	if pistol_use_accuracy_penalty and _current_accuracy_penalty > 0:
		_current_accuracy_penalty = max(0, _current_accuracy_penalty - pistol_accuracy_recovery_rate * delta)
		spread_degrees = pistol_spread + _current_accuracy_penalty 
