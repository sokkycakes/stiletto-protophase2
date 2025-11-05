extends Control

# Standalone multiplayer menu that handles scene switching properly

# UI References
@onready var player_name_input = $MainContainer/PlayerNameContainer/PlayerNameInput
@onready var host_button = $MainContainer/HostContainer/HostButton
@onready var join_code_container = $MainContainer/HostContainer/JoinCodeContainer
@onready var join_code_display = $MainContainer/HostContainer/JoinCodeContainer/JoinCodeDisplay
@onready var copy_code_button = $MainContainer/HostContainer/JoinCodeContainer/CopyCodeButton
@onready var join_code_input = $MainContainer/JoinContainer/JoinCodeInputContainer/JoinCodeInput
@onready var join_button = $MainContainer/JoinContainer/JoinButton
@onready var status_label = $MainContainer/StatusContainer/StatusLabel
@onready var player_count_label = $MainContainer/StatusContainer/PlayerCountLabel
@onready var disconnect_button = $MainContainer/ButtonContainer/DisconnectButton
@onready var back_button = $MainContainer/ButtonContainer/BackButton
@onready var start_game_button = $MainContainer/ButtonContainer/StartGameButton

# State
var is_connected: bool = false

func _ready():
	# Set mouse mode
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Connect UI signals
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	copy_code_button.pressed.connect(_on_copy_code_button_pressed)
	disconnect_button.pressed.connect(_on_disconnect_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	
	# Connect multiplayer manager signals
	if MultiplayerManager:
		MultiplayerManager.hosting_started.connect(_on_hosting_started)
		MultiplayerManager.joined_game.connect(_on_joined_game)
		MultiplayerManager.join_code_generated.connect(_on_join_code_generated)
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)
		MultiplayerManager.connection_failed.connect(_on_connection_failed)
	
	# Set initial state
	_update_ui_state()
	
	print("Standalone multiplayer menu loaded successfully")

func _update_ui_state():
	var player_count = MultiplayerManager.get_player_count() if MultiplayerManager else 1
	player_count_label.text = "Players: %d/8" % player_count
	
	if is_connected:
		host_button.disabled = true
		join_button.disabled = true
		player_name_input.editable = false
		join_code_input.editable = false
		disconnect_button.visible = true
		
		if MultiplayerManager and MultiplayerManager.is_server():
			# Only show start button if game hasn't started yet
			if MultiplayerManager.get_game_state() == MultiplayerManager.GameState.LOBBY:
				start_game_button.visible = true
				status_label.text = "Hosting game - waiting for players"
			else:
				start_game_button.visible = false
				status_label.text = "Game in progress"
		else:
			start_game_button.visible = false
			if MultiplayerManager and MultiplayerManager.is_game_in_progress():
				status_label.text = "Game in progress - joining..."
			else:
				status_label.text = "Connected - waiting for host to start"
	else:
		host_button.disabled = false
		join_button.disabled = false
		player_name_input.editable = true
		join_code_input.editable = true
		disconnect_button.visible = false
		start_game_button.visible = false
		join_code_container.visible = false
		status_label.text = "Ready to connect"

func _on_host_button_pressed():
	var player_name = player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	
	status_label.text = "Starting server..."
	
	if MultiplayerManager.host_game(player_name):
		status_label.text = "Server started successfully"
	else:
		status_label.text = "Failed to start server"

func _on_join_button_pressed():
	var join_code = join_code_input.text.strip_edges()
	var player_name = player_name_input.text.strip_edges()
	
	if join_code.is_empty():
		status_label.text = "Please enter a join code"
		return
	
	if player_name.is_empty():
		player_name = "Player"
	
	status_label.text = "Connecting..."
	
	if not MultiplayerManager.join_game(join_code, player_name):
		status_label.text = "Failed to connect"

func _on_copy_code_button_pressed():
	if not join_code_display.text.is_empty():
		DisplayServer.clipboard_set(join_code_display.text)
		status_label.text = "Join code copied to clipboard!"
		
		# Reset status message after a delay
		await get_tree().create_timer(2.0).timeout
		if is_connected:
			status_label.text = "Hosting game - waiting for players"

func _on_disconnect_button_pressed():
	MultiplayerManager.disconnect_from_game()
	is_connected = false
	_update_ui_state()

func _on_back_button_pressed():
	if is_connected:
		MultiplayerManager.disconnect_from_game()
		is_connected = false
	
	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

func _on_start_game_button_pressed():
	if MultiplayerManager and MultiplayerManager.is_server():
		# Notify all clients that the game is starting
		_rpc_start_game.rpc()

@rpc("authority", "call_local", "reliable")
func _rpc_start_game():
	# This will be called on all clients (including the host due to call_local)
	print("Game starting - transitioning to multiplayer game scene")
	status_label.text = "Starting game..."

	# Update game state
	if MultiplayerManager:
		MultiplayerManager.set_game_state(MultiplayerManager.GameState.STARTING)

	# Small delay to ensure the message is seen
	await get_tree().create_timer(0.5).timeout

	# Update game state to in-game
	if MultiplayerManager:
		MultiplayerManager.set_game_state(MultiplayerManager.GameState.IN_GAME)

	# Transition all players to the game scene
	get_tree().change_scene_to_file("res://scenes/multiplayer_game.tscn")

# Multiplayer Manager signal handlers

func _on_hosting_started():
	is_connected = true
	join_code_container.visible = true
	_update_ui_state()

func _on_joined_game():
	is_connected = true
	_update_ui_state()

	# Check if we're joining a game in progress
	if MultiplayerManager and MultiplayerManager.is_game_in_progress():
		print("Joining game in progress...")
		status_label.text = "Joining game in progress..."

		# Small delay then join the active game
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://scenes/multiplayer_game.tscn")

func _on_join_code_generated(code: String):
	join_code_display.text = code

func _on_player_connected(peer_id: int):
	_update_ui_state()
	status_label.text = "Player %d connected" % peer_id
	
	# Reset status message after a delay
	await get_tree().create_timer(2.0).timeout
	if is_connected and MultiplayerManager.is_server():
		status_label.text = "Hosting game - waiting for players"

func _on_player_disconnected(peer_id: int):
	_update_ui_state()
	status_label.text = "Player %d disconnected" % peer_id
	
	# Reset status message after a delay
	await get_tree().create_timer(2.0).timeout
	if is_connected and MultiplayerManager.is_server():
		status_label.text = "Hosting game - waiting for players"

func _on_connection_failed(reason: String):
	is_connected = false
	status_label.text = "Connection failed: " + reason
	_update_ui_state()

# Handle ESC key to go back
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()
