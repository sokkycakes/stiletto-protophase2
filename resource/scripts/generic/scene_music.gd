extends Node

@export var music: AudioStream
@export var fade_duration: float = 1.0

func _ready() -> void:
	if music != null:
		# Wait a frame to ensure BgmGlobal is ready
		await get_tree().process_frame
		var bgm = get_node("/root/bgm_global")
		bgm.change_music(music, fade_duration) 
