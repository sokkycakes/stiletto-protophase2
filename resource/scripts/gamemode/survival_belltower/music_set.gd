class_name MusicSet
extends Resource

## A set of music tracks for different game states
## Each song set contains 3-4 audio files for different game phases

@export var set_name: String = "Default Set"
@export var pre_game_track: AudioStream
@export var normal_game_track: AudioStream
@export var doom_track: AudioStream
@export var overwhelm_track: AudioStream  # Optional track for when doom countdown expires

## Optional metadata for the music set
@export var description: String = ""
@export var tags: Array[String] = []

func _init():
	resource_name = "MusicSet" 