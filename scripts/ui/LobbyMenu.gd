extends Control
class_name LobbyMenu

## Lobby interface for multiplayer games
## Shows connected players, chat, and game settings

# --- UI References ---
@onready var players_label: Label = $HBoxContainer/LeftPanel/PlayersPanel/VBoxContainer/PlayersLabel
@onready var players_list: ItemList = $HBoxContainer/LeftPanel/PlayersPanel/VBoxContainer/PlayersList
@onready var start_game_button: Button = $HBoxContainer/RightPanel/MenuContainer/StartGame
@onready var leave_game_button: Button = $HBoxContainer/LeftPanel/LeaveGame

# --- Game Settings UI ---
@onready var game_mode_option: OptionButton = $HBoxContainer/RightPanel/MenuContainer/ModeRow/GameModeOption
@onready var score_limit_container: Control = $OptionsOverlay/CenterContainer/OptionsBox/ScoreLimitContainer
@onready var time_limit_container: Control = $OptionsOverlay/CenterContainer/OptionsBox/TimeLimitContainer
@onready var map_option: OptionButton = $HBoxContainer/RightPanel/MenuContainer/MapRow/MapOption
@onready var map_thumbnail: TextureRect = $HBoxContainer/RightPanel/MenuContainer/MapThumbnail

# --- Options Overlay ---
@onready var options_overlay: Control = $OptionsOverlay
@onready var game_options_button: Button = $HBoxContainer/RightPanel/MenuContainer/GameOptionsButton
@onready var close_options_button: Button = $OptionsOverlay/CenterContainer/OptionsBox/CloseOptionsButton

# --- Session Code UI ---
@onready var code_label: Label = $OptionsOverlay/CenterContainer/OptionsBox/SessionCodeContainer/CodeLabel
@onready var copy_code_button: Button = $OptionsOverlay/CenterContainer/OptionsBox/SessionCodeContainer/CopyCodeButton

# --- Chat UI ---
@onready var chat_display: RichTextLabel = $HBoxContainer/LeftPanel/ChatPanel/VBoxContainer/ChatDisplay
@onready var chat_input: LineEdit = $HBoxContainer/LeftPanel/ChatPanel/VBoxContainer/ChatInput
@onready var status_label: Label = $StatusBar/StatusLabel

# --- State ---
var is_host: bool = false
var match_active: bool = false
var connected_players: Dictionary = {}
var chat_messages: Array[Dictionary] = []
var current_settings: Dictionary = {}

# --- Available Maps ---
# Maps are now populated dynamically by scanning directories
var all_maps: Array[Dictionary] = []      # Master list of all found maps
var available_maps: Array[Dictionary] = [] # Currently filtered list based on gamemode

# Map scanning configuration
var map_directories: Array[String] = [
	"res://maps/mp/"  # Dedicated multiplayer map directory
]
var map_file_extensions: Array[String] = [".tscn"]
var excluded_scenes: Array[String] = [
	"lobby.tscn",
	"main_menu.tscn",
	"NetworkedPlayer.tscn",
	"PauseMenu.tscn",
	"tester.tscn"
]

func _ready() -> void:
	# Scan for available maps first
	_scan_for_maps()

	# Determine if we're the host
	is_host = MultiplayerManager.is_hosting

	# Connect UI signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_game_button.pressed.connect(_on_leave_game_pressed)
	chat_input.text_submitted.connect(_on_chat_submitted)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	
	# Options overlay signals
	game_options_button.pressed.connect(func(): options_overlay.visible = true)
	close_options_button.pressed.connect(func(): options_overlay.visible = false)
	
	# Only hosts can change map selection
	if is_host:
		map_option.item_selected.connect(_on_map_changed)
		game_mode_option.item_selected.connect(_on_game_mode_changed)
	else:
		_disable_host_controls()
	
	# Connect to multiplayer events
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)
		MultiplayerManager.game_started.connect(_on_game_started)
		MultiplayerManager.returned_to_lobby.connect(_on_returned_to_lobby)
		MultiplayerManager.match_state_changed.connect(_on_match_state_changed)
		MultiplayerManager.lobby_ready.connect(_on_lobby_ready)
		match_active = MultiplayerManager.current_game_path != ""
	else:
		match_active = false
	
	if GameRulesManager:
		match_active = match_active or GameRulesManager.match_active
	
	# Initialize current settings
	_initialize_settings()
	
	# Load current players
	_refresh_players_list()
	
	# Add welcome message
	_add_chat_message("System", "Welcome to the lobby!", Color.YELLOW)
	
	# Update UI state
	_update_ui_state()
	
	# Update session code display
	_update_session_code()
	
	# Set up periodic check for session code (in case it arrives after lobby loads)
	_setup_session_code_check()

