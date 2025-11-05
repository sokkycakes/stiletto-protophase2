extends Control

# Simple multiplayer test script
# Use this to test the multiplayer system without going through the full UI

@onready var host_button = $VBoxContainer/HostButton
@onready var join_button = $VBoxContainer/JoinButton
@onready var join_code_input = $VBoxContainer/JoinCodeInput
@onready var status_label = $VBoxContainer/StatusLabel

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	
	# Connect multiplayer manager signals
	if MultiplayerManager:
		MultiplayerManager.hosting_started.connect(_on_hosting_started)
		MultiplayerManager.joined_game.connect(_on_joined_game)
		MultiplayerManager.join_code_generated.connect(_on_join_code_generated)
		MultiplayerManager.connection_failed.connect(_on_connection_failed)

func _on_host_pressed():
	status_label.text = "Starting server..."
	MultiplayerManager.host_game("TestHost")

func _on_join_pressed():
	var code = join_code_input.text.strip_edges()
	if code.is_empty():
		status_label.text = "Enter a join code"
		return
	
	status_label.text = "Connecting..."
	MultiplayerManager.join_game(code, "TestClient")

func _on_hosting_started():
	status_label.text = "Server started! Waiting for players..."

func _on_joined_game():
	status_label.text = "Connected to server!"
	# Auto-start the game after a short delay
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/multiplayer_game.tscn")

func _on_join_code_generated(code: String):
	status_label.text = "Join code: " + code + "\nWaiting for players..."

func _on_connection_failed(reason: String):
	status_label.text = "Connection failed: " + reason

func _input(event):
	if event.is_action_pressed("ui_accept") and MultiplayerManager.is_hosting:
		# Start game when host presses Enter
		get_tree().change_scene_to_file("res://scenes/multiplayer_game.tscn")
