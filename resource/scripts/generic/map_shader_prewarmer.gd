extends Node

## Place this in your map scenes to prewarm all potential spawnable entities
## Prevents shader compilation stuttering when enemies/effects first appear

@export_group("Entities to Prewarm")
@export var enemy_scenes: Array[PackedScene] = []
@export var weapon_scenes: Array[PackedScene] = []
@export var effect_scenes: Array[PackedScene] = []
@export var ui_scenes: Array[PackedScene] = []

@export_group("Settings")
@export var prewarm_on_ready: bool = true
@export var delay_gameplay_until_complete: bool = false
@export var only_prewarm_on_web: bool = true

signal prewarming_started(total_items: int)
signal prewarming_progress(current: int, total: int)
signal prewarming_complete

var _prewarmer: ShaderPrewarmer

func _ready():
	if prewarm_on_ready:
		start_prewarming()

func start_prewarming() -> void:
	# Skip if not on web and only_prewarm_on_web is enabled
	if only_prewarm_on_web and OS.get_name() != "Web":
		prewarming_complete.emit()
		return
	
	_prewarmer = ShaderPrewarmer.new()
	add_child(_prewarmer)
	_prewarmer.prewarming_started.connect(_on_prewarming_started)
	_prewarmer.prewarming_progress.connect(_on_prewarming_progress)
	_prewarmer.prewarming_complete.connect(_on_complete)
	
	var all_scenes: Array[PackedScene] = []
	all_scenes.append_array(enemy_scenes)
	all_scenes.append_array(weapon_scenes)
	all_scenes.append_array(effect_scenes)
	all_scenes.append_array(ui_scenes)
	
	if all_scenes.is_empty():
		push_warning("MapShaderPrewarmer: No scenes to prewarm!")
		prewarming_complete.emit()
		return
	
	if delay_gameplay_until_complete:
		# Freeze game
		get_tree().paused = true
	
	_prewarmer.start_prewarming(all_scenes)

func _on_prewarming_started(total_items: int) -> void:
	prewarming_started.emit(total_items)

func _on_prewarming_progress(current: int, total: int, item_name: String) -> void:
	prewarming_progress.emit(current, total)

func _on_complete() -> void:
	if delay_gameplay_until_complete:
		get_tree().paused = false
	
	prewarming_complete.emit()
	
	# Clean up prewarmer after a delay
	await get_tree().create_timer(1.0).timeout
	if _prewarmer:
		_prewarmer.queue_free()

