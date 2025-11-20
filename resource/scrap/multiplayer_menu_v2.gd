extends Control

@onready var player_name_input := $MainContainer/PlayerNameContainer/PlayerNameInput
@onready var host_button := $MainContainer/HostContainer/HostButton
@onready var join_code_container := $MainContainer/HostContainer/JoinCodeContainer
@onready var join_code_display := $MainContainer/HostContainer/JoinCodeContainer/JoinCodeDisplay
@onready var copy_code_button := $MainContainer/HostContainer/JoinCodeContainer/CopyCodeButton
@onready var join_code_input := $MainContainer/JoinContainer/JoinCodeInputContainer/JoinCodeInput
@onready var join_button := $MainContainer/JoinContainer/JoinButton
@onready var status_label := $MainContainer/StatusContainer/StatusLabel
@onready var player_count_label := $MainContainer/StatusContainer/PlayerCountLabel
@onready var disconnect_button := $MainContainer/ButtonContainer/DisconnectButton
@onready var back_button := $MainContainer/ButtonContainer/BackButton
@onready var start_game_button := $MainContainer/ButtonContainer/StartGameButton

var current_state := "idle"
var is_connected: bool = false

func _ready() -> void:
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	copy_code_button.pressed.connect(_on_copy_code_button_pressed)
	disconnect_button.pressed.connect(_on_disconnect_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	start_game_button.pressed.connect(_on_start_game_button_pressed)
	
	MultiplayerManager.lobby_ready.connect(_on_lobby_ready)
	MultiplayerManager.session_id_changed.connect(_on_session_id_changed)
	MultiplayerManager.player_connected.connect(_on_player_event)
	MultiplayerManager.player_disconnected.connect(_on_player_event)
	MultiplayerManager.connection_failed.connect(_on_connection_failed)
	MultiplayerManager.match_state_changed.connect(_on_match_state_changed)
	MultiplayerManager.game_started.connect(_on_game_started)
	MultiplayerManager.join_code_generated.connect(_on_join_code_generated)
	
	_update_ui_state()


func _update_ui_state() -> void:
	var connected_count := MultiplayerManager.get_player_count()
	player_count_label.text = "Players: %d/8" % connected_count
	
	host_button.disabled = is_connected
	join_button.disabled = is_connected
	player_name_input.editable = not is_connected
	join_code_input.editable = not is_connected
	disconnect_button.visible = is_connected
	
	join_code_container.visible = MultiplayerManager.is_server() and is_connected
	start_game_button.visible = is_connected and MultiplayerManager.is_server() and MultiplayerManager.get_game_state() == MultiplayerManager.GameState.LOBBY
	
	if not is_connected:
		status_label.text = "Ready to connect"


func _on_host_button_pressed() -> void:
	var player_name: String = player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	status_label.text = "Starting session..."
	MultiplayerManager.host_game(player_name)


func _on_join_button_pressed() -> void:
	var join_code: String = join_code_input.text.strip_edges()
	var player_name: String = player_name_input.text.strip_edges()
	
	if join_code.length() != 5:
		status_label.text = "Join code must be 5 characters"
		return
	
	if player_name.is_empty():
		player_name = "Player"
	
	status_label.text = "Joining session..."
	MultiplayerManager.join_game(join_code, player_name)


func _on_copy_code_button_pressed() -> void:
	if join_code_display.text.is_empty():
		return
	DisplayServer.clipboard_set(join_code_display.text)
	status_label.text = "Join code copied to clipboard"


func _on_disconnect_button_pressed() -> void:
	MultiplayerManager.disconnect_from_game()


func _on_back_button_pressed() -> void:
	if is_connected:
		MultiplayerManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_start_game_button_pressed() -> void:
	if not MultiplayerManager.is_server():
		return
	MultiplayerManager.start_game("res://scenes/multiplayer_game.tscn")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_button_pressed()


func _on_lobby_ready() -> void:
	is_connected = true
	current_state = "connected"
	if MultiplayerManager.is_server():
		status_label.text = "Hosting game – waiting for players"
	else:
		status_label.text = "Connected – waiting for host"
	_update_ui_state()


func _on_session_id_changed(new_session_id: String) -> void:
	join_code_display.text = new_session_id
	if new_session_id.is_empty():
		join_code_display.placeholder_text = "Generating..."


func _on_player_event(_peer_id: int) -> void:
	if not is_connected:
		return
	_update_ui_state()


func _on_connection_failed(reason: String) -> void:
	is_connected = false
	current_state = "idle"
	status_label.text = "Connection failed: %s" % reason
	_update_ui_state()


func _on_match_state_changed(active: bool) -> void:
	current_state = "in_game" if active else "connected"
	_update_ui_state()


func _on_game_started() -> void:
	status_label.text = "Game starting..."


func _on_join_code_generated(code: String) -> void:
	join_code_display.text = code
	current_state = "hosting"
	status_label.text = "Hosting game – waiting for players"
	is_connected = true
	_update_ui_state()