func _initialize_settings() -> void:
	# Ensure we have a valid map index
	var default_map_index = 0
	if available_maps.is_empty():
		default_map_index = -1

	current_settings = {
		"map_index": default_map_index
	}

	# Only set map selection if we have maps available
	if not available_maps.is_empty():
		map_option.selected = current_settings.map_index
		_update_map_thumbnail(available_maps[current_settings.map_index].name)
	else:
		# Keep the placeholder visible if no maps are available
		pass

func _disable_host_controls() -> void:
	# Only host can change maps/start games
	map_option.disabled = true
	game_mode_option.disabled = true
	start_game_button.disabled = true

func _scan_for_maps() -> void:
	all_maps.clear()

	# Scan each directory for map files
	for directory_path in map_directories:
		_scan_directory_for_maps(directory_path)

	# Sort maps alphabetically by name
	all_maps.sort_custom(func(a, b): return a.name < b.name)

	# Initial filter based on default selection
	_on_game_mode_changed(game_mode_option.selected)

	print("Found %d total maps. Filtered to %d maps for mode %d" % [all_maps.size(), available_maps.size(), game_mode_option.selected])

func _scan_directory_for_maps(directory_path: String) -> void:
	# Use ResourceLoader.list_directory (Godot 4.4+) for PCK compatibility in exported builds
	# Check engine version - ResourceLoader.list_directory was added in 4.4
	var version_info = Engine.get_version_info()
	var use_resource_loader = version_info.major >= 4 and version_info.minor >= 4
	
	if use_resource_loader:
		_scan_directory_with_resource_loader(directory_path)
		return
	
	# Fallback to DirAccess for older versions or editor
	var dir = DirAccess.open(directory_path)
	if not dir:
		print("Could not open directory: ", directory_path)
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if not dir.current_is_dir():
			# Check if it's a scene file and not excluded
			var is_scene_file = false
			for extension in map_file_extensions:
				if file_name.ends_with(extension):
					is_scene_file = true
					break

			if is_scene_file and not file_name in excluded_scenes:
				var full_path = directory_path + file_name
				var map_name = _generate_map_name(file_name)

				# Verify the scene file exists and is valid
				if ResourceLoader.exists(full_path):
					all_maps.append({
						"name": map_name,
						"path": full_path,
						"filename": file_name.get_basename()
					})

		file_name = dir.get_next()


func _scan_directory_with_resource_loader(directory_path: String) -> void:
	# Use ResourceLoader.list_directory for PCK compatibility (Godot 4.4+)
	var files: PackedStringArray = ResourceLoader.list_directory(directory_path)
	
	for file_name in files:
		# Check if it's a scene file and not excluded
		var is_scene_file = false
		for extension in map_file_extensions:
			if file_name.ends_with(extension):
				is_scene_file = true
				break
		
		if is_scene_file and not file_name in excluded_scenes:
			var full_path = directory_path + file_name
			var map_name = _generate_map_name(file_name)
			
			# Verify the scene file exists and is valid
			if ResourceLoader.exists(full_path):
				all_maps.append({
					"name": map_name,
					"path": full_path,
					"filename": file_name.get_basename()
				})

func _generate_map_name(file_name: String) -> String:
	# Remove file extension
	var map_name = file_name.get_basename()

	# Convert underscores to spaces and capitalize words
	# But we also want to keep prefixes visible for sorting/grouping?
	# User requested: "maps sorted by prefix; archstiletto_, duelists_, etc"
	# So maybe we should keep the raw name or format it nicely but keep the prefix structure?
	# The current logic capitalizes words. e.g. "archstiletto_nucleus" -> "Archstiletto Nucleus".
	# This preserves the prefix word order.
	
	map_name = map_name.replace("_", " ")
	var words = map_name.split(" ")
	var capitalized_words: Array[String] = []

	for word in words:
		if word.length() > 0:
			capitalized_words.append(word.capitalize())

	return " ".join(capitalized_words)

