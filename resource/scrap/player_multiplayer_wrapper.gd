extends Node3D
class_name PlayerMultiplayerWrapper

signal character_loaded(character_root: Node)

@export_file("*.tscn") var default_character_scene: String = ""

var character_instance: Node = null

@onready var network_script: Node = get_node_or_null("NetworkedPlayerScript")

func _ready() -> void:
	if not default_character_scene.is_empty():
		load_character_scene(default_character_scene)

func load_character_scene(character_source) -> Node:
	var packed_scene := _resolve_packed_scene(character_source)
	if not packed_scene:
		push_error("PlayerMultiplayerWrapper: Invalid character scene source: %s" % str(character_source))
		return null
	
	_clear_character()
	
	character_instance = packed_scene.instantiate()
	character_instance.name = "Character"
	if character_instance is Node3D:
		character_instance.transform = Transform3D.IDENTITY
	add_child(character_instance)
	
	_notify_character_loaded()
	return character_instance

func get_character_root() -> Node:
	return character_instance

func _notify_character_loaded() -> void:
	if network_script and network_script.has_method("set_character_root"):
		network_script.set_character_root(character_instance)
	character_loaded.emit(character_instance)

func _clear_character() -> void:
	if character_instance and is_instance_valid(character_instance):
		character_instance.queue_free()
	character_instance = null

func _resolve_packed_scene(source) -> PackedScene:
	if source is PackedScene:
		return source
	elif source is String:
		if source.is_empty():
			return null
		var loaded = load(source)
		return loaded if loaded is PackedScene else null
	return null
