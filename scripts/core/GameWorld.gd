extends Node3D
class_name GameWorld

## Main game world controller for multiplayer matches
## Handles player spawning, game flow, and coordination between systems

# --- Player Management ---
var networked_player_scene: PackedScene = preload("res://scenes/mp_framework/NetworkedPlayer.tscn")
@export var map_config: MapConfig
var current_game_mode_definition: GameModeDefinition
var active_game_mode_logic: Node
var players: Dictionary = {}  # peer_id -> NetworkedPlayer instance
var spawn_points: Array[SpawnPoint] = []
var state_sync: GameWorldStateSync

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

func _requires_character_selection() -> bool:
	if current_game_mode_definition:
		return current_game_mode_definition.character_select_ui_scene != null
	return false

func _ready() -> void:
	# Hide chat input initially
	if chat_input:
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

	# Connect chat input (guard in case chat_input node is not present in this scene)
	if chat_input:
		chat_input.text_submitted.connect(_on_chat_submitted)

	# Collect spawn points
	_collect_spawn_points()

	# Setup Source Engine-style state replication
	# Create StateSync on all peers (needed for RPC path resolution)
	# But only server will initialize StateReplicationManager
	state_sync = GameWorldStateSync.new()
	state_sync.name = "StateSync"
	add_child(state_sync)

	# Check if we should delay spawning (e.g., for character selection in game modes)
	var should_delay_spawn: bool = false
	if map_config and map_config.game_mode_definition:
		# Ensure game mode logic is applied on both host and clients immediately
		if current_game_mode_definition != map_config.game_mode_definition:
			_apply_game_mode_definition(map_config.game_mode_definition)
		# Game mode will handle spawning after character selection
		should_delay_spawn = true

	if not should_delay_spawn:
		# Spawn players immediately (default behavior)
		_spawn_all_players()

	# Start the match
	if MultiplayerManager.is_server():
		await get_tree().create_timer(2.0).timeout  # Give time for all players to load
		_start_match_with_map_config()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				# Toggle chat
				_toggle_chat()
			KEY_ESCAPE:
				# Hide chat; toggle pause menu without pausing the game.
				if chat_input and chat_input.visible:
					_hide_chat()
				else:
					_toggle_pause_menu()
				# Prevent global/autoload pause handlers from also reacting.
				get_viewport().set_input_as_handled()
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

func get_spawn_point_node_for_player(peer_id: int) -> SpawnPoint:
	if spawn_points.is_empty():
		return null
	
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
	
	return best_spawn if best_spawn else available_spawns[0]

func get_spawn_point_for_player(peer_id: int) -> Vector3:
	var spawn_node = get_spawn_point_node_for_player(peer_id)
	if spawn_node:
		spawn_node.use_spawn_point()
		return spawn_node.global_position
	return Vector3(0, 2, 0)

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
	
	# Set spawn position and rotation
	var spawn_point = get_spawn_point_node_for_player(peer_id)
	var spawn_pos = Vector3(0, 2, 0)
	var spawn_yaw = 0.0
	
	if spawn_point:
		spawn_pos = spawn_point.use_spawn_point()
		spawn_yaw = spawn_point.get_spawn_rotation_y()
	
	# Wire in character selection if provided by the player info
	var chosen_character_path = ""
	if player_info and player_info.has("character_path"):
		chosen_character_path = player_info["character_path"]
	
	var requires_character = _requires_character_selection()
	if chosen_character_path == "" and requires_character:
		print("[GameWorld] Waiting for character selection before spawning peer ", peer_id)
		return
	
	if chosen_character_path != "":
		# Load the character scene and set it as the pawn_scene
		var character_scene = load(chosen_character_path) as PackedScene
		if character_scene:
			networked_player.pawn_scene = character_scene
			print("[GameWorld] Set pawn_scene to: ", chosen_character_path)
		else:
			push_warning("[GameWorld] Failed to load character scene: ", chosen_character_path)
	
	# Initialize player
	networked_player.initialize_player(peer_id, player_name, team_id)
	
	# Add to scene (guard against missing container in some scenes)
	if players_container:
		players_container.add_child(networked_player)
	else:
		# Fallback: attach to root if the container is absent (e.g., in simplified setups)
		get_tree().get_root().add_child(networked_player)
	players[peer_id] = networked_player

	# Apply spawn transform (position + view rotation)
	# We do this AFTER adding to tree so the pawn is initialized
	if networked_player.has_method("set_spawn_transform"):
		networked_player.set_spawn_transform(spawn_pos, spawn_yaw)
	else:
		networked_player.global_position = spawn_pos

	# Register with state replication (server only)
	if state_sync and MultiplayerManager.is_server():
		state_sync.register_player(networked_player)
	
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
# Guard UI cleanup to avoid null dereferences in scenes without these widgets
	if health_bar:
		health_bar.value = 0.0
	if health_label:
		health_label.text = "Health: 0"
	if ammo_label:
		ammo_label.text = "Ammo: 0/0"

func _on_player_disconnected(peer_id: int) -> void:
	if peer_id in players:
		var player = players[peer_id]

		# Unregister from state replication
		if state_sync and MultiplayerManager.is_server():
			state_sync.unregister_player(player)

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
	# Spawn the newly connected player
	_spawn_player(peer_id)
	
	# If we're the server, spawn all existing players for the new client
	if MultiplayerManager.is_server():
		if state_sync:
			call_deferred("_sync_late_joiner", peer_id)
		else:
			call_deferred("_spawn_existing_players_for_new_client", peer_id)

