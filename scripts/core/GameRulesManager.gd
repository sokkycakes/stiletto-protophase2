extends Node
# GameRulesManager - Autoload Singleton
# Note: No class_name needed for autoload singletons

## Manages game rules, modes, and match flow
## Handles scoring, win conditions, and game state

# --- Game Modes ---
enum GameMode {
	DEATHMATCH,      # Free-for-all
	TEAM_DEATHMATCH, # Team vs team
	COOPERATIVE,     # PvE mode
	DUEL             # 1v1 duel
}

# --- Game State ---
const PAUSE_MENU_SCENE := preload("res://scenes/mp_framework/ui/PauseMenu.tscn")
var current_mode: GameMode = GameMode.DEATHMATCH
var match_active: bool = false
var game_paused: bool = false
var match_paused: bool = false
var can_pause: bool = true
var pause_menu_instance: CanvasLayer

func show_pause_menu_ui(show: bool, notify_server: bool = false) -> void:
	var menu := _ensure_pause_menu()
	if not menu:
		return
	
	if game_paused == show:
		_apply_pause_menu_visibility(show)
		return
	
	game_paused = show
	_apply_pause_menu_visibility(show)
	pause_menu_visibility_changed.emit(show)
	
	if notify_server and multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			_set_match_paused(show)
		else:
			request_match_pause.rpc_id(1, show)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and match_active:
		show_pause_menu_ui(!game_paused)

@rpc("authority", "call_local", "reliable")
func sync_match_pause_state(show: bool) -> void:
	match_paused = show
	match_pause_state_changed.emit(show)

@rpc("any_peer", "call_remote", "reliable")
func request_match_pause(show: bool) -> void:
	if multiplayer.is_server():
		_set_match_paused(show)
var match_time_remaining: float = 300.0  # 5 minutes default
var score_limit: int = 25
var time_limit: float = 300.0

# --- Match Statistics ---
var match_start_time: float
var player_stats: Dictionary = {}  # peer_id -> stats

# --- Timers ---
var match_timer: Timer

# --- Signals ---
signal match_started()
signal match_ended(winner_info: Dictionary)
signal player_scored(peer_id: int, points: int)
signal match_time_updated(time_remaining: float)
signal pause_menu_visibility_changed(show: bool)
signal match_pause_state_changed(show: bool)
signal player_stats_updated(stats: Dictionary)

func _ready() -> void:
	# Create match timer
	match_timer = Timer.new()
	match_timer.one_shot = true
	match_timer.timeout.connect(_on_match_timeout)
	add_child(match_timer)
	
	# Connect to multiplayer events
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

func _process(delta: float) -> void:
	if match_active and match_timer.time_left > 0:
		match_time_remaining = match_timer.time_left
		match_time_updated.emit(match_time_remaining)

# --- Public API ---

## Start a new match with specified mode and settings
func start_match(mode: GameMode = GameMode.DEATHMATCH, time_limit_minutes: float = 5.0, score_limit_value: int = 25) -> void:
	if not MultiplayerManager.is_server():
		print("Only server can start matches")
		return
	
	current_mode = mode
	time_limit = time_limit_minutes * 60.0
	score_limit = score_limit_value
	match_time_remaining = time_limit
	
	# Reset all player stats
	_reset_player_stats()
	
	# Start match timer
	match_timer.start(time_limit)
	match_active = true
	match_start_time = Time.get_unix_time_from_system()
	
	print("Match started: ", GameMode.keys()[mode])
	start_match_for_all.rpc(mode, time_limit, score_limit)

## End the current match
func end_match() -> void:
	if not MultiplayerManager.is_server():
		return
	
	# Prevent multiple calls to end_match
	if not match_active:
		print("[GameRulesManager] end_match() called but match is already inactive")
		return
	
	match_active = false
	if match_timer:
		match_timer.stop()
	
	# Safety check - ensure MultiplayerManager is still valid
	if not MultiplayerManager or not is_instance_valid(MultiplayerManager):
		push_warning("[GameRulesManager] MultiplayerManager is not valid, cannot end match")
		return
	
	var winner_info = _calculate_winner()
	print("Match ended. Winner: ", winner_info)
	
	# Check if we're still in the tree before sending RPC
	if not is_inside_tree() or not is_instance_valid(self):
		push_warning("[GameRulesManager] Node is not valid, cannot send end_match RPC")
		return
	
	end_match_for_all.rpc(winner_info)

