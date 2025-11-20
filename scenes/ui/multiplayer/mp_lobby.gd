extends Control
## Multiplayer Lobby V3 - Modeled after FPS Framework LobbyMenu
## Full-featured lobby with player management, chat, game settings, and team display

# --- UI References ---
@onready var players_label: Label = $HBoxContainer/LeftPanel/PlayersPanel/VBoxContainer/PlayersLabel
@onready var players_list: ItemList = $HBoxContainer/LeftPanel/PlayersPanel/VBoxContainer/PlayersList
@onready var start_game_button: Button = $HBoxContainer/LeftPanel/ButtonsContainer/StartGame
@onready var leave_game_button: Button = $HBoxContainer/LeftPanel/ButtonsContainer/LeaveGame

# --- Game Settings UI ---
@onready var game_mode_option: OptionButton = $HBoxContainer/RightPanel/GameSettingsPanel/VBoxContainer/GameModeContainer/GameModeOption
@onready var score_limit_spinbox: SpinBox = $HBoxContainer/RightPanel/GameSettingsPanel/VBoxContainer/ScoreLimitContainer/ScoreLimitSpinBox
@onready var time_limit_spinbox: SpinBox = $HBoxContainer/RightPanel/GameSettingsPanel/VBoxContainer/TimeLimitContainer/TimeLimitSpinBox
@onready var map_option: OptionButton = $HBoxContainer/RightPanel/GameSettingsPanel/VBoxContainer/MapOption

# --- Join Code Display ---
@onready var join_code_display: Label = $HBoxContainer/RightPanel/JoinCodePanel/JoinCodeContainer/JoinCodeDisplay
@onready var copy_button: Button = $HBoxContainer/RightPanel/JoinCodePanel/JoinCodeContainer/CopyButton

# --- Chat UI ---
@onready var chat_display: RichTextLabel = $HBoxContainer/RightPanel/ChatPanel/VBoxContainer/ChatDisplay
@onready var chat_input: LineEdit = $HBoxContainer/RightPanel/ChatPanel/VBoxContainer/ChatInput
@onready var status_label: Label = $StatusBar/StatusLabel

# --- State ---
var is_host: bool = false
var match_active: bool = false
var connected_players: Dictionary = {}
var chat_messages: Array[Dictionary] = []
var current_settings: Dictionary = {}

# --- Available Maps ---
var available_maps: Array[Dictionary] = []

# Map scanning configuration
var map_directories: Array[String] = [
	"res://maps/",
	"res://scenes/",
]
var map_file_extensions: Array[String] = [".tscn"]
var excluded_scenes: Array[String] = [
	"lobby.tscn",
	"main_menu.tscn",
	"multiplayer_menu.tscn",
	"multiplayer_menu_v2.tscn",
	"multiplayer_menu_v3.tscn",
	"multiplayer_game.tscn",
	"pause_menu.tscn",
]

func _ready() -> void:
	# Scan for available maps
	_scan_for_maps()
	
	# Determine if we're the host
	is_host = MultiplayerManager.is_server()
	
	# Connect UI signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_game_button.pressed.connect(_on_leave_game_pressed)
	chat_input.text_submitted.connect(_on_chat_submitted)
	copy_button.pressed.connect(_on_copy_code_pressed)
	
	# Connect game settings signals (only for host)
	if is_host:
		game_mode_option.item_selected.connect(_on_game_mode_changed)
		score_limit_spinbox.value_changed.connect(_on_score_limit_changed)
		time_limit_spinbox.value_changed.connect(_on_time_limit_changed)
		map_option.item_selected.connect(_on_map_changed)
	else:
		_disable_host_controls()
	
# Connect to multiplayer events
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)
		MultiplayerManager.game_started.connect(_on_game_started)
		MultiplayerManager.match_state_changed.connect(_on_match_state_changed)
		if MultiplayerManager.has_signal("session_id_changed"):
			MultiplayerManager.session_id_changed.connect(_on_session_id_changed)
	
	if GameRulesManager:
		match_active = GameRulesManager.is_match_active()
	
	# Initialize settings
	_initialize_settings()
	
	# Load current players
	_refresh_players_list()

	# Show session code for host
	if is_host and MultiplayerManager:
		var code: String = ""
		if MultiplayerManager.has_method("get_join_code"):
			code = MultiplayerManager.get_join_code()
		if not code.is_empty() and join_code_display:
			join_code_display.text = code.to_upper()
		elif join_code_display:
			join_code_display.text = "-----"
	
	# Add welcome message
	_add_chat_message("System", "Welcome to the lobby!", Color.YELLOW)
	
	# Update UI state
	_update_ui_state()


