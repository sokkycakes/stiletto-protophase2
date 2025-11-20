extends CanvasLayer

func _ready():
	print("DEBUG: PauseMenu _ready() called")
	hide()
	if GameRulesManager:
		print("DEBUG: GameRulesManager found, connecting signal")
		GameRulesManager.pause_menu_visibility_changed.connect(_on_pause_menu_shown.bind())
	else:
		print("ERROR: GameRulesManager not found in PauseMenu")

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
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_viewport().set_input_as_handled()

func hide_menu():
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	get_viewport().set_input_as_handled()

func _on_resume_pressed():
	print("DEBUG: Resume button pressed")
	GameRulesManager.show_pause_menu_ui(false)

func _on_return_pressed():
	print("DEBUG: Return to lobby button pressed")
	GameRulesManager.request_return_to_lobby()

func _on_disconnect_pressed():
	print("DEBUG: Disconnect button pressed")
	GameRulesManager.request_disconnect_from_match()
