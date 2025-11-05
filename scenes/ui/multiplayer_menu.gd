extends Control

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

signal back_pressed
signal game_started

func _ready():
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
			start_game_button.visible = true
			status_label.text = "Hosting game - waiting for players"
		else:
			start_game_button.visible = false
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
	back_pressed.emit()

func _on_start_game_button_pressed():
	if MultiplayerManager and MultiplayerManager.is_server():
		game_started.emit()

# Multiplayer Manager signal handlers

func _on_hosting_started():
	is_connected = true
	join_code_container.visible = true
	_update_ui_state()

func _on_joined_game():
	is_connected = true
	_update_ui_state()

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

# Public methods

func show_menu():
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Multiplayer menu shown - Size: ", size, " Position: ", position)

func hide_menu():
	visible = false
