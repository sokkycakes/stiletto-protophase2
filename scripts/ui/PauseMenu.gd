extends CanvasLayer

var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _last_scene: Node = null

func _ready():
	print("DEBUG: PauseMenu _ready() called")
	hide()
	if GameRulesManager:
		print("DEBUG: GameRulesManager found, connecting signal")
		GameRulesManager.pause_menu_visibility_changed.connect(_on_pause_menu_shown.bind())
	else:
		print("ERROR: GameRulesManager not found in PauseMenu")
	
	# Store initial scene
	_last_scene = get_tree().current_scene

func _process(_delta: float) -> void:
	# Check if scene has changed
	var current_scene = get_tree().current_scene
	if current_scene != _last_scene:
		_last_scene = current_scene
		_on_scene_changed()

func _on_scene_changed() -> void:
	# Auto-hide pause menu on scene change
	if visible:
		_force_hide_menu()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		print("DEBUG: Escape pressed in pause menu, hiding")
		GameRulesManager.show_pause_menu_ui(false)
		get_viewport().set_input_as_handled()

func _on_pause_menu_shown(show: bool):
	print("DEBUG: _on_pause_menu_shown called with show=", show)
	if show:
		show_menu()
	else:
		hide_menu()

func show_menu():
	show()
	# Store current mouse mode before changing it
	_previous_mouse_mode = Input.mouse_mode
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_viewport().set_input_as_handled()

func hide_menu():
	hide()
	# Check if character select is active - if so, force mouse to visible
	if _has_character_select():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Only restore mouse capture if we're in a game scene
	# UI scenes (lobby, character select) will set their own mouse mode
	elif _is_game_scene():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Otherwise, don't touch mouse mode - let the scene handle it
	get_viewport().set_input_as_handled()

func _force_hide_menu() -> void:
	# Force hide without changing mouse mode (scene transition)
	hide()
	# Don't change mouse mode - let the new scene handle it

func _is_game_scene() -> bool:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return false
	
	var scene_path := current_scene.scene_file_path
	# Game scenes are not UI scenes, lobby, or character select
	return not scene_path.begins_with("res://scenes/ui/") and \
		   not "lobby" in scene_path.to_lower() and \
		   not _has_character_select()

func _has_character_select() -> bool:
	# Check if current scene has character select UI
	var current_scene := get_tree().current_scene
	if not current_scene:
		return false
	
	# Check for CharacterSelect node by name
	if current_scene.get_node_or_null("CharacterSelect"):
		return true
	
	# Check for nodes in character_select group
	if not get_tree().get_nodes_in_group("character_select").is_empty():
		return true
	
	# Search recursively for CharacterSelect class instances
	var character_select_nodes = _find_nodes_by_class(current_scene)
	if not character_select_nodes.is_empty():
		return true
	
	return false

func _find_nodes_by_class(node: Node) -> Array:
	var result: Array = []
	# Check if node is of the CharacterSelect class
	if node is CharacterSelect:
		result.append(node)
	
	# Recursively check children
	for child in node.get_children():
		result.append_array(_find_nodes_by_class(child))
	
	return result

func _on_resume_pressed():
	print("DEBUG: Resume button pressed")
	GameRulesManager.show_pause_menu_ui(false)

func _on_return_pressed():
	print("DEBUG: Return to lobby button pressed")
	GameRulesManager.request_return_to_lobby()

func _on_disconnect_pressed():
	print("DEBUG: Disconnect button pressed")
	GameRulesManager.request_disconnect_from_match()
