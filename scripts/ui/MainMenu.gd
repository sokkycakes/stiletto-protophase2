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
var discovered_servers: Array[Dictionary] = []
var refresh_timer: Timer
var last_refresh_time: float = 0.0
var refresh_cooldown: float = 0.1  # Minimum time between refreshes (100ms)

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
		server_browser.item_activated.connect(_on_server_activated)  # Double-click to connect
	
	# Connect to multiplayer manager
	if MultiplayerManager:
		MultiplayerManager.lobby_ready.connect(_on_lobby_ready)
		MultiplayerManager.connection_failed.connect(_on_connection_failed)
		MultiplayerManager.servers_list_updated.connect(_on_servers_updated)
	
	# Load saved settings
	_load_settings()
	
	# Initially hide status panel
	status_panel.visible = false
	
	# Setup refresh timer for server discovery
	refresh_timer = Timer.new()
	refresh_timer.wait_time = 1.0  # Refresh every second
	refresh_timer.timeout.connect(_refresh_server_list)
	add_child(refresh_timer)
	
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
	
	# Start hosting (async function)
	var success = await MultiplayerManager.host_game(player_name, default_port)
	
	if not success:
		_hide_status()

func _on_join_pressed() -> void:
	if is_connecting:
		return
	
	_update_player_name()
	
	# Show both local server browser and Noray OID input
	# Local server browser section
	if server_browser:
		server_browser.visible = true
	if refresh_button:
		refresh_button.visible = true
	if direct_connect_button:
		direct_connect_button.visible = true
		direct_connect_button.text = "Direct Connect"
		# Reset button connections
		if direct_connect_button.pressed.is_connected(_on_show_browser):
			direct_connect_button.pressed.disconnect(_on_show_browser)
		if not direct_connect_button.pressed.is_connected(_on_direct_connect):
			direct_connect_button.pressed.connect(_on_direct_connect)
	
	# Noray OID input section
	if address_input:
		address_input.visible = true
		address_input.placeholder_text = "Enter host code (OID) for remote connection"
		address_input.text = ""
		# Connect text change to validate code in real-time
		if not address_input.text_changed.is_connected(_on_join_code_input_changed):
			address_input.text_changed.connect(_on_join_code_input_changed)
	if port_input:
		port_input.visible = false
	
	# If we're hosting, ensure localhost entry is in the list
	# Note: The broadcast system should handle this, but we check here as a safety measure
	if MultiplayerManager.is_hosting:
		print("[Server Browser] We are hosting, checking for localhost entry...")
	
	# Start server discovery first
	MultiplayerManager.start_server_discovery()
	
	# Wait a frame for discovery to initialize
	await get_tree().process_frame
	
	# Refresh server list when dialog opens
	_refresh_server_list()
	
	join_dialog.popup_centered()
	
	# Refresh again after dialog is shown (in case items were cleared)
	await get_tree().process_frame
	print("[Server Browser] Item count after dialog popup: ", server_browser.get_item_count() if server_browser else 0)
	if server_browser and server_browser.get_item_count() == 0 and not discovered_servers.is_empty():
		print("[Server Browser] Items were cleared after popup, refreshing again...")
		_refresh_server_list()
	# Don't disable OK button; let validation enable/disable it as user types
	if join_dialog.get_ok_button():
		join_dialog.get_ok_button().disabled = true

