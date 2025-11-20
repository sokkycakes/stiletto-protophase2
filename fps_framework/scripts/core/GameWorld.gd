extends Node3D
class_name GameWorld

## Main game world controller for multiplayer matches
## Handles player spawning, game flow, and coordination between systems

# --- Player Management ---
var networked_player_scene: PackedScene = preload("res://scenes/NetworkedPlayer.tscn")
var players: Dictionary = {}  # peer_id -> NetworkedPlayer instance
var spawn_points: Array[SpawnPoint] = []

# --- Game State ---
var game_active: bool = false
var match_started: bool = false

# --- UI References ---
@onready var players_container: Node3D = $Players
@onready var health_bar: ProgressBar = $UI/GameHUD/HealthBar
@onready var health_label: Label = $UI/GameHUD/HealthLabel
@onready var ammo_label: Label = $UI/GameHUD/AmmoLabel
@onready var score_label: Label = $UI/GameHUD/ScoreLabel
@onready var time_label: Label = $UI/GameHUD/TimeLabel
@onready var chat_display: RichTextLabel = $UI/GameHUD/ChatPanel/VBoxContainer/ChatDisplay
@onready var chat_input: LineEdit = $UI/GameHUD/ChatPanel/VBoxContainer/ChatInput

# --- Local Player Reference ---
var local_player: NetworkedPlayer

func _ready() -> void:
	# Hide chat input initially
	chat_input.visible = false
	
	# Connect to multiplayer events
	if MultiplayerManager:
		if not MultiplayerManager.player_connected.is_connected(_on_player_connected_to_game):
			MultiplayerManager.player_connected.connect(_on_player_connected_to_game)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)
	
	# Connect to game rules
	if GameRulesManager:
		GameRulesManager.match_started.connect(_on_match_started)
		GameRulesManager.match_ended.connect(_on_match_ended)
		GameRulesManager.match_time_updated.connect(_on_match_time_updated)
	
	# Connect chat input
	chat_input.text_submitted.connect(_on_chat_submitted)
	
	# Collect spawn points
	_collect_spawn_points()
	
	# Spawn players
	_spawn_all_players()
	
	# Start the match
	if MultiplayerManager.is_server():
		await get_tree().create_timer(2.0).timeout  # Give time for all players to load
		GameRulesManager.start_match()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				# Toggle chat
				_toggle_chat()
			KEY_ESCAPE:
				# Hide chat; toggle pause menu without pausing the game.
				if chat_input.visible:
					_hide_chat()
				else:
					_toggle_pause_menu()
			KEY_TAB:
				# Show scoreboard (while held)
				_show_scoreboard(true)
	elif event is InputEventKey and not event.pressed:
		match event.keycode:
			KEY_TAB:
				# Hide scoreboard
				_show_scoreboard(false)

# --- Spawn Point Management ---

func _collect_spawn_points() -> void:
	spawn_points.clear()
	
	# Find all spawn points in the scene
	var spawn_nodes = get_tree().get_nodes_in_group("spawn_points")
	for node in spawn_nodes:
		if node is SpawnPoint:
			spawn_points.append(node)
	
	print("Found ", spawn_points.size(), " spawn points")

func get_spawn_point_for_player(peer_id: int) -> Vector3:
	if spawn_points.is_empty():
		return Vector3(0, 2, 0)  # Default spawn
	
	var player_info = MultiplayerManager.get_player_info(peer_id)
	var team_id = player_info.get("team", 0)
	
	# Find spawn points for this team
	var team_spawns: Array[SpawnPoint] = []
	for spawn in spawn_points:
		if spawn.team_id == team_id or spawn.team_id == -1:  # -1 means any team
			team_spawns.append(spawn)
	
	# Use team spawns if available, otherwise any spawn
	var available_spawns = team_spawns if team_spawns.size() > 0 else spawn_points
	
	# Find least recently used spawn point
	var best_spawn: SpawnPoint = null
	var oldest_time: float = INF
	
	for spawn in available_spawns:
		if spawn.last_used_time < oldest_time:
			oldest_time = spawn.last_used_time
			best_spawn = spawn
	
	if best_spawn:
		best_spawn.use_spawn_point()
		return best_spawn.global_position
	
	# Fallback
	return available_spawns[0].global_position