func _initialize_settings() -> void:
	var default_map_index: int = 0
	if available_maps.is_empty():
		default_map_index = -1
	
	current_settings = {
		"game_mode": GameRulesManager.GameMode.DEATHMATCH if GameRulesManager else 0,
		"score_limit": 25,
		"time_limit": 5,
		"map_index": default_map_index
	}
	
	# Update UI to match settings
	if game_mode_option:
		game_mode_option.selected = current_settings.game_mode
	if score_limit_spinbox:
		score_limit_spinbox.value = current_settings.score_limit
	if time_limit_spinbox:
		time_limit_spinbox.value = current_settings.time_limit
	
	if not available_maps.is_empty() and map_option:
		map_option.selected = current_settings.map_index


func _disable_host_controls() -> void:
	if game_mode_option:
		game_mode_option.disabled = true
	if score_limit_spinbox:
		score_limit_spinbox.editable = false
	if time_limit_spinbox:
		time_limit_spinbox.editable = false
	if map_option:
		map_option.disabled = true
	if start_game_button:
		start_game_button.disabled = true


func _scan_for_maps() -> void:
	available_maps.clear()
	
	for directory_path in map_directories:
		_scan_directory_for_maps(directory_path)
	
	available_maps.sort_custom(func(a, b): return a.name < b.name)
	_populate_map_options()
	
	print("Found %d maps" % available_maps.size())


func _scan_directory_for_maps(directory_path: String) -> void:
	var dir: DirAccess = DirAccess.open(directory_path)
	if not dir:
		print("Could not open directory: ", directory_path)
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir():
			var is_scene_file: bool = false
			for extension in map_file_extensions:
				if file_name.ends_with(extension):
					is_scene_file = true
					break
			
			if is_scene_file and file_name not in excluded_scenes:
				var full_path: String = directory_path + file_name
				var map_name: String = _generate_map_name(file_name)
				
				if ResourceLoader.exists(full_path):
					available_maps.append({
						"name": map_name,
						"path": full_path
					})
		
		file_name = dir.get_next()


func _generate_map_name(file_name: String) -> String:
	var map_name: String = file_name.get_basename()
	map_name = map_name.replace("_", " ")
	var words: PackedStringArray = map_name.split(" ")
	var capitalized_words: Array[String] = []
	
	for word in words:
		if word.length() > 0:
			capitalized_words.append(word.capitalize())
	
	return " ".join(capitalized_words)


func _populate_map_options() -> void:
	if not map_option:
		return
	
	map_option.clear()
	
	for i in range(available_maps.size()):
		var map_data: Dictionary = available_maps[i]
		map_option.add_item(map_data.name)
	
	if available_maps.is_empty():
		map_option.add_item("No maps found")
		map_option.set_item_disabled(0, true)


func _update_ui_state() -> void:
	var player_count: int = connected_players.size()
	var max_players: int = 8
	
	if players_label:
		players_label.text = "Players (%d/%d)" % [player_count, max_players]
	
	# Update start button
	if match_active:
		if is_host:
			if start_game_button:
				start_game_button.text = "Match In Progress"
				start_game_button.disabled = true
			if status_label:
				status_label.text = "Match is currently active"
		else:
			if start_game_button:
				start_game_button.text = "Join Match"
				start_game_button.disabled = not (MultiplayerManager and MultiplayerManager.current_game_path)
			if status_label:
				status_label.text = "Match in progress - join to re-enter"
	else:
		if start_game_button:
			start_game_button.text = "Start Game"
			if is_host:
				start_game_button.disabled = player_count < 1
			else:
				start_game_button.disabled = true
		
		if status_label:
			if is_host:
				status_label.text = "Ready to start game" if player_count >= 1 else "Waiting for players..."
			else:
				status_label.text = "Waiting for host to start game..."


# --- Player Management ---

func _refresh_players_list() -> void:
	if not players_list:
		return
	
	players_list.clear()
	connected_players = MultiplayerManager.get_connected_players()
	
	for peer_id in connected_players:
		var player_info: Dictionary = connected_players[peer_id]
		var player_name: String = player_info.get("name", "Player %d" % peer_id)
		var team_id: int = player_info.get("team", 0)
		
		# Build display text
		var display_text: String = player_name
		if TeamManager and TeamManager.get_all_teams_info().size() > 1:
			var team_info: Dictionary = TeamManager.get_team_info(team_id)
			display_text += " (" + team_info["name"] + ")"
		
		# Mark host
		if peer_id == 1:
			display_text += " [HOST]"
		
		players_list.add_item(display_text)
		
		# Set team color
		if TeamManager:
			var team_info: Dictionary = TeamManager.get_team_info(team_id)
			var color: Color = team_info["color"]
			players_list.set_item_custom_bg_color(players_list.get_item_count() - 1, color * Color(1, 1, 1, 0.3))


func _on_player_connected(peer_id: int) -> void:
	_refresh_players_list()
	_update_ui_state()
	_add_chat_message("System", "Player %d joined the lobby" % peer_id, Color.GREEN)


