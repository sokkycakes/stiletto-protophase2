extends Control

@export var main_menu_scene: String = "res://scenes/ui/main_menu.tscn"
@export var multiplayer_manager_path: NodePath = NodePath("/root/MultiplayerManager")
@export var base_gamemaster_path: NodePath = NodePath("/root/BaseGameMaster")

@onready var button_container: VBoxContainer = $VBoxContainer
@onready var quit_confirmation: ConfirmationDialog = $QuitConfirmation
@onready var options_menu: Control = $OptionsMenu

var _current_mode: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 128
	_setup_quit_confirmation()
	_connect_multiplayer_signals()
	_refresh_menu()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not _should_process_input():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if visible:
			hide_menu()
		else:
			show_menu()


func show_menu() -> void:
	show()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_menu()
	_set_other_ui_process_mode(Node.PROCESS_MODE_DISABLED)


func hide_menu() -> void:
	hide()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_set_other_ui_process_mode(Node.PROCESS_MODE_INHERIT)


func pause_game() -> void:
	show_menu()


func unpause_game() -> void:
	hide_menu()


func _setup_quit_confirmation() -> void:
	if not quit_confirmation:
		return
	if not quit_confirmation.confirmed.is_connected(_on_quit_confirmed):
		quit_confirmation.confirmed.connect(_on_quit_confirmed)
	if not quit_confirmation.canceled.is_connected(_on_quit_canceled):
		quit_confirmation.canceled.connect(_on_quit_canceled)


func _connect_multiplayer_signals() -> void:
	var manager = _get_multiplayer_manager()
	if not manager:
		return
	if manager.has_signal("match_state_changed") and not manager.match_state_changed.is_connected(_on_multiplayer_state_changed):
		manager.match_state_changed.connect(_on_multiplayer_state_changed)
	if manager.has_signal("game_started") and not manager.game_started.is_connected(_on_multiplayer_state_changed):
		manager.game_started.connect(_on_multiplayer_state_changed)
	if manager.has_signal("session_id_changed") and not manager.session_id_changed.is_connected(_on_multiplayer_state_changed):
		manager.session_id_changed.connect(_on_multiplayer_state_changed)


func _on_multiplayer_state_changed(_value = null) -> void:
	_refresh_menu()


func _refresh_menu() -> void:
	if not is_instance_valid(button_container):
		return
	var mode := _determine_menu_mode()
	if mode == _current_mode and button_container.get_child_count() > 0:
		return
	_current_mode = mode
	_clear_buttons()
	for option in _get_menu_options(mode):
		_create_menu_button(option)


func _determine_menu_mode() -> String:
	if _is_multiplayer_active():
		return "multiplayer"
	return "singleplayer"


func _is_multiplayer_active() -> bool:
	var manager = _get_multiplayer_manager()
	if manager:
		if manager.has_method("is_game_in_progress") and manager.is_game_in_progress():
			return true
		if manager.has_method("is_game_starting") and manager.is_game_starting():
			return true
		if manager.has_method("get_player_count") and manager.get_player_count() > 1:
			return true
		if manager.has_method("get_connected_players") and manager.get_connected_players().size() > 1:
			return true
		if bool(manager.get("is_connected")):
			return true
		if bool(manager.get("is_hosting")):
			return true
	var peer = get_tree().get_multiplayer().multiplayer_peer
	return peer != null


func _get_menu_options(mode: String) -> Array:
	if mode == "multiplayer":
		return [
			{
				"label": "Return to Game",
				"callback": Callable(self, "_handle_resume")
			},
			{
				"label": "Respawn",
				"callback": Callable(self, "_handle_respawn")
			},
			{
				"label": "Settings",
				"callback": Callable(self, "_handle_settings")
			},
			{
				"label": "Return to Lobby",
				"callback": Callable(self, "_handle_return_to_lobby")
			},
			{
				"label": "Disconnect",
				"callback": Callable(self, "_handle_disconnect")
			},
		]
	return [
		{
			"label": "Resume",
			"callback": Callable(self, "_handle_resume")
		},
		{
			"label": "Respawn",
			"callback": Callable(self, "_handle_respawn")
		},
		{
			"label": "Settings",
			"callback": Callable(self, "_handle_settings")
		},
		{
			"label": "Return to Title",
			"callback": Callable(self, "_handle_return_to_title")
		},
		{
			"label": "Quit",
			"callback": Callable(self, "_handle_quit")
		},
	]


func _create_menu_button(option: Dictionary) -> void:
	if not option.has("label") or not option.has("callback"):
		return
	var button := Button.new()
	button.text = option.label
	button.custom_minimum_size = Vector2(260, 48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.theme_type_variation = &"FlatButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button_container.add_child(button)
	button.pressed.connect(option.callback)


func _clear_buttons() -> void:
	for child in button_container.get_children():
		child.queue_free()


func _handle_resume() -> void:
	unpause_game()


func _handle_respawn() -> void:
	unpause_game()
	if _try_respawn_via_gamemaster():
		return
	if _try_respawn_via_players():
		return
	get_tree().reload_current_scene()


func _handle_settings() -> void:
	if options_menu:
		options_menu.show()


func _handle_return_to_title() -> void:
	unpause_game()
	_change_scene_safely(main_menu_scene)


func _handle_quit() -> void:
	if quit_confirmation:
		quit_confirmation.popup_centered()
	else:
		get_tree().quit()


func _handle_return_to_lobby() -> void:
	var manager = _get_multiplayer_manager()
	unpause_game()
	if manager and manager.has_method("return_to_lobby"):
		manager.return_to_lobby()
	else:
		_change_scene_safely(main_menu_scene)


func _handle_disconnect() -> void:
	var manager = _get_multiplayer_manager()
	unpause_game()
	if manager and manager.has_method("disconnect_from_game"):
		manager.disconnect_from_game()
	_change_scene_safely(main_menu_scene)


func _on_quit_confirmed() -> void:
	get_tree().quit()


func _on_quit_canceled() -> void:
	if quit_confirmation:
		quit_confirmation.hide()


func _should_process_input() -> bool:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return true
	var scene_path := current_scene.scene_file_path
	if scene_path.begins_with("res://scenes/ui/"):
		return false
	return true


func _try_respawn_via_gamemaster() -> bool:
	var gamemaster = _get_base_gamemaster()
	if gamemaster and gamemaster.has_method("respawn_player"):
		gamemaster.respawn_player()
		return true
	return false


func _try_respawn_via_players() -> bool:
	for player in get_tree().get_nodes_in_group("player"):
		if player.has_method("respawn"):
			player.respawn()
			return true
	return false


func _change_scene_safely(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	get_tree().change_scene_to_file(scene_path)


func _set_other_ui_process_mode(mode: int) -> void:
	for node in get_tree().get_nodes_in_group("ui"):
		if node == self or node == options_menu:
			continue
		node.process_mode = mode


func _get_multiplayer_manager():
	if multiplayer_manager_path.is_empty():
		return null
	var manager = get_node_or_null(multiplayer_manager_path)
	if manager:
		return manager
	return get_tree().root.get_node_or_null(multiplayer_manager_path)


func _get_base_gamemaster():
	if base_gamemaster_path.is_empty():
		return null
	var gamemaster = get_node_or_null(base_gamemaster_path)
	if gamemaster:
		return gamemaster
	return get_tree().root.get_node_or_null(base_gamemaster_path)
