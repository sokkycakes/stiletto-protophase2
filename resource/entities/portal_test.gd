extends Area3D

@export var target_scene: String = "res://scenes/level1.tscn"  # Set this in the editor to specify which scene to load
@export var audio_stream: AudioStream = preload("res://assets/snd/ambient/-1 - Fourth Chapter - On the Ground.mp3")

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

func _ready():
	# Connect signals
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	
	# Setup audio player if it doesn't exist
	if not has_node("AudioStreamPlayer3D"):
		var new_audio_player = AudioStreamPlayer3D.new()
		new_audio_player.name = "AudioStreamPlayer3D"
		add_child(new_audio_player)
		audio_player = new_audio_player
	
	# Set the audio stream
	if audio_stream:
		audio_player.stream = audio_stream
	
	print("Portal collision layer: ", collision_layer)
	print("Portal collision mask: ", collision_mask)

func _on_body_entered(body):
	print("Body entered: ", body.name)
	print("Body is in player group: ", body.is_in_group("player"))
	if body.is_in_group("player"):
		print("Playing audio")
		audio_player.play()

func _on_body_exited(body):
	print("Body exited: ", body.name)
	if body.is_in_group("player"):
		audio_player.stop()
