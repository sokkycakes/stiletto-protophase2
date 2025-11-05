@tool
extends Node

@export var stream: AudioStream
@export var volume_db: float = 0.0
@export var pitch_scale: float = 1.0
@export var autoplay: bool = false
@export var mix_target: int = 0
@export var bus: String = "bgm"
@export var parameters: Dictionary = {}

func _ready():
	if not Engine.is_editor_hint():
		var bgm = get_node("/root/BgmGlobal")
		if bgm:
			if stream:
				bgm.stream = stream
			bgm.volume_db = volume_db
			bgm.pitch_scale = pitch_scale
			bgm.autoplay = autoplay
			bgm.mix_target = mix_target
			bgm.bus = bus
			
			# Apply any additional parameters
			for param in parameters:
				bgm.set(param, parameters[param]) 