func _on_game_mode_changed(index: int) -> void:
	available_maps.clear()
	
	# Filter maps based on selected mode
	# Mode 0: Duel (prefix: "duelists_")
	# Mode 1: Archstiletto (prefix: "archstiletto_")
	
	var prefix = ""
	match index:
		0: prefix = "duelists_"
		1: prefix = "archstiletto_"
		_: prefix = "" # Show all if unknown
		
	for map_data in all_maps:
		var filename = map_data.filename.to_lower()
		if prefix == "" or filename.begins_with(prefix):
			available_maps.append(map_data)
			
	# Refresh UI
	_populate_map_options()
	
	# Update current selection
	if not available_maps.is_empty():
		_on_map_changed(0)
	else:
		# No maps available - keep the placeholder thumbnail
		current_settings.map_index = -1
		_sync_settings()

func _populate_map_options() -> void:
	# Clear existing options
	map_option.clear()

	# Add each map to the option button
	for i in range(available_maps.size()):
		var map_data = available_maps[i]
		map_option.add_item(map_data.name)

	# Ensure we have at least one map
	if available_maps.is_empty():
		map_option.add_item("No maps found")
		map_option.set_item_disabled(0, true)
		print("Warning: No valid map files found!")

func _update_map_thumbnail(map_name: String) -> void:
	# Load thumbnail from pre-generated assets
	# Thumbnails are generated by tools/generate_map_thumbs.gd and saved to res://assets/map_thumbs/
	# If no thumbnail is found, preserve the placeholder texture set in the scene
	
	# If map_name is empty, keep the placeholder
	if map_name.is_empty():
		return
	
	# Find map data to get filename
	var map_data = null
	for m in available_maps:
		if m.name == map_name:
			map_data = m
			break
	
	if not map_data:
		# No map data found - keep the placeholder
		return
	
	# Construct thumbnail path using the scene filename (without extension)
	var base_name: String = map_data.get("filename", "")
	if base_name.is_empty():
		# No filename - keep the placeholder
		return
	
	var thumb_path := "res://assets/map_thumbs/%s.png" % base_name
	
	# Try to load the thumbnail
	if ResourceLoader.exists(thumb_path):
		var thumb_texture := load(thumb_path) as Texture2D
		if thumb_texture:
			map_thumbnail.texture = thumb_texture
		# If loading fails, keep the placeholder (don't set to null)
	else:
		# No thumbnail found - keep the placeholder texture from the scene
		pass

func _update_ui_state() -> void:
	# Update players count
	var player_count = connected_players.size()
	var max_players = 8  # Could be configurable
	players_label.text = "Players (%d/%d)" % [player_count, max_players]
	
	# Update start button (only host can start, need at least 1 player)
	if match_active:
		if is_host:
			start_game_button.text = "MATCH IN PROGRESS"
			start_game_button.disabled = true
			status_label.text = "Match is currently active"
		else:
			start_game_button.text = "JOIN MATCH"
			start_game_button.disabled = not MultiplayerManager or not MultiplayerManager.current_game_path
			status_label.text = "Match in progress - join to re-enter"
	else:
		start_game_button.text = "START GAME"
		if is_host:
			start_game_button.disabled = player_count < 1
			status_label.text = "Ready to start game" if player_count >= 1 else "Waiting for players..."
		else:
			start_game_button.disabled = true
			status_label.text = "Waiting for host to start game..."

# --- Player Management ---

func _refresh_players_list() -> void:
	players_list.clear()
	connected_players = MultiplayerManager.get_connected_players()
	
	print("-- Refreshing lobby player list --")
	print("MultiplayerManager players: ", connected_players)
	print("Local peer ID: ", MultiplayerManager.get_local_peer_id())
	
	for peer_id in connected_players:
		var player_info = connected_players[peer_id]
		var player_name = player_info.get("name", "Player " + str(peer_id))
		var team_id = player_info.get("team", 0)
		print("Processing peer %d: %s (team %d)" % [peer_id, player_name, team_id])
		
		# Add player to list with team info
		var display_text = player_name
		if TeamManager and TeamManager.get_all_teams_info().size() > 1:
			var team_info = TeamManager.get_team_info(team_id)
			display_text += " (" + team_info.name + ")"
		
		# Mark host
		if peer_id == 1:
			display_text += " [HOST]"
		
		players_list.add_item(display_text)
		
		# Set team color if available
		if TeamManager:
			var team_info = TeamManager.get_team_info(team_id)
			players_list.set_item_custom_bg_color(players_list.get_item_count() - 1, team_info.color)
	
	# Update session code when players list refreshes (in case host OID becomes available)
	_update_session_code()

