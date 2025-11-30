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

# --- Spawn Point Assignments (for Duel mode) ---
var player_spawn_assignments: Dictionary = {}  # peer_id -> SpawnPoint
var spawn_assignments_initialized: bool = false

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
	# Add to group for easy lookup
	add_to_group("game_world")
	
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
	
	# Initialize spawn point assignments for Duel mode
	if _is_duel_mode():
		_initialize_spawn_assignments()

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

func _is_duel_mode() -> bool:
	if GameRulesManager:
		return GameRulesManager.current_mode == GameRulesManager.GameMode.DUEL
	if map_config:
		return map_config.game_mode == 3  # Duel mode enum value
	return false

func _initialize_spawn_assignments() -> void:
	if spawn_assignments_initialized:
		return
	
	if spawn_points.is_empty():
		print("[GameWorld] No spawn points available for assignment")
		return
	
	# Only initialize on server
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	# Get all connected peer IDs
	var connected_peers = MultiplayerManager.get_connected_players()
	var peer_ids: Array[int] = []
	for peer_id in connected_peers:
		peer_ids.append(peer_id)
	
	# Sort for consistency
	peer_ids.sort()
	
	# Shuffle spawn points for random assignment
	var available_spawns = spawn_points.duplicate()
	available_spawns.shuffle()
	
	# Assign spawn points to players
	for i in range(peer_ids.size()):
		var peer_id = peer_ids[i]
		var spawn_index = i % available_spawns.size()
		var assigned_spawn = available_spawns[spawn_index]
		player_spawn_assignments[peer_id] = assigned_spawn
		print("[GameWorld] Assigned spawn point to peer %d: %s" % [peer_id, assigned_spawn.name])
	
	spawn_assignments_initialized = true
	
	# Sync assignments to clients
	if MultiplayerManager.is_server():
		_sync_spawn_assignments_to_clients()

func _sync_spawn_assignments_to_clients() -> void:
	# Convert SpawnPoint references to names for RPC
	var assignments_data: Dictionary = {}
	for peer_id in player_spawn_assignments:
		var spawn: SpawnPoint = player_spawn_assignments[peer_id]
		# Store by spawn point name - clients will look it up
		assignments_data[peer_id] = spawn.name
	
	_set_spawn_assignments.rpc(assignments_data)

@rpc("authority", "call_local", "reliable")
func _set_spawn_assignments(assignments_data: Dictionary) -> void:
	# Reconstruct spawn point assignments from names
	player_spawn_assignments.clear()
	for peer_id in assignments_data:
		var spawn_name: String = assignments_data[peer_id]
		# Find spawn point by name
		var spawn: SpawnPoint = null
		for sp in spawn_points:
			if sp.name == spawn_name:
				spawn = sp
				break
		
		if spawn:
			player_spawn_assignments[peer_id] = spawn
			print("[GameWorld] Received spawn assignment for peer %d: %s" % [peer_id, spawn.name])
		else:
			push_warning("[GameWorld] Failed to find spawn point with name: %s" % spawn_name)
	
	spawn_assignments_initialized = true

func _assign_spawn_point_to_late_joiner(peer_id: int) -> void:
	## Assign a spawn point to a late-joining player in Duel mode
	## Ensures they get a unique spawn point that isn't already assigned
	if not _is_duel_mode() or not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	if spawn_points.is_empty():
		print("[GameWorld] No spawn points available for late joiner: ", peer_id)
		return
	
	# If late joiner already has an assignment (shouldn't happen, but handle it)
	if peer_id in player_spawn_assignments:
		var existing_spawn = player_spawn_assignments[peer_id]
		# Check if another active player is using this spawn
		var spawn_in_use = false
		for assigned_peer_id in player_spawn_assignments:
			if assigned_peer_id != peer_id and assigned_peer_id in MultiplayerManager.get_connected_players() and assigned_peer_id in players:
				if player_spawn_assignments[assigned_peer_id] == existing_spawn:
					spawn_in_use = true
					break
		# If spawn is not in use, keep the existing assignment
		if not spawn_in_use:
			print("[GameWorld] Late joiner peer %d already has valid spawn assignment: %s" % [peer_id, existing_spawn.name])
			_sync_single_spawn_assignment(peer_id, existing_spawn)
			return
	
	# Find spawn points that are not already assigned to active players
	var assigned_spawns: Array[SpawnPoint] = []
	for assigned_peer_id in player_spawn_assignments:
		# Only count spawns assigned to players that are still connected AND spawned
		if assigned_peer_id != peer_id and assigned_peer_id in MultiplayerManager.get_connected_players() and assigned_peer_id in players:
			var assigned_spawn = player_spawn_assignments[assigned_peer_id]
			if assigned_spawn:
				assigned_spawns.append(assigned_spawn)
	
	# Find unassigned spawn points
	var unassigned_spawns: Array[SpawnPoint] = []
	for spawn in spawn_points:
		if spawn not in assigned_spawns:
			unassigned_spawns.append(spawn)
	
	# Prefer unassigned spawns, but if all are assigned, use the least recently used one
	var spawn_to_assign: SpawnPoint = null
	if unassigned_spawns.size() > 0:
		# Pick a random unassigned spawn
		spawn_to_assign = unassigned_spawns[randi() % unassigned_spawns.size()]
	else:
		# All spawns are assigned - find the least recently used one
		var least_recently_used: SpawnPoint = spawn_points[0]
		var oldest_time: float = least_recently_used.last_used_time
		for spawn in spawn_points:
			if spawn.last_used_time < oldest_time:
				oldest_time = spawn.last_used_time
				least_recently_used = spawn
		spawn_to_assign = least_recently_used
		print("[GameWorld] All spawns assigned, using least recently used for late joiner: ", spawn_to_assign.name)
	
	# Assign the spawn point to the late joiner
	player_spawn_assignments[peer_id] = spawn_to_assign
	print("[GameWorld] Assigned spawn point to late joiner peer %d: %s" % [peer_id, spawn_to_assign.name])
	
	# Sync this assignment to all clients
	_sync_single_spawn_assignment(peer_id, spawn_to_assign)

