extends Control
# MainMenu - UI Controller
# Note: No class_name needed to avoid conflicts

## Main menu for the FPS multiplayer template
## Handles hosting, joining, and configuring multiplayer games

# --- UI References ---
@onready var player_name_input: LineEdit = $VBoxContainer/PlayerName
@onready var host_button: Button = $VBoxContainer/HostGame
@onready var join_button: Button = $VBoxContainer/JoinGame
@onready var settings_button: Button = $VBoxContainer/Settings
@onready var quit_button: Button = $VBoxContainer/Quit

# --- Dialogs ---
@onready var join_dialog: AcceptDialog = $JoinDialog
@onready var server_browser: ItemList = $JoinDialog/VBoxContainer/ServerBrowser
@onready var refresh_button: Button = $JoinDialog/VBoxContainer/HBoxContainer/RefreshButton
@onready var direct_connect_button: Button = $JoinDialog/VBoxContainer/HBoxContainer/DirectConnectButton
@onready var address_input: LineEdit = $JoinDialog/VBoxContainer/AddressInput
@onready var port_input: LineEdit = $JoinDialog/VBoxContainer/PortInput

@onready var settings_dialog: AcceptDialog = $SettingsDialog
@onready var default_port_input: LineEdit = $SettingsDialog/VBoxContainer/HBoxContainer/DefaultPortInput
@onready var max_players_input: SpinBox = $SettingsDialog/VBoxContainer/HBoxContainer2/MaxPlayersInput

# --- Status Panel ---
@onready var status_panel: Panel = $StatusPanel
@onready var status_label: Label = $StatusPanel/VBoxContainer/StatusLabel
@onready var cancel_button: Button = $StatusPanel/VBoxContainer/CancelButton

# --- Settings ---
var default_port: int = 7000
var max_players: int = 8
var player_name: String = "Player"

# --- State ---
var is_connecting: bool = false

func _ready() -> void:
	# Connect UI signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Dialog signals
	join_dialog.confirmed.connect(_on_join_confirmed)
	settings_dialog.confirmed.connect(_on_settings_confirmed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	
	# Connect server browser signals with null checks
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_servers)
	if direct_connect_button:
		direct_connect_button.pressed.connect(_on_direct_connect)
	if server_browser:
		server_browser.item_selected.connect(_on_server_selected)
	
	# Connect to multiplayer manager
	if MultiplayerManager:
		MultiplayerManager.lobby_ready.connect(_on_lobby_ready)
		MultiplayerManager.connection_failed.connect(_on_connection_failed)
		if MultiplayerManager.has_signal("join_code_generated"):
			MultiplayerManager.join_code_generated.connect(_on_join_code_generated)
	
	# Load saved settings
	_load_settings()
	
	# Initially hide status panel
	status_panel.visible = false
	
	# Set focus to player name input
	player_name_input.grab_focus()

func _load_settings() -> void:
	# Load from config file if it exists
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		player_name = config.get_value("player", "name", "Player")
		default_port = config.get_value("network", "default_port", 7000)
		max_players = config.get_value("network", "max_players", 8)
	
	# Update UI
	player_name_input.text = player_name
	default_port_input.text = str(default_port)
	max_players_input.value = max_players

func _save_settings() -> void:
	var config = ConfigFile.new()
	
	# Save current values
	config.set_value("player", "name", player_name_input.text)
	config.set_value("network", "default_port", int(default_port_input.text))
	config.set_value("network", "max_players", int(max_players_input.value))
	
	# Save to file
	config.save("user://settings.cfg")

# --- Button Handlers ---

func _on_host_pressed() -> void:
	if is_connecting:
		return
	
	_update_player_name()
	
	# Show status
	_show_status("Starting server...")
	
	# Start hosting
	var success = MultiplayerManager.host_game(player_name)
	
	if not success:
		_hide_status()


func _on_join_pressed() -> void:
	if is_connecting:
		return
	
	_update_player_name()
	
	# Show join dialog for session code entry
	if address_input:
		address_input.visible = true
		address_input.placeholder_text = "Enter 5-character code (case-sensitive)"
		address_input.text = ""
		# Connect text change to validate code in real-time
		if not address_input.text_changed.is_connected(_on_join_code_input_changed):
			address_input.text_changed.connect(_on_join_code_input_changed)
	if port_input:
		port_input.visible = false
	if server_browser:
		server_browser.visible = false
	if refresh_button:
		refresh_button.visible = false
	if direct_connect_button:
		direct_connect_button.visible = false
	
	join_dialog.popup_centered()
	# Don't disable OK button; let validation enable/disable it as user types
	if join_dialog.get_ok_button():
		join_dialog.get_ok_button().disabled = true

func _on_join_confirmed() -> void:
	var join_code: String = ""
	if address_input:
		join_code = address_input.text.strip_edges()
	
	if join_code.length() != 5:
		_hide_status()
		_show_error_dialog("Join code must be 5 characters long.")
		return
	
	# Show status
	_show_status("Connecting to session " + join_code + "...")
	
	# Attempt to join using Tube join codes
	var success = MultiplayerManager.join_game(join_code, player_name)
	
	if not success:
		_hide_status()

func _on_join_code_input_changed(new_text: String) -> void:
	# Validate join code in real-time and enable/disable OK button
	var trimmed: String = new_text.strip_edges()
	var is_valid: bool = trimmed.length() == 5
	if join_dialog and join_dialog.get_ok_button():
		join_dialog.get_ok_button().disabled = not is_valid

func _on_refresh_servers() -> void:
	# In Tube-based flow, server discovery is not used. Provide a no-op or a friendly notice.
	print("[MP] _on_refresh_servers called; server discovery is disabled in Tube mode.")

