extends Node
class_name BaseGameMaster

# Base GameMaster - fallback for maps without custom logic
# This should be registered as an autoload singleton in project.godot
# Provides barebones character selection and player spawning

signal player_ready
signal player_spawned(player: Node)

# Character selection scene (created in editor)
@export var character_select_ui_scene: PackedScene = preload("res://scenes/ui/character_select.tscn")

# Available characters - configured in editor
@export var available_characters: Array = []

var active_player: Node = null
var selected_character = null
var spawn_position: Vector3 = Vector3.ZERO
var spawn_rotation: Vector3 = Vector3.ZERO
var last_character_id: String = ""  # Track last selected character for respawning

func _ready():
	add_to_group("gamemaster")
	
	# Initialize default characters if not already set in editor
	if available_characters.is_empty():
		available_characters = [
			_create_character_def("vagrant", "Vagrant", "res://resource/entities/player/ss_player_vagrant.tscn"),
			_create_character_def("base", "Base", "res://resource/entities/player/ss_player_base.tscn"),
		]
	
	# Check for scene on first frame (this runs after scene is loaded)
	call_deferred("check_current_scene")

func check_current_scene():
	# Only activate for scenes in the maps folder
	var current_scene_path = get_tree().current_scene.scene_file_path
	if not current_scene_path.begins_with("res://maps/"):
		print("[BaseGameMaster] Skipping - not a map scene: ", current_scene_path)
		return
	
	# Check if the current scene has a custom GameMaster or player
	if not _scene_has_custom_gamemaster():
		# If we already have a remembered selection, spawn immediately on fresh loads
		if not last_character_id.is_empty():
			# Restore selected character by id
			for char_def in available_characters:
				if char_def.id == last_character_id and char_def.is_valid():
					selected_character = char_def
					break
			# Spawn if we restored a selection and there's no existing player
			if selected_character and not _scene_has_player():
				print("[BaseGameMaster] Restoring previously selected character on scene load: ", selected_character.display_name)
				call_deferred("_spawn_player")
				return

		# Check if scene already has a player spawned
		if _scene_has_player():
			print("[BaseGameMaster] Scene already has a player, skipping character selection")
			return
		
		print("[BaseGameMaster] No custom GameMaster found in scene, activating fallback mode")
		# Delay slightly to let scene fully load
		call_deferred("_start_character_selection")


func _scene_has_custom_gamemaster() -> bool:
	# Check if the current scene or any nodes have the gamemaster group
	# But exclude ourselves
	var gamemasters = get_tree().get_nodes_in_group("gamemaster")
	for gm in gamemasters:
		if gm != self:  # Don't count ourselves
			return true
	return false

func _scene_has_player() -> bool:
	# Check if scene already has a player in the player group
	var players = get_tree().get_nodes_in_group("player")
	return players.size() > 0

func _start_character_selection():
	# Find spawn point in the scene
	_find_spawn_point()
	
	# Show character selection UI
	_show_character_select()

func _find_spawn_point():
	# Look for a spawn point in the scene
	var spawn_points = get_tree().get_nodes_in_group("spawn_point")
	
	if spawn_points.size() > 0:
		var spawn = spawn_points[0]
		spawn_position = spawn.global_position
		spawn_rotation = spawn.rotation
		print("[BaseGameMaster] Found spawn point: ", spawn.name)
	elif get_tree().current_scene.has_method("get_player_spawn_position"):
		# Some maps might define this method
		spawn_position = get_tree().current_scene.get_player_spawn_position()
		print("[BaseGameMaster] Using map-defined spawn position")
	else:
		# Default spawn at origin
		spawn_position = Vector3.ZERO
		spawn_rotation = Vector3.ZERO
		print("[BaseGameMaster] WARNING: No spawn point found, using origin")