# --- Player Management ---

func _spawn_all_players() -> void:
	var connected_players = MultiplayerManager.get_connected_players()
	
	for peer_id in connected_players:
		_spawn_player(peer_id)

func _spawn_player(peer_id: int) -> void:
	if peer_id in players:
		return  # Already spawned
	
	var player_info = MultiplayerManager.get_player_info(peer_id)
	var player_name = player_info.get("name", "Player " + str(peer_id))
	var team_id = player_info.get("team", 0)
	
	# Create networked player
	var networked_player = NetworkedPlayer.new()
	networked_player.name = "Player_" + str(peer_id)
	
	# Set spawn position
	var spawn_pos = get_spawn_point_for_player(peer_id)
	networked_player.global_position = spawn_pos
	
	# Initialize player
	networked_player.initialize_player(peer_id, player_name, team_id)
	
	# Add to scene
	players_container.add_child(networked_player)
	players[peer_id] = networked_player
	
	# If this is the local player, set up UI connections
	if peer_id == MultiplayerManager.get_local_peer_id():
		local_player = networked_player
		_setup_local_player_ui()
	
	if MultiplayerManager.is_server():
		call_deferred("_force_sync_existing_players_to_peer", peer_id)
	
	print("Spawned player: ", player_name, " at ", spawn_pos)

func _force_sync_existing_players_to_peer(peer_id: int) -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	await get_tree().create_timer(0.1).timeout
	for existing_id in players:
		if existing_id == peer_id:
			continue
		var existing_player: NetworkedPlayer = players[existing_id]
		if existing_player:
			existing_player.force_sync(peer_id)

func _setup_local_player_ui() -> void:
	if not local_player:
		return
	
	# Connect health updates
	local_player.health_changed.connect(_on_local_player_health_changed)
	
	# Connect weapon manager if available
	if local_player.weapon_manager:
		local_player.weapon_manager.ammo_changed.connect(_on_local_player_ammo_changed)
	
	# Update initial UI
	_update_health_ui(local_player.health)

func _cleanup_local_player_ui() -> void:
	if local_player:
		if local_player.health_changed.is_connected(_on_local_player_health_changed):
			local_player.health_changed.disconnect(_on_local_player_health_changed)
		if local_player.weapon_manager and local_player.weapon_manager.ammo_changed.is_connected(_on_local_player_ammo_changed):
			local_player.weapon_manager.ammo_changed.disconnect(_on_local_player_ammo_changed)
	health_bar.value = 0.0
	health_label.text = "Health: 0"
	ammo_label.text = "Ammo: 0/0"

func _on_player_disconnected(peer_id: int) -> void:
	if peer_id in players:
		var player = players[peer_id]
		player.queue_free()
		players.erase(peer_id)
		print("Removed disconnected player: ", peer_id)

func remove_player_from_match(peer_id: int) -> void:
	if MultiplayerManager and MultiplayerManager.is_server():
		remove_player_from_match_remote.rpc(peer_id)
	else:
		remove_player_from_match_remote(peer_id)

@rpc("authority", "call_local", "reliable")
func remove_player_from_match_remote(peer_id: int) -> void:
	_remove_player_local(peer_id)
	if MultiplayerManager and not MultiplayerManager.is_server():
		if MultiplayerManager.get_local_peer_id() == peer_id:
			MultiplayerManager.on_local_player_removed_from_match()

func _remove_player_local(peer_id: int) -> void:
	if peer_id in players:
		var player = players[peer_id]
		if player == local_player:
			_cleanup_local_player_ui()
			local_player = null
		player.queue_free()
		players.erase(peer_id)
		print("Removed player from match: ", peer_id)

func _on_player_connected_to_game(peer_id: int, _player_info: Dictionary) -> void:
	_spawn_player(peer_id)

# --- Game Flow ---

func _on_match_started() -> void:
	game_active = true
	match_started = true
	_add_chat_message("System", "Match started!", Color.GREEN)

func _on_match_ended(winner_info: Dictionary) -> void:
	game_active = false
	match_started = false
	
	var winner_text = "Match ended!"
	if winner_info.type == "player":
		winner_text = winner_info.name + " wins!"
	elif winner_info.type == "team":
		winner_text = winner_info.name + " wins!"
	
	_add_chat_message("System", winner_text, Color.YELLOW)
	
	# Show end game screen after delay
	await get_tree().create_timer(3.0).timeout
	_show_end_game_screen(winner_info)