func _on_direct_connect() -> void:
	# In Tube-based flow, direct connect via IP/port is not used. Join codes only.
	print("[MP] Direct connect called; join via session code only in Tube mode.")

func _on_server_selected(index: int) -> void:
	# In Tube-based flow, server selection is not used.
	print("[MP] Server selected; discovery disabled in Tube mode.")

func _on_settings_pressed() -> void:
	# Update dialog with current values
	default_port_input.text = str(default_port)
	max_players_input.value = max_players
	
	settings_dialog.popup_centered()

func _on_settings_confirmed() -> void:
	# Apply settings
	default_port = int(default_port_input.text)
	max_players = int(max_players_input.value)
	
	# Save settings
	_save_settings()
	
	print("Settings saved")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_cancel_pressed() -> void:
	if is_connecting:
		MultiplayerManager.disconnect_from_game()
	
	_hide_status()

# --- Multiplayer Event Handlers ---

func _on_lobby_ready() -> void:
	print("Lobby ready, transitioning to lobby scene")
	_hide_status()
	
	# Transition to lobby scene (Tube-backed lobby)
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer/mp_lobby.tscn")

func _on_connection_failed(error: String) -> void:
	print("Connection failed: ", error)
	_hide_status()
	_show_error_dialog(error)

func _on_join_code_generated(code: String) -> void:
	if code.is_empty():
		return
	status_panel.visible = true
	status_label.text = "Session code: %s" % code
	is_connecting = false
	host_button.disabled = true
	join_button.disabled = true

# --- UI State Management ---

func _show_status(message: String) -> void:
	status_label.text = message
	status_panel.visible = true
	is_connecting = true
	
	# Disable main buttons
	host_button.disabled = true
	join_button.disabled = true

func _hide_status() -> void:
	status_panel.visible = false
	is_connecting = false
	
	# Re-enable main buttons
	host_button.disabled = false
	join_button.disabled = false

func _show_error_dialog(message: String) -> void:
	var error_dialog = AcceptDialog.new()
	error_dialog.title = "Error"
	error_dialog.dialog_text = message
	add_child(error_dialog)
	error_dialog.popup_centered()
	error_dialog.confirmed.connect(error_dialog.queue_free)

func _update_player_name() -> void:
	player_name = player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
		player_name_input.text = player_name

# --- Validation ---

func _validate_player_name(name: String) -> bool:
	# Basic validation
	if name.length() < 1 or name.length() > 20:
		return false
	
	# Check for valid characters (letters, numbers, spaces, basic punctuation)
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9 ._-]+$")
	
	return regex.search(name) != null

func _validate_port(port_text: String) -> bool:
	var port = int(port_text)
	return port >= 1024 and port <= 65535

func _validate_address(address: String) -> bool:
	var trimmed: String = address.strip_edges()
	return trimmed.length() == 5

# --- Input Validation ---

func _on_player_name_text_changed(new_text: String) -> void:
	# Enable/disable host and join buttons based on name validity
	var is_valid = _validate_player_name(new_text.strip_edges())
	host_button.disabled = not is_valid or is_connecting
	join_button.disabled = not is_valid or is_connecting

func _on_port_input_text_changed(new_text: String) -> void:
	# Validate port in real-time
	var is_valid = _validate_port(new_text)
	if join_dialog.visible:
		join_dialog.get_ok_button().disabled = not is_valid

func _on_address_input_text_changed(new_text: String) -> void:
	# Validate address in real-time
	var is_valid = _validate_address(new_text.strip_edges())
	if join_dialog.visible:
		join_dialog.get_ok_button().disabled = not is_valid

# --- Additional Features ---

func _on_player_name_input_text_submitted(new_text: String) -> void:
	# Auto-focus to host button when enter is pressed
	if _validate_player_name(new_text.strip_edges()):
		host_button.grab_focus()

# --- Debug/Development ---

func _input(event: InputEvent) -> void:
	# Debug shortcuts
	if OS.is_debug_build():
		if event is InputEventKey and event.pressed:
			match event.keycode:
				KEY_F1:
					# Quick host
					_update_player_name()
					MultiplayerManager.host_game(player_name)
				KEY_F2:
					# Quick join using code typed in AddressInput field
					_update_player_name()
					if address_input:
						var code := address_input.text.strip_edges()
						if code.length() == 5:
							MultiplayerManager.join_game(code, player_name)
						else:
							_show_error_dialog("Enter a 5-character code in the join dialog before pressing F2")
					else:
						_show_error_dialog("Open the join dialog and enter a 5-character code before pressing F2")

func _get_version_info() -> String:
	# Could be used for displaying version information
	return "FPS Multiplayer Template v1.0"

# --- Recent Servers (Future Enhancement) ---

func _load_recent_servers() -> Array:
	# Load recently connected servers for quick access
	var config = ConfigFile.new()
	if config.load("user://recent_servers.cfg") == OK:
		return config.get_value("servers", "recent", [])
	return []

func _save_recent_server(address: String, port: int) -> void:
	# Save server to recent list
	var recent = _load_recent_servers()
	var server_info = {"address": address, "port": port}
	
	# Remove if already exists
	for i in range(recent.size() - 1, -1, -1):
		if recent[i].address == address and recent[i].port == port:
			recent.remove_at(i)
	
	# Add to front
	recent.push_front(server_info)
	
	# Limit to 10 recent servers
	if recent.size() > 10:
		recent.resize(10)
	
	# Save
	var config = ConfigFile.new()
	config.set_value("servers", "recent", recent)
	config.save("user://recent_servers.cfg")