func _sync_late_joiner(peer_id: int) -> void:
	if not state_sync:
		return

	await get_tree().create_timer(0.5).timeout
	state_sync.sync_late_joiner(peer_id)

func _spawn_existing_players_for_new_client(new_peer_id: int) -> void:
	"""Server-side: Spawn all existing players for a late-joining client"""
	if not MultiplayerManager.is_server():
		return
	
	print("[GameWorld] Spawning existing players for new client: ", new_peer_id)
	
	# Wait a moment for the new client's scene to be ready
	await get_tree().create_timer(0.3).timeout
	
	# Spawn all existing players (including host) for the new client
	for existing_peer_id in players.keys():
		if existing_peer_id == new_peer_id:
			continue  # Don't spawn the new player for themselves
		
		var player_info = MultiplayerManager.get_player_info(existing_peer_id)
		if not player_info:
			continue
		
		# Check if this player has a character selected
		var character_path = player_info.get("character_path", "")
		if character_path != "":
			# Tell the new client to spawn this existing player with their character
			print("[GameWorld] Telling peer %d to spawn existing peer %d with character: %s" % [new_peer_id, existing_peer_id, character_path])
			_rpc_spawn_existing_player.rpc_id(new_peer_id, existing_peer_id, character_path)

@rpc("authority", "call_remote", "reliable")
func _rpc_spawn_existing_player(peer_id: int, character_path: String) -> void:
	"""Client-side: Spawn an existing player that was already in the game"""
	print("[GameWorld] Received RPC to spawn existing peer %d with character: %s" % [peer_id, character_path])
	
	# Update local player info cache
	if MultiplayerManager.connected_players.has(peer_id):
		MultiplayerManager.connected_players[peer_id]["character_path"] = character_path
	
	# Spawn the player
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
	if time_label:
		time_label.text = "%02d:%02d" % [minutes, seconds]

# --- UI Updates ---

func _on_local_player_health_changed(_old_health: float, new_health: float) -> void:
	_update_health_ui(new_health)

func _update_health_ui(health: float) -> void:
	if local_player:
		if health_bar:
			health_bar.value = health
		if health_label:
			health_label.text = "Health: " + str(int(health))

func _on_local_player_ammo_changed(ammo_in_clip: int, total_ammo: int) -> void:
	if ammo_label:
		ammo_label.text = "Ammo: %d/%d" % [ammo_in_clip, total_ammo]

func _update_score_ui() -> void:
	if not local_player:
		return
	
	var peer_id = local_player.peer_id
	var stats = GameRulesManager.get_player_stats(peer_id)
	var score = stats.get("score", 0)
	if score_label:
		score_label.text = "Score: " + str(score)

# --- Chat System ---

func _toggle_chat() -> void:
	if not chat_input:
		return
	if chat_input.visible:
		_hide_chat()
	else:
		_show_chat()

func _show_chat() -> void:
	if not chat_input:
		return
	chat_input.visible = true
	chat_input.grab_focus()
	
	# Pause local player input
	if local_player and local_player.pawn:
		local_player.pawn.set_process_input(false)

func _hide_chat() -> void:
	if not chat_input:
		return
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
	
	if chat_display:
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

func _show_scoreboard(show_scoreboard_arg: bool) -> void:
	# Implement scoreboard overlay
	print("Scoreboard: ", show_scoreboard_arg)

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
		var spawn_point = get_spawn_point_node_for_player(peer_id)
		if spawn_point:
			var spawn_pos = spawn_point.use_spawn_point()
			var spawn_yaw = spawn_point.get_spawn_rotation_y()
			
			if player.has_method("set_spawn_transform"):
				player.set_spawn_transform(spawn_pos, spawn_yaw)
			else:
				player.global_position = spawn_pos
				if player.pawn:
					player.pawn.global_position = spawn_pos


func _start_match_with_map_config() -> void:
	if not GameRulesManager:
		return
	
	var target_mode: int = GameRulesManager.GameMode.DEATHMATCH
	var time_limit_minutes: float = 5.0
	var score_limit: int = 25
	
	if map_config:
		if map_config.game_mode_definition:
			if current_game_mode_definition != map_config.game_mode_definition:
				_apply_game_mode_definition(map_config.game_mode_definition)
			target_mode = map_config.game_mode_definition.mode
			time_limit_minutes = map_config.game_mode_definition.default_time_limit_minutes
			score_limit = map_config.game_mode_definition.default_score_limit
		else:
			_clear_game_mode_logic()
			target_mode = map_config.game_mode
			time_limit_minutes = map_config.time_limit_minutes
			score_limit = map_config.score_limit
	else:
		_clear_game_mode_logic()
	
	GameRulesManager.start_match(
		target_mode,
		time_limit_minutes,
		score_limit
	)

func _apply_game_mode_definition(definition: GameModeDefinition) -> void:
	_clear_game_mode_logic()
	if not definition:
		return
	
	current_game_mode_definition = definition
	
	if definition.logic_scene:
		active_game_mode_logic = definition.logic_scene.instantiate()
		add_child(active_game_mode_logic)
		if active_game_mode_logic.has_method("initialize"):
			active_game_mode_logic.call("initialize", self, definition)

func _clear_game_mode_logic() -> void:
	current_game_mode_definition = null
	if active_game_mode_logic:
		active_game_mode_logic.queue_free()
		active_game_mode_logic = null