func _on_join_confirmed() -> void:
	# Check if a server is selected from the browser
	var selected_server: Dictionary = {}
	if server_browser:
		var selected_items = server_browser.get_selected_items()
		if selected_items.size() > 0 and selected_items[0] < discovered_servers.size():
			selected_server = discovered_servers[selected_items[0]]
	
	# Check if Noray OID is provided
	var host_oid: String = ""
	if address_input:
		host_oid = address_input.text.strip_edges()
	
	# Prioritize local server selection over Noray OID
	if not selected_server.is_empty():
		# Join via local server browser (direct connection)
		var server_ip = selected_server.get("ip", "")
		var server_port = selected_server.get("port", default_port)
		
		if server_ip.is_empty():
			_hide_status()
			_show_error_dialog("Invalid server selected.")
			return
		
		# Show status
		_show_status("Connecting to local server " + server_ip + ":" + str(server_port) + "...")
		
		# Attempt to join using direct connection (async function)
		var success = await MultiplayerManager.join_game_direct(server_ip, player_name, server_port)
		
		if not success:
			_hide_status()
		return
	
	# Fall back to Noray OID if no local server selected
	if host_oid.is_empty():
		_hide_status()
		_show_error_dialog("Please select a local server or enter a host code.")
		return
	
	# Show status
	_show_status("Connecting to host " + host_oid + "...")
	
	# Attempt to join using Noray OID (async function)
	var success = await MultiplayerManager.join_game(host_oid, player_name)
	
	if not success:
		_hide_status()

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
	
	# If hosting, display the OID before transitioning
	if MultiplayerManager.is_hosting and MultiplayerManager.noray_oid:
		var oid = MultiplayerManager.noray_oid
		status_panel.visible = true
		status_label.text = "Session code: %s\n(Share this code for others to join)" % oid
		# Wait a moment to show the code, then transition
		await get_tree().create_timer(3.0).timeout
	
	_hide_status()
	
	# Transition to lobby scene
	get_tree().change_scene_to_file("res://scenes/mp_framework/lobby.tscn")

func _on_connection_failed(error: String) -> void:
	print("Connection failed: ", error)
	_hide_status()
	_show_error_dialog(error)

func _show_error_dialog(message: String) -> void:
	var error_dialog = AcceptDialog.new()
	error_dialog.title = "Error"
	error_dialog.dialog_text = message
	add_child(error_dialog)
	error_dialog.popup_centered()
	error_dialog.confirmed.connect(error_dialog.queue_free)

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
	# Validate host OID - accept any non-empty string
	var trimmed: String = address.strip_edges()
	return not trimmed.is_empty()

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
	# Validate host OID in real-time and enable/disable OK button
	# Noray OIDs can vary in length, accept any non-empty string
	var trimmed: String = new_text.strip_edges()
	var is_valid: bool = not trimmed.is_empty()
	if join_dialog.visible and join_dialog.get_ok_button():
		join_dialog.get_ok_button().disabled = not is_valid

func _on_join_code_input_changed(new_text: String) -> void:
	# Validate host OID in real-time and enable/disable OK button
	# Noray OIDs can vary in length, accept any non-empty string
	var trimmed: String = new_text.strip_edges()
	var is_valid: bool = not trimmed.is_empty()
	if join_dialog and join_dialog.get_ok_button():
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
					await MultiplayerManager.host_game(player_name, default_port)
				KEY_F2:
					# Quick join using code typed in AddressInput field
					_update_player_name()
					if address_input:
						var code := address_input.text.strip_edges()
						if not code.is_empty():
							await MultiplayerManager.join_game(code, player_name)
						else:
							_show_error_dialog("Enter a host code in the join dialog before pressing F2")
					else:
						_show_error_dialog("Open the join dialog and enter a host code before pressing F2")

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

# --- Server Browser Functions ---

func _on_refresh_servers() -> void:
	# print("[Server Browser] Refreshing server list...")
	MultiplayerManager.start_server_discovery()
	_refresh_server_list()

func _on_direct_connect() -> void:
	# Hide server browser and show direct connect fields
	if server_browser:
		server_browser.visible = false
	if refresh_button:
		refresh_button.visible = false
	if address_input:
		address_input.visible = true
	if port_input:
		port_input.visible = true
	if direct_connect_button:
		direct_connect_button.text = "Show Browser"
		direct_connect_button.pressed.disconnect(_on_direct_connect)
		direct_connect_button.pressed.connect(_on_show_browser)

func _on_show_browser() -> void:
	# Show server browser and hide direct connect fields
	if server_browser:
		server_browser.visible = true
	if refresh_button:
		refresh_button.visible = true
	if address_input:
		address_input.visible = false
	if port_input:
		port_input.visible = false
	if direct_connect_button:
		direct_connect_button.text = "Direct Connect"
		direct_connect_button.pressed.disconnect(_on_show_browser)
		direct_connect_button.pressed.connect(_on_direct_connect)
	_refresh_server_list()

func _on_server_selected(index: int) -> void:
	if index >= 0 and index < discovered_servers.size():
		var server = discovered_servers[index]
		# print("[Server Browser] Selected server: ", server["name"], " at ", server["ip"], ":", server["port"])