func _on_player_disconnected(peer_id: int) -> void:
	_refresh_players_list()
	_update_ui_state()
	_add_chat_message("System", "Player %d left the lobby" % peer_id, Color.RED)


# --- Game Settings (Host Only) ---

func _on_game_mode_changed(index: int) -> void:
	if not is_host:
		return
	current_settings.game_mode = index
	_sync_settings()


func _on_score_limit_changed(value: float) -> void:
	if not is_host:
		return
	current_settings.score_limit = int(value)
	_sync_settings()


func _on_time_limit_changed(value: float) -> void:
	if not is_host:
		return
	current_settings.time_limit = int(value)
	_sync_settings()


func _on_map_changed(index: int) -> void:
	if not is_host:
		return
	current_settings.map_index = index
	_sync_settings()


func _sync_settings() -> void:
	if is_host:
		sync_lobby_settings.rpc(current_settings)


@rpc("authority", "call_local", "reliable")
func sync_lobby_settings(settings: Dictionary) -> void:
	current_settings = settings
	
	if not is_host:
		if game_mode_option:
			game_mode_option.selected = settings.game_mode
		if score_limit_spinbox:
			score_limit_spinbox.value = settings.score_limit
		if time_limit_spinbox:
			time_limit_spinbox.value = settings.time_limit
		
		if not available_maps.is_empty() and settings.map_index >= 0 and settings.map_index < available_maps.size():
			if map_option:
				map_option.selected = settings.map_index
	
	var mode_names: Array[String] = ["Deathmatch", "Team Deathmatch", "Cooperative", "Duel"]
	var mode_name: String = mode_names[settings.game_mode] if settings.game_mode < mode_names.size() else "Unknown"
	var map_name: String = "Unknown"
	if not available_maps.is_empty() and settings.map_index >= 0 and settings.map_index < available_maps.size():
		map_name = available_maps[settings.map_index]["name"]
	
	_add_chat_message("System", "Settings: %s, Score: %d, Time: %d min, Map: %s" % [
		mode_name, settings.score_limit, settings.time_limit, map_name
	], Color.CYAN)


# --- Chat System ---

func _on_chat_submitted(text: String) -> void:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return
	
	var player_info: Dictionary = MultiplayerManager.get_player_info(MultiplayerManager.get_local_peer_id())
	var player_name: String = player_info.get("name", "Player")
	
	send_chat_message.rpc(player_name, trimmed)
	
	if chat_input:
		chat_input.clear()


@rpc("any_peer", "call_local", "reliable")
func send_chat_message(sender_name: String, message: String) -> void:
	_add_chat_message(sender_name, message, Color.WHITE)


func _add_chat_message(sender: String, message: String, color: Color = Color.WHITE) -> void:
	var time_dict: Dictionary = Time.get_time_dict_from_system()
	var timestamp: String = "%02d:%02d" % [time_dict.hour, time_dict.minute]
	
	var formatted_message: String = "[color=#%s][%s] %s: %s[/color]" % [
		color.to_html(false),
		timestamp,
		sender,
		message
	]
	
	if chat_display:
		chat_display.append_text(formatted_message + "\n")
	
	chat_messages.append({
		"sender": sender,
		"message": message,
		"timestamp": timestamp,
		"color": color
	})
	
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
		
		if available_maps.is_empty():
			_add_chat_message("System", "No maps available", Color.RED)
			return
		
		var map_index: int = current_settings.map_index
		if map_index < 0 or map_index >= available_maps.size():
			_add_chat_message("System", "Invalid map selected", Color.RED)
			return
		
		var map_path: String = available_maps[map_index]["path"]
		
		_add_chat_message("System", "Starting game...", Color.YELLOW)
		MultiplayerManager.start_game(map_path)


func _on_leave_game_pressed() -> void:
	MultiplayerManager.disconnect_from_game()
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer/mp_menu.tscn")


func _on_game_started() -> void:
	match_active = true
	_update_ui_state()


func _on_return_to_lobby() -> void:
	match_active = false
	_update_ui_state()


func _on_match_state_changed(active: bool) -> void:
	match_active = active
	_update_ui_state()


func _on_session_id_changed(new_code: String) -> void:
	if is_host and join_code_display:
		if not new_code.is_empty():
			join_code_display.text = new_code.to_upper()
		else:
			join_code_display.text = "-----"


func _on_copy_code_pressed() -> void:
	if join_code_display and not join_code_display.text.is_empty():
		var code: String = join_code_display.text
		if code != "-----":
			DisplayServer.clipboard_set(code)
			_add_chat_message("System", "Join code copied to clipboard!", Color.CYAN)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if not chat_input.has_focus():
					chat_input.grab_focus()
			KEY_ESCAPE:
				if chat_input.has_focus():
					chat_input.release_focus()