func _sync_single_spawn_assignment(peer_id: int, spawn: SpawnPoint) -> void:
	## Sync a single spawn assignment to all clients
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	_set_single_spawn_assignment.rpc(peer_id, spawn.name)

@rpc("authority", "call_local", "reliable")
func _set_single_spawn_assignment(peer_id: int, spawn_name: String) -> void:
	## Client-side: Receive a single spawn assignment update
	var spawn: SpawnPoint = null
	for sp in spawn_points:
		if sp.name == spawn_name:
			spawn = sp
			break
	
	if spawn:
		player_spawn_assignments[peer_id] = spawn
		print("[GameWorld] Received spawn assignment update for peer %d: %s" % [peer_id, spawn_name])
	else:
		push_warning("[GameWorld] Failed to find spawn point with name: %s for late joiner" % spawn_name)

func get_spawn_point_node_for_player(peer_id: int) -> SpawnPoint:
	if spawn_points.is_empty():
		return null
	
	# For Duel mode, use assigned spawn points
	if _is_duel_mode() and spawn_assignments_initialized:
		if peer_id in player_spawn_assignments:
			return player_spawn_assignments[peer_id]
		# Fallback if assignment not found
		print("[GameWorld] Warning: No spawn assignment for peer %d in Duel mode, using fallback" % peer_id)
	
	# Default behavior: team-based or least recently used
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

func get_assigned_spawn_point_for_player(peer_id: int) -> SpawnPoint:
	## Get the assigned spawn point for a player (used in Duel mode)
	if _is_duel_mode() and peer_id in player_spawn_assignments:
		return player_spawn_assignments[peer_id]
	return null

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
		if not is_inside_tree() or not get_tree():
			push_warning("[GameWorld] Cannot spawn player %d: GameWorld not in scene tree" % peer_id)
			return
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
		
		# Clear spawn assignment for disconnected player (for Duel mode)
		if _is_duel_mode() and peer_id in player_spawn_assignments:
			player_spawn_assignments.erase(peer_id)
			print("[GameWorld] Cleared spawn assignment for disconnected player: ", peer_id)
		
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
	# Ensure we're in the tree before spawning
	if not is_inside_tree():
		call_deferred("_on_player_connected_to_game", peer_id, _player_info)
		return
	
	# For Duel mode, assign spawn point to newly connected player
	if _is_duel_mode() and MultiplayerManager.is_server():
		if not spawn_assignments_initialized:
			_initialize_spawn_assignments()
		else:
			# Late joiner: assign them an available spawn point
			_assign_spawn_point_to_late_joiner(peer_id)
	
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
	
	# Check if we're still in the tree (scene might be unloading)
	if not is_inside_tree():
		return
	
	print("[GameWorld] Spawning existing players for new client: ", new_peer_id)
	
	# Wait a moment for the new client's scene to be ready
	await get_tree().create_timer(0.3).timeout
	
	# Check again after await (scene might have unloaded during wait)
	if not is_inside_tree():
		return
	
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

## Clean up all players and game world resources
## Call this before changing scenes to ensure proper cleanup
func cleanup_all_players() -> void:
	print("[GameWorld] Cleaning up all players before returning to lobby")
	
	# Release mouse capture immediately
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Disable processing on this node to prevent any further updates
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	
	# Clean up local player UI first
	if local_player:
		_cleanup_local_player_ui()
		# Disable input on local player before cleanup
		if is_instance_valid(local_player):
			local_player._disable_pawn_input()
			# Also disable processing on the pawn itself
			if local_player.pawn:
				local_player.pawn.set_process(false)
				local_player.pawn.set_physics_process(false)
				local_player.pawn.set_process_input(false)
				local_player.pawn.set_process_unhandled_input(false)
		local_player = null
	
	# Clean up all player instances - disable input first, then free
	var player_ids = players.keys()
	for peer_id in player_ids:
		if peer_id in players:
			var player = players[peer_id]
			if is_instance_valid(player):
				# Disable all input processing first
				player._disable_pawn_input()
				
				# Disable processing on pawn
				if player.pawn:
					player.pawn.set_process(false)
					player.pawn.set_physics_process(false)
					player.pawn.set_process_input(false)
					player.pawn.set_process_unhandled_input(false)
				
				# Unregister from state replication if server
				if state_sync and MultiplayerManager.is_server():
					state_sync.unregister_player(player)
				
				# Free immediately to prevent any further processing
				player.free()
			players.erase(peer_id)
	
	players.clear()
	print("[GameWorld] All players cleaned up")
	
	# Clean up state sync
	if state_sync:
		if state_sync.state_replication_manager:
			if state_sync.state_replication_manager.has_method("reset_state"):
				state_sync.state_replication_manager.reset_state()
		state_sync = null
	
	# Reset game state
	game_active = false
	match_started = false