func _on_server_activated(index: int) -> void:
	# Double-click on server to connect
	if index >= 0 and index < discovered_servers.size():
		var server = discovered_servers[index]
		print("[Server Browser] Activated server: ", server.get("name", "Unknown"), " at ", server.get("ip", "Unknown"), ":", server.get("port", -1))
		
		# Close the dialog
		join_dialog.hide()
		
		# Connect to the server
		_connect_to_server(server)

func _connect_to_server(server: Dictionary) -> void:
	var server_ip = server.get("ip", "")
	var server_port = server.get("port", default_port)
	
	# Ensure port is an integer
	if server_port is float:
		server_port = int(server_port)
	
	if server_ip.is_empty():
		_hide_status()
		_show_error_dialog("Invalid server selected.")
		return
	
	# Show status
	_show_status("Connecting to local server " + server_ip + ":" + str(server_port) + "...")
	
	# Attempt to join using direct connection (async function)
	var success = await MultiplayerManager.join_game_direct(server_ip, player_name, server_port)
	
	if not success:
		_hide_status()

func _on_servers_updated(servers: Array[Dictionary]) -> void:
	discovered_servers = servers
	# Throttle refreshes to prevent rapid updates
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_refresh_time < refresh_cooldown:
		# Skip this refresh, it's too soon
		return
	last_refresh_time = current_time
	_refresh_server_list()

func _refresh_server_list() -> void:
	if not server_browser:
		print("[Server Browser] ERROR: server_browser is null!")
		return
	
	if not is_instance_valid(server_browser):
		print("[Server Browser] ERROR: server_browser is not a valid instance!")
		return
		
	print("[Server Browser] Clearing list (current item count: ", server_browser.get_item_count(), ")")
	server_browser.clear()
	discovered_servers = MultiplayerManager.get_discovered_servers()
	
	print("[Server Browser] Refreshing list, found ", discovered_servers.size(), " servers")
	for i in range(discovered_servers.size()):
		var server = discovered_servers[i]
		print("[Server Browser] Server ", i, ": ", server.get("name", "Unknown"), " at ", server.get("ip", "Unknown"), ":", server.get("port", -1))
	
	if discovered_servers.is_empty():
		print("[Server Browser] No servers found, adding placeholder")
		server_browser.add_item("No servers found - Click Refresh to scan")
		server_browser.set_item_disabled(0, true)
		print("[Server Browser] Item count after adding placeholder: ", server_browser.get_item_count())
	else:
		print("[Server Browser] Adding ", discovered_servers.size(), " servers to list")
		for i in range(discovered_servers.size()):
			var server = discovered_servers[i]
			# Ensure port is an integer (JSON might parse it as float)
			var port = server.get("port", 7000)
			if port is float:
				port = int(port)
			
			var server_text = "%s (%d/%d players) - %s:%d" % [
				server.get("name", "Unknown Server"),
				server.get("players", 0),
				server.get("max_players", 8),
				server.get("ip", "Unknown"),
				port
			]
			print("[Server Browser] Adding server ", i, " to list: ", server_text)
			var item_index = server_browser.add_item(server_text)
			print("[Server Browser] Added at index: ", item_index, " (total items now: ", server_browser.get_item_count(), ")")
	
	print("[Server Browser] Final item count: ", server_browser.get_item_count(), " (expected: ", discovered_servers.size() if not discovered_servers.is_empty() else 1, ")")
	print("[Server Browser] ItemList visible: ", server_browser.visible, ", size: ", server_browser.size, ", position: ", server_browser.position)
	
	# Force update the ItemList
	server_browser.queue_redraw()
	
	# Verify items are actually there
	if server_browser.get_item_count() > 0:
		print("[Server Browser] First item text: ", server_browser.get_item_text(0))
		print("[Server Browser] ItemList is_valid: ", is_instance_valid(server_browser), ", in_tree: ", server_browser.is_inside_tree())

func _on_join_dialog_about_to_popup() -> void:
	# Reset to browser view when dialog opens
	print("[Server Browser] Join dialog about to popup")
	_on_show_browser()
	# Don't refresh here - let it refresh after popup
	# _refresh_server_list()