func _on_player_connected(_peer_id: int, player_info: Dictionary) -> void:
	print("Player connected to lobby: ", player_info.name)
	_refresh_players_list()
	_update_ui_state()
	_update_session_code()  # Update in case host OID was just synced
	
	# Add chat message
	_add_chat_message("System", player_info.name + " joined the lobby", Color.GREEN)

func _on_player_disconnected(peer_id: int) -> void:
	print("Player disconnected from lobby: ", peer_id)
	_refresh_players_list()
	_update_ui_state()
	
	# Add chat message
	_add_chat_message("System", "Player left the lobby", Color.RED)

# --- Game Settings (Host Only) ---

func _on_map_changed(index: int) -> void:
	if not is_host:
		return
	
	current_settings.map_index = index
	_sync_settings()
	
	# Update thumbnail locally for host
	if available_maps.size() > index:
		_update_map_thumbnail(available_maps[index].name)

func _sync_settings() -> void:
	# Sync settings to all clients
	if is_host:
		sync_lobby_settings.rpc(current_settings)

@rpc("authority", "call_local", "reliable")
func sync_lobby_settings(settings: Dictionary) -> void:
	current_settings = settings

	# Update UI if not host
	if not is_host:
		# Only update map selection if we have maps and valid index
		if not available_maps.is_empty() and settings.map_index >= 0 and settings.map_index < available_maps.size():
			map_option.selected = settings.map_index
			_update_map_thumbnail(available_maps[settings.map_index].name)

	# Show settings change in chat
	var map_name = "Unknown"
	if not available_maps.is_empty() and settings.map_index >= 0 and settings.map_index < available_maps.size():
		map_name = available_maps[settings.map_index].name

	_add_chat_message("System", "Map set to: %s" % map_name, Color.CYAN)

# --- Chat System ---

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	
	var player_info = MultiplayerManager.get_player_info(MultiplayerManager.get_local_peer_id())
	var player_name = player_info.get("name", "Player")
	
	# Send chat message to all players
	send_chat_message.rpc(player_name, text.strip_edges())
	
	# Clear input
	chat_input.clear()

@rpc("any_peer", "call_local", "reliable")
func send_chat_message(sender_name: String, message: String) -> void:
	_add_chat_message(sender_name, message, Color.WHITE)

func _add_chat_message(sender: String, message: String, color: Color = Color.WHITE) -> void:
	# Add timestamp
	var time_dict = Time.get_time_dict_from_system()
	var timestamp = "%02d:%02d" % [time_dict.hour, time_dict.minute]
	
	# Format message with BBCode
	var formatted_message = "[color=#%s][%s] %s: %s[/color]" % [
		color.to_html(false),
		timestamp,
		sender,
		message
	]
	
	chat_display.append_text(formatted_message + "\n")
	
	# Store message
	chat_messages.append({
		"sender": sender,
		"message": message,
		"timestamp": timestamp,
		"color": color
	})
	
	# Limit chat history
	if chat_messages.size() > 100:
		chat_messages.pop_front()

# --- Game Control ---

func _on_start_game_pressed() -> void:
	if is_host:
		if match_active:
			return
		
		if connected_players.size() < 1:
			_add_chat_message("System", "Need at least 1 player to start", Color.RED)
			return
		
		# Check if we have any maps available
		if available_maps.is_empty():
			_add_chat_message("System", "No maps available to start the game", Color.RED)
			return
		
		# Validate map index
		var map_index = current_settings.map_index
		if map_index < 0 or map_index >= available_maps.size():
			_add_chat_message("System", "Invalid map selected", Color.RED)
			return
		
		# Get selected map
		var map_path = available_maps[map_index].path
		
		_add_chat_message("System", "Starting game...", Color.YELLOW)
		
		# Start the game
		MultiplayerManager.start_game(map_path)
	else:
		if match_active and start_game_button.text == "Join Match":
			print("[LobbyMenu] Client requested to join active match")
			MultiplayerManager.join_active_match()