## Handle player death/kill events
func on_player_killed(killer_id: int, victim_id: int) -> void:
	if not MultiplayerManager.is_server():
		return
	
	# Initialize stats for killer if not present
	if killer_id >= 0 and killer_id not in player_stats:
		_initialize_player_stats(killer_id)
	
	# Update killer stats (only if valid killer, not suicide/world kill)
	if killer_id >= 0 and killer_id in player_stats:
		player_stats[killer_id]["kills"] += 1
		player_stats[killer_id]["score"] += _get_kill_points()
		
		# Update player info in MultiplayerManager
		var new_score = player_stats[killer_id]["score"]
		MultiplayerManager.update_player_score(killer_id, new_score)
		
		player_scored.emit(killer_id, _get_kill_points())
		
		# Check win condition
		if player_stats[killer_id]["score"] >= score_limit:
			end_match()
	
	# Update victim stats
	if victim_id in player_stats:
		player_stats[victim_id]["deaths"] += 1
	elif victim_id >= 0:
		# Initialize stats for victim if not present
		_initialize_player_stats(victim_id)
		player_stats[victim_id]["deaths"] += 1
	
	# Sync stats to all clients
	sync_player_stats.rpc(player_stats)

## Get current game mode
func get_current_mode() -> GameMode:
	return current_mode

## Get match statistics
func get_match_stats() -> Dictionary:
	return {
		"active": match_active,
		"mode": current_mode,
		"time_remaining": match_time_remaining,
		"score_limit": score_limit,
		"player_stats": player_stats
	}

## Get player statistics
func get_player_stats(peer_id: int) -> Dictionary:
	return player_stats.get(peer_id, {})

# --- RPC Methods ---

@rpc("authority", "call_local", "reliable")
func start_match_for_all(mode: GameMode, time_limit_seconds: float, score_limit_value: int) -> void:
	current_mode = mode
	time_limit = time_limit_seconds
	score_limit = score_limit_value
	match_time_remaining = time_limit
	match_active = true
	
	if match_timer:
		match_timer.start(time_limit)
	
	match_started.emit()

@rpc("authority", "call_local", "reliable")
func end_match_for_all(winner_info: Dictionary) -> void:
	# Safety check - ensure node is still valid
	if not is_inside_tree() or not is_instance_valid(self):
		push_warning("[GameRulesManager] Node is not valid, cannot process end_match_for_all")
		return
	
	match_active = false
	if match_timer:
		match_timer.stop()
	
	# Validate winner_info before emitting
	if not winner_info or not winner_info is Dictionary:
		push_warning("[GameRulesManager] Invalid winner_info, using default")
		winner_info = {
			"type": "none",
			"peer_id": -1,
			"team_id": -1,
			"name": "No Winner",
			"score": 0
		}
	
	match_ended.emit(winner_info)

@rpc("authority", "call_local", "reliable")
func sync_player_stats(stats: Dictionary) -> void:
	player_stats = stats
	player_stats_updated.emit(player_stats)

# --- Internal Methods ---

func _reset_player_stats() -> void:
	player_stats.clear()
	
	# Initialize stats for all connected players
	for peer_id in MultiplayerManager.get_connected_players():
		_initialize_player_stats(peer_id)

func _initialize_player_stats(peer_id: int) -> void:
	player_stats[peer_id] = {
		"kills": 0,
		"deaths": 0,
		"score": 0,
		"join_time": Time.get_unix_time_from_system()
	}

func _get_kill_points() -> int:
	match current_mode:
		GameMode.DEATHMATCH, GameMode.TEAM_DEATHMATCH, GameMode.DUEL:
			return 1
		GameMode.COOPERATIVE:
			return 1
		_:
			return 1