func _on_match_time_updated(time_remaining: float) -> void:
	var minutes = int(time_remaining / 60.0)
	var seconds = int(time_remaining) % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]

# --- UI Updates ---

func _on_local_player_health_changed(old_health: float, new_health: float) -> void:
	_update_health_ui(new_health)

func _update_health_ui(health: float) -> void:
	if local_player:
		health_bar.value = health
		health_label.text = "Health: " + str(int(health))

func _on_local_player_ammo_changed(ammo_in_clip: int, total_ammo: int) -> void:
	ammo_label.text = "Ammo: %d/%d" % [ammo_in_clip, total_ammo]

func _update_score_ui() -> void:
	if not local_player:
		return
	
	var peer_id = local_player.peer_id
	var stats = GameRulesManager.get_player_stats(peer_id)
	var score = stats.get("score", 0)
	score_label.text = "Score: " + str(score)

# --- Chat System ---

func _toggle_chat() -> void:
	if chat_input.visible:
		_hide_chat()
	else:
		_show_chat()

func _show_chat() -> void:
	chat_input.visible = true
	chat_input.grab_focus()
	
	# Pause local player input
	if local_player and local_player.pawn:
		local_player.pawn.set_process_input(false)

func _hide_chat() -> void:
	chat_input.visible = false
	chat_input.release_focus()
	chat_input.clear()
	
	# Resume local player input
	if local_player and local_player.pawn:
		local_player.pawn.set_process_input(true)

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		_hide_chat()
		return
	
	var player_name = local_player.player_name if local_player else "Player"
	send_chat_message.rpc(player_name, text.strip_edges())
	_hide_chat()

@rpc("any_peer", "call_local", "reliable")
func send_chat_message(sender_name: String, message: String) -> void:
	_add_chat_message(sender_name, message, Color.WHITE)

func _add_chat_message(sender: String, message: String, color: Color = Color.WHITE) -> void:
	var time_dict = Time.get_time_dict_from_system()
	var timestamp = "%02d:%02d" % [time_dict.hour, time_dict.minute]
	
	var formatted_message = "[color=#%s][%s] %s: %s[/color]" % [
		color.to_html(false),
		timestamp,
		sender,
		message
	]
	
	chat_display.append_text(formatted_message + "\n")

# --- Menu Systems ---

func _toggle_pause_menu() -> void:
	print("DEBUG: Toggling pause menu")
	if GameRulesManager:
		var should_show = not GameRulesManager.game_paused
		print("DEBUG: Calling GameRulesManager.show_pause_menu_ui(%s)" % should_show)
		GameRulesManager.show_pause_menu_ui(should_show)
	else:
		print("ERROR: GameRulesManager not found")

func _show_scoreboard(is_visible: bool) -> void:
	# Implement scoreboard overlay
	print("Scoreboard: ", is_visible)

func _show_end_game_screen(winner_info: Dictionary) -> void:
	print("End game screen - Winner: ", winner_info)
	# Could implement end game screen here
	# For now, return to lobby
	await get_tree().create_timer(2.0).timeout
	MultiplayerManager.return_to_lobby()

# --- Utility Functions ---

func get_player_by_peer_id(peer_id: int) -> NetworkedPlayer:
	return players.get(peer_id, null)

func get_local_player() -> NetworkedPlayer:
	return local_player

func is_match_active() -> bool:
	return match_started and game_active

# --- Process Updates ---

func _process(_delta: float) -> void:
	# Update score UI periodically
	if match_started and local_player:
		_update_score_ui()

# --- Admin/Debug Functions ---

func respawn_player(peer_id: int) -> void:
	if not MultiplayerManager.is_server():
		return
	
	var player = get_player_by_peer_id(peer_id)
	if player:
		player.force_respawn()

func teleport_player_to_spawn(peer_id: int) -> void:
	if not MultiplayerManager.is_server():
		return
	
	var player = get_player_by_peer_id(peer_id)
	if player:
		var spawn_pos = get_spawn_point_for_player(peer_id)
		player.global_position = spawn_pos
		if player.pawn:
			player.pawn.global_position = spawn_pos
