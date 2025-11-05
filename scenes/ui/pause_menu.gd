extends Control

@onready var resume_button = $VBoxContainer/ResumeButton
@onready var options_button = $VBoxContainer/OptionsButton
@onready var quit_button = $VBoxContainer/QuitButton
@onready var title_button = $VBoxContainer/TitleButton
@onready var quit_confirmation = $QuitConfirmation
@onready var options_menu = $OptionsMenu

func _ready():
	# Make sure this node can process input and is always on top
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 128  # Set to a high z_index to be above other UI elements
	
	# Connect button signals
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
		print("Resume button connected")
	else:
		print("Resume button not found!")
		
	if options_button:
		options_button.pressed.connect(_on_options_pressed)
		print("Options button connected")
	else:
		print("Options button not found!")
		
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
		print("Quit button connected")
	else:
		print("Quit button not found!")
		
	if title_button:
		title_button.pressed.connect(_on_title_pressed)
		print("Title button connected")
	else:
		print("Title button not found!")
	
	# Connect quit confirmation signals
	if quit_confirmation:
		quit_confirmation.confirmed.connect(_on_quit_confirmed)
		quit_confirmation.canceled.connect(_on_quit_canceled)
		print("Quit confirmation connected")
	else:
		print("Quit confirmation not found!")
	
	# Hide the menu initially
	hide()

func _unhandled_input(event):
	# Don't handle pause in menu scenes
	if get_tree().current_scene:
		var scene_path = get_tree().current_scene.scene_file_path
		if (scene_path == "res://scenes/ui/trialmenuv2.tscn" or
			scene_path == "res://scenes/ui/main_menu.tscn" or
			scene_path.begins_with("res://scenes/ui/")):
			return

	if event.is_action_pressed("ui_cancel"):  # Escape key
		if visible:
			unpause_game()
			get_viewport().set_input_as_handled()
		else:
			pause_game()
			get_viewport().set_input_as_handled()

func pause_game():
	show()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Disable input processing for other UI elements
	for node in get_tree().get_nodes_in_group("ui"):
		if node != self and node != options_menu:
			node.process_mode = Node.PROCESS_MODE_DISABLED

func unpause_game():
	hide()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Re-enable input processing for other UI elements
	for node in get_tree().get_nodes_in_group("ui"):
		if node != self and node != options_menu:
			node.process_mode = Node.PROCESS_MODE_INHERIT

func _on_resume_pressed():
	print("Resume button pressed")
	unpause_game()

func _on_options_pressed():
	print("Options button pressed")
	options_menu.show()

func _on_quit_pressed():
	print("Quit button pressed")
	quit_confirmation.show()

func _on_quit_confirmed():
	print("Quit confirmed")
	get_tree().quit()

func _on_quit_canceled():
	print("Quit canceled")
	quit_confirmation.hide()

func _on_title_pressed():
	print("Title button pressed")
	get_tree().paused = false  # Unpause the game before changing scenes
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)  # Show the mouse cursor
	hide()  # Hide the pause menu

	# Handle different scene types appropriately
	var current_scene = get_tree().current_scene
	if current_scene:
		# Check if it's a multiplayer game scene
		if current_scene.scene_file_path == "res://scenes/multiplayer_game.tscn":
			# Call the multiplayer game's return to menu function
			if current_scene.has_method("_return_to_menu"):
				current_scene._return_to_menu()
				return

		# Check if current scene has a player with return to menu functionality
		var players = get_tree().get_nodes_in_group("players")
		for player in players:
			var networked_script = player.get_node_or_null("NetworkedPlayerScript")
			if networked_script and networked_script.has_method("_return_to_menu") and networked_script.has_method("is_local") and networked_script.is_local():
				networked_script._return_to_menu()
				return

	# Default fallback - go to new main menu
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