func _calculate_winner() -> Dictionary:
	var winner_info = {
		"type": "none",
		"peer_id": -1,
		"team_id": -1,
		"name": "No Winner",
		"score": 0
	}
	
	# Safety check - ensure MultiplayerManager is valid
	if not MultiplayerManager or not is_instance_valid(MultiplayerManager):
		push_warning("[GameRulesManager] MultiplayerManager is not valid, cannot calculate winner")
		return winner_info
	
	match current_mode:
		GameMode.DEATHMATCH, GameMode.DUEL:
			# Find player with highest score
			var highest_score = -1
			var winner_peer_id = -1
			
			for peer_id in player_stats:
				if peer_id in player_stats and "score" in player_stats[peer_id]:
					var score = player_stats[peer_id]["score"]
					if score > highest_score:
						highest_score = score
						winner_peer_id = peer_id
			
			if winner_peer_id != -1:
				var player_info = MultiplayerManager.get_player_info(winner_peer_id)
				# Safety check - ensure player_info is valid
				if player_info and player_info is Dictionary:
					winner_info = {
						"type": "player",
						"peer_id": winner_peer_id,
						"team_id": -1,
						"name": player_info.get("name", "Player"),
						"score": highest_score
					}
				else:
					# Fallback if player_info is invalid
					winner_info = {
						"type": "player",
						"peer_id": winner_peer_id,
						"team_id": -1,
						"name": "Player " + str(winner_peer_id),
						"score": highest_score
					}
		
		GameMode.TEAM_DEATHMATCH:
			# Calculate team scores and find winning team
			var team_scores = {}
			
			for peer_id in player_stats:
				var player_info = MultiplayerManager.get_player_info(peer_id)
				var team_id = player_info.get("team", 0)
				
				if not team_id in team_scores:
					team_scores[team_id] = 0
				team_scores[team_id] += player_stats[peer_id]["score"]
			
			# Find winning team
			var highest_team_score = -1
			var winning_team = -1
			
			for team_id in team_scores:
				if team_scores[team_id] > highest_team_score:
					highest_team_score = team_scores[team_id]
					winning_team = team_id
			
			if winning_team != -1:
				winner_info = {
					"type": "team",
					"peer_id": -1,
					"team_id": winning_team,
					"name": "Team " + str(winning_team),
					"score": highest_team_score
				}
	
	return winner_info

# --- Signal Handlers ---

func _on_match_timeout() -> void:
	print("Match time expired")
	end_match()

func _on_player_connected(peer_id: int, player_info: Dictionary) -> void:
	# Initialize stats for new player
	_initialize_player_stats(peer_id)
	
	# If match is active, sync current state to new player
	if match_active:
		sync_player_stats.rpc_id(peer_id, player_stats)

func _on_player_disconnected(peer_id: int) -> void:
	# Keep stats for potential reconnection
	# Could add logic here to handle mid-match disconnections
	pass

func remove_player_from_match(peer_id: int) -> void:
	if peer_id in player_stats:
		player_stats.erase(peer_id)
		if MultiplayerManager and MultiplayerManager.is_server():
			sync_player_stats.rpc(player_stats)

# --- Utility Methods ---

## Check if match is currently active
func is_match_active() -> bool:
	return match_active

## Get formatted time remaining string
func get_time_remaining_formatted() -> String:
	var minutes = int(match_time_remaining) / 60
	var seconds = int(match_time_remaining) % 60
	return "%02d:%02d" % [minutes, seconds]

## Get current leaderboard (sorted by score)
func get_leaderboard() -> Array:
	var leaderboard = []
	
	for peer_id in player_stats:
		var player_info = MultiplayerManager.get_player_info(peer_id)
		var stats = player_stats[peer_id]
		
		leaderboard.append({
			"peer_id": peer_id,
			"name": player_info.get("name", "Player"),
			"team": player_info.get("team", 0),
			"score": stats["score"],
			"kills": stats["kills"],
			"deaths": stats["deaths"],
			"kd_ratio": stats["kills"] / float(max(stats["deaths"], 1))
		})
	
	# Sort by score (descending)
	leaderboard.sort_custom(func(a, b): return a["score"] > b["score"])
	
	return leaderboard

# --- Pause Menu Button Handlers ---

func _ensure_pause_menu() -> CanvasLayer:
	if pause_menu_instance and is_instance_valid(pause_menu_instance):
		return pause_menu_instance
	
	var existing = get_node_or_null("/root/PauseMenu")
	if existing:
		pause_menu_instance = existing
		pause_menu_instance.layer = 128
		pause_menu_instance.set_process_input(true)
		_connect_pause_menu_buttons()
		return pause_menu_instance
	
	pause_menu_instance = PAUSE_MENU_SCENE.instantiate()
	pause_menu_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu_instance.layer = 128
	pause_menu_instance.set_process_input(true)
	get_tree().root.add_child(pause_menu_instance)
	pause_menu_instance.hide()
	_connect_pause_menu_buttons()
	return pause_menu_instance

func _apply_pause_menu_visibility(show: bool) -> void:
	if not pause_menu_instance or not is_instance_valid(pause_menu_instance):
		return
	
	if pause_menu_instance.has_method("show_menu") and pause_menu_instance.has_method("hide_menu"):
		if show:
			pause_menu_instance.call("show_menu")
		else:
			pause_menu_instance.call("hide_menu")
	else:
		if show:
			pause_menu_instance.show()
		else:
			pause_menu_instance.hide()
	
	# Check if character select is active - if so, force mouse to visible when hiding
	if not show and _has_character_select():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# Only manage mouse mode if we're in a game scene
	# Let UI scenes (lobby, character select) manage their own mouse mode
	elif _is_game_scene():
		if show:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Otherwise, don't touch mouse mode - let the scene handle it