func _show_character_select():
	# Filter out invalid or locked characters
	var valid_characters = []
	for c in available_characters:
		if c.has_method("is_valid") and c.has_method("is_unlocked") and c.is_valid() and c.is_unlocked:
			valid_characters.append(c)
		elif not c.has_method("is_unlocked"):
			# Allow if no unlock check
			valid_characters.append(c)
	
	if valid_characters.is_empty():
		print("[BaseGameMaster] ERROR: No valid characters available! Spawning default.")
		_spawn_default_character()
		return
	
	# Create and show character selection UI
	if character_select_ui_scene:
		var ui_instance = character_select_ui_scene.instantiate()
		
		# Pass characters to UI
		if ui_instance.has_method("set_characters"):
			ui_instance.set_characters(valid_characters)
		
		# Add to scene tree and show
		get_tree().root.add_child(ui_instance)
		
		# Connect to selection signal
		if ui_instance.has_signal("character_selected"):
			ui_instance.character_selected.connect(_on_character_selected)
		else:
			print("[BaseGameMaster] ERROR: Character select UI missing character_selected signal")
			# Fallback: spawn default character after delay
			await get_tree().create_timer(0.1).timeout
			_spawn_default_character()
	else:
		print("[BaseGameMaster] ERROR: No character_select_ui_scene assigned!")
		# Fallback: spawn default character
		_spawn_default_character()

func _on_character_selected(character_id: String):
	# Find the selected character
	for char_def in available_characters:
		if char_def.id == character_id and char_def.is_valid():
			selected_character = char_def
			last_character_id = character_id  # Save for respawning
			_spawn_player()
			return
	
	print("[BaseGameMaster] ERROR: Character not found: ", character_id)
	_spawn_default_character()

func _spawn_default_character():
	# Use first available character
	for char_def in available_characters:
		if char_def.is_valid() and char_def.is_unlocked:
			selected_character = char_def
			last_character_id = char_def.id  # Save for respawning
			print("[BaseGameMaster] Using default character: ", char_def.display_name)
			break
	
	if not selected_character:
		push_error("[BaseGameMaster] FATAL: No valid characters available!")
		return
	
	_spawn_player()

func _spawn_player():
	if not selected_character or not selected_character.is_valid():
		push_error("[BaseGameMaster] ERROR: No valid character selected!")
		return
	
	# Load and instantiate the player
	var player_scene = load(selected_character.scene_path)
	if not player_scene:
		push_error("[BaseGameMaster] ERROR: Could not load character scene: ", selected_character.scene_path)
		return
	
	active_player = player_scene.instantiate()
	
	# Position the player
	if active_player is Node3D:
		active_player.global_position = spawn_position
		active_player.rotation = spawn_rotation
	
	# Add to scene
	get_tree().current_scene.call_deferred("add_child", active_player)
	
	# Activate player camera
	await get_tree().process_frame  # Wait a frame for player to be added
	_activate_player_camera()
	
	emit_signal("player_spawned", active_player)
	print("[BaseGameMaster] Player spawned: ", selected_character.display_name)

func _activate_player_camera():
	if not active_player:
		return
	
	# Find camera in player
	var camera = _find_camera_recursive(active_player)
	if camera:
		camera.current = true
		emit_signal("player_ready")
		print("[BaseGameMaster] Player camera activated")

func _find_camera_recursive(node: Node) -> Camera3D:
	if node is Camera3D:
		return node
	for child in node.get_children():
		var found = _find_camera_recursive(child)
		if found:
			return found
	return null

# Public API methods for other systems
func get_active_player() -> Node:
	return active_player

func has_active_player() -> bool:
	return active_player != null and is_instance_valid(active_player)

func respawn_player(new_spawn_position: Vector3 = Vector3.ZERO):
	if new_spawn_position != Vector3.ZERO:
		spawn_position = new_spawn_position
	
	# Clean up old player
	if has_active_player():
		active_player.queue_free()
	
	# Reset player reference
	active_player = null
	
	# Restore selected character from last selection, or use default
	if last_character_id.is_empty():
		# No previous selection, use default
		for char_def in available_characters:
			if char_def.is_valid() and char_def.is_unlocked:
				selected_character = char_def
				last_character_id = char_def.id
				break
	else:
		# Find the previously selected character
		for char_def in available_characters:
			if char_def.id == last_character_id and char_def.is_valid():
				selected_character = char_def
				break
	
	# Spawn the player immediately (skip character selection on respawn)
	if selected_character:
		print("[BaseGameMaster] Respawning player as: ", selected_character.display_name)
		_spawn_player()
	else:
		# Fallback to character selection if no valid character found
		call_deferred("_start_character_selection")

# Helper to create character definition
func _create_character_def(id: String, display_name: String, scene_path: String) -> Resource:
	var CharacterDefClass = load("res://resource/scripts/character_definition.gd")
	var def = CharacterDefClass.new()
	def.id = id
	def.display_name = display_name
	def.scene_path = scene_path
	return def
