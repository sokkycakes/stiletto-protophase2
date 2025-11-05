extends Node3D

@export var bob_speed : float = 10.0
@export var bob_amplitude : float = 0.05
@export var rotation_bob_amplitude : float = 0.02

@onready var anim_player : AnimationPlayer = $v_revolver2/AnimationPlayer
var pm_fire: String = "pm_fire"

var character : CharacterBody3D
var base_position : Vector3
var time_offset : float = 0.0
var target_position : Vector3 #The position we are moving to.
@onready var bob_tween : Tween = create_tween()

func _ready():
	character = get_node("../../../../../../Body")
	print("Character node path: ", get_path_to(character) if character else "null")
	base_position = position
	target_position = base_position
	if anim_player == null:
		print("Error: AnimationPlayer is null. Node path: ", get_path())
		print("Available children: ", get_children())
	if not InputMap.has_action(pm_fire):
		printerr("Input Action '" + pm_fire + "' is not defined in Input Map.")
func _process(delta):
	var should_bob = is_bobbing_enabled()

	if should_bob:
		weapon_bob(delta)
	else:
		reset_weapon_position()

func is_bobbing_enabled() -> bool:
	if character == null:
		print("Warning: Character node is null in is_bobbing_enabled()")
		return false
		
	if not character.is_on_floor():
		return false

	if character.velocity.length() < 0.1:
		return false

	return true

func weapon_bob(delta):
	time_offset += delta * bob_speed

	var vertical_offset = sin(time_offset) * bob_amplitude
	var horizontal_offset = cos(time_offset) * bob_amplitude * 0.5
	var rotation_offset = sin(time_offset) * rotation_bob_amplitude

	target_position = base_position + Vector3(horizontal_offset, vertical_offset, 0)
	rotation.z = rotation_offset
	bob_tween.kill()
	bob_tween = create_tween()
	bob_tween.tween_property(self, "position", target_position, 0.1).set_trans(Tween.TRANS_SINE)

func reset_weapon_position():
	bob_tween.kill()
	bob_tween = create_tween()
	bob_tween.tween_property(self, "position", base_position, 0.1).set_trans(Tween.TRANS_SINE)
	rotation.z = 0

func _input(event: InputEvent) -> void:
	if Input.is_action_just_pressed(pm_fire):
		anim_player.play("fire")
		# Create a new AudioStreamPlayer for this shot
		var sound_instance = AudioStreamPlayer.new()
		sound_instance.stream = $GunSound.stream
		sound_instance.volume_db = $GunSound.volume_db
		add_child(sound_instance)
		sound_instance.play()
		# Remove the sound instance after it finishes playing
		await sound_instance.finished
		sound_instance.queue_free()