func _is_game_scene() -> bool:
	var current_scene := get_tree().current_scene
	if not current_scene:
		return false
	
	var scene_path := current_scene.scene_file_path
	# Game scenes are not UI scenes, lobby, or character select
	return not scene_path.begins_with("res://scenes/ui/") and \
		   not "lobby" in scene_path.to_lower() and \
		   not _has_character_select()

func _has_character_select() -> bool:
	# Check if current scene has character select UI
	var current_scene := get_tree().current_scene
	if not current_scene:
		return false
	
	# Check for CharacterSelect node by name
	if current_scene.get_node_or_null("CharacterSelect"):
		return true
	
	# Check for nodes in character_select group
	if not get_tree().get_nodes_in_group("character_select").is_empty():
		return true
	
	# Search recursively for CharacterSelect class instances
	var character_select_nodes = _find_nodes_by_class(current_scene)
	if not character_select_nodes.is_empty():
		return true
	
	return false

func _find_nodes_by_class(node: Node) -> Array:
	var result: Array = []
	# Check if node is of the CharacterSelect class
	if node is CharacterSelect:
		result.append(node)
	
	# Recursively check children
	for child in node.get_children():
		result.append_array(_find_nodes_by_class(child))
	
	return result

func _set_match_paused(show: bool) -> void:
	sync_match_pause_state.rpc(show)

func _connect_pause_menu_buttons() -> void:
	if not pause_menu_instance or not is_instance_valid(pause_menu_instance):
		return
	var resume_button: Button = pause_menu_instance.get_node_or_null("Panel/VBoxContainer/ResumeButton")
	var return_button: Button = pause_menu_instance.get_node_or_null("Panel/VBoxContainer/ReturnButton")
	var disconnect_button: Button = pause_menu_instance.get_node_or_null("Panel/VBoxContainer/DisconnectButton")
	if resume_button and not resume_button.pressed.is_connected(_on_pause_resume_button):
		resume_button.pressed.connect(_on_pause_resume_button)
	if return_button and not return_button.pressed.is_connected(_on_pause_return_button):
		return_button.pressed.connect(_on_pause_return_button)
	if disconnect_button and not disconnect_button.pressed.is_connected(_on_pause_disconnect_button):
		disconnect_button.pressed.connect(_on_pause_disconnect_button)

func _on_pause_resume_button() -> void:
	print("DEBUG: Resume clicked (GameRulesManager)")
	show_pause_menu_ui(false)

func _on_pause_return_button() -> void:
	print("DEBUG: Return to lobby clicked (GameRulesManager)")
	show_pause_menu_ui(false)
	if MultiplayerManager:
		if MultiplayerManager.is_hosting:
			MultiplayerManager.return_to_lobby()
		else:
			MultiplayerManager.return_to_lobby_local()

func _on_pause_disconnect_button() -> void:
	print("DEBUG: Disconnect clicked (GameRulesManager)")
	show_pause_menu_ui(false)
	await get_tree().create_timer(0.05).timeout
	if MultiplayerManager:
		MultiplayerManager.disconnect_from_game()

func request_return_to_lobby() -> void:
	_on_pause_return_button()

func request_disconnect_from_match() -> void:
	_on_pause_disconnect_button()

func apply_match_snapshot(snapshot: Dictionary) -> void:
	if not snapshot:
		return
	
	current_mode = snapshot.get("mode", current_mode)
	score_limit = snapshot.get("score_limit", score_limit)
	time_limit = snapshot.get("time_limit", time_limit)
	match_time_remaining = snapshot.get("time_remaining", time_limit)
	match_active = snapshot.get("active", false)
	match_paused = false
	game_paused = false
	player_stats = snapshot.get("player_stats", player_stats)
	
	if match_timer:
		match_timer.stop()
		if match_active and match_time_remaining > 0.0:
			match_timer.start(match_time_remaining)
	var now = Time.get_unix_time_from_system()
	if time_limit > 0.0:
		match_start_time = now - (time_limit - match_time_remaining)
	else:
		match_start_time = now
	
	if match_active:
		match_started.emit()
		match_time_updated.emit(match_time_remaining)
	
	_apply_pause_menu_visibility(false)
	pause_menu_visibility_changed.emit(false)