func _on_leave_game_pressed() -> void:
	# Disconnect and return to main menu
	MultiplayerManager.disconnect_from_game()

func _on_game_started() -> void:
	# Game is starting, this will be handled by scene change
	print("Game started from lobby")
	match_active = true
	_update_ui_state()

func _on_returned_to_lobby() -> void:
	if GameRulesManager:
		match_active = GameRulesManager.match_active
	else:
		match_active = false
	_update_ui_state()

func _on_match_state_changed(active: bool) -> void:
	match_active = active
	_update_ui_state()

func _on_lobby_ready() -> void:
	# Update session code when lobby becomes ready (OID should be available)
	_update_session_code()

# --- Input Handling ---

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				# Focus chat input
				if not chat_input.has_focus():
					chat_input.grab_focus()
			KEY_ESCAPE:
				# Focus away from chat
				if chat_input.has_focus():
					chat_input.release_focus()
				# Also close options if open
				if options_overlay.visible:
					options_overlay.visible = false
			KEY_F5:
				# Refresh players list
				_refresh_players_list()

# --- Team Management (Future Enhancement) ---

func _on_player_item_selected(index: int) -> void:
	# Could be used for team management, kicking players, etc.
	if not is_host:
		return
	
	# Get selected player
	if index < 0 or index >= players_list.get_item_count():
		return
	
	# For now, just show player info
	var player_keys = connected_players.keys()
	if index < player_keys.size():
		var peer_id = player_keys[index]
		var player_info = connected_players[peer_id]
		print("Selected player: ", player_info)

# --- Session Code Management ---

func _update_session_code() -> void:
	if not MultiplayerManager:
		code_label.text = "---"
		return
	
	var session_code: String = "---"
	
	if is_host:
		# Host: use our own OID
		if MultiplayerManager.noray_oid:
			session_code = MultiplayerManager.noray_oid
	else:
		# Client: get host's OID from connected players
		var players = MultiplayerManager.get_connected_players()
		if 1 in players:  # Host is always peer_id 1
			var host_info = players[1]
			if host_info.has("noray_oid") and host_info["noray_oid"]:
				session_code = host_info["noray_oid"]
	
	code_label.text = session_code

func _on_copy_code_pressed() -> void:
	var code = code_label.text
	if code and code != "---":
		DisplayServer.clipboard_set(code)
		_add_chat_message("System", "Session code copied to clipboard: %s" % code, Color.CYAN)
	else:
		_add_chat_message("System", "No session code available", Color.RED)

func _setup_session_code_check() -> void:
	# Periodically check for session code (especially for clients waiting for host OID)
	# This ensures the code appears even if it arrives after the lobby loads
	if not is_host:
		# For clients, check every second until we have the code
		var timer = Timer.new()
		timer.wait_time = 1.0
		timer.timeout.connect(_check_session_code_available)
		timer.add_to_group("session_code_timer")
		add_child(timer)
		timer.start()

func _check_session_code_available() -> void:
	# Only check if we don't have a code yet
	if code_label.text == "---":
		var old_code = code_label.text
		_update_session_code()
		# If we found the code, stop checking
		if code_label.text != "---" and code_label.text != old_code:
			# Stop the timer
			var timers = get_tree().get_nodes_in_group("session_code_timer")
			for timer in timers:
				timer.queue_free()

# --- Utility Functions ---

# --- Admin Commands (Future Enhancement) ---

func _process_admin_command(command: String) -> void:
	# Could be used for admin commands in chat
	if not is_host:
		return
	
	var parts = command.split(" ")
	if parts.size() == 0:
		return
	
	match parts[0].to_lower():
		"/kick":
			if parts.size() > 1:
				# Kick player by name
				pass
		"/balance":
			# Balance teams
			if TeamManager:
				TeamManager.balance_teams()
				_add_chat_message("System", "Teams have been balanced", Color.CYAN)
		"/settings":
			# Show current settings
			var map_name = "Unknown"
			if not available_maps.is_empty() and current_settings.map_index >= 0 and current_settings.map_index < available_maps.size():
				map_name = available_maps[current_settings.map_index].name
			_add_chat_message("System", "Current map: %s" % map_name, Color.CYAN)
