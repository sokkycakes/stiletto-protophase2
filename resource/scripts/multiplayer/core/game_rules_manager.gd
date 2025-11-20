extends Node

enum GameMode {
	DEATHMATCH,
	TEAM_DEATHMATCH,
	COOPERATIVE,
}

const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menuv2.tscn")

var current_mode: GameMode = GameMode.DEATHMATCH
var match_active: bool = false
var game_paused: bool = false
var match_paused: bool = false
var can_pause: bool = true
var pause_menu_instance: CanvasLayer

var match_time_remaining: float = 300.0
var score_limit: int = 25
var time_limit: float = 300.0
var match_start_time: float = 0.0
var player_stats: Dictionary = {}

var match_timer: Timer

signal match_started()
signal match_ended(winner_info: Dictionary)
signal player_scored(peer_id: int, points: int)
signal match_time_updated(time_remaining: float)
signal pause_menu_visibility_changed(show: bool)
signal match_pause_state_changed(show: bool)

func _ready() -> void:
	match_timer = Timer.new()
	match_timer.one_shot = true
	match_timer.timeout.connect(_on_match_timeout)
	add_child(match_timer)
	
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)


func _process(_delta: float) -> void:
	if match_active and match_timer.time_left > 0.0:
		match_time_remaining = match_timer.time_left
		match_time_updated.emit(match_time_remaining)


func show_pause_menu_ui(show: bool, notify_server: bool = false) -> void:
	var menu: CanvasLayer = _ensure_pause_menu()
	if not menu:
		return
	
	if game_paused == show:
		_apply_pause_menu_visibility(show)
		return
	
	game_paused = show
	_apply_pause_menu_visibility(show)
	pause_menu_visibility_changed.emit(show)
	
	if notify_server and MultiplayerManager and MultiplayerManager.is_server():
		_set_match_paused(show)
	elif notify_server and MultiplayerManager:
		request_match_pause.rpc_id(1, show)


func _input(event: InputEvent) -> void:
	if not can_pause:
		return
	if event.is_action_pressed("pause") and match_active:
		show_pause_menu_ui(!game_paused, true)


func start_match(mode: GameMode = GameMode.DEATHMATCH, time_limit_minutes: float = 5.0, score_limit_value: int = 25) -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	current_mode = mode
	time_limit = time_limit_minutes * 60.0
	score_limit = score_limit_value
	match_time_remaining = time_limit
	match_active = true
	match_start_time = Time.get_unix_time_from_system()
	
	_reset_player_stats()
	match_timer.start(time_limit)
	start_match_for_all.rpc(mode, time_limit, score_limit)


func end_match() -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	match_active = false
	match_timer.stop()
	var winner_info: Dictionary = _calculate_winner()
	end_match_for_all.rpc(winner_info)


func on_player_killed(killer_id: int, victim_id: int) -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	if killer_id in player_stats:
		player_stats[killer_id]["kills"] += 1
		player_stats[killer_id]["score"] += _get_kill_points()
		MultiplayerManager.update_player_score(killer_id, player_stats[killer_id]["score"])
		player_scored.emit(killer_id, _get_kill_points())
		if player_stats[killer_id]["score"] >= score_limit:
			end_match()
	
	if victim_id in player_stats:
		player_stats[victim_id]["deaths"] += 1
	
	sync_player_stats.rpc(player_stats)


func get_current_mode() -> GameMode:
	return current_mode


func get_match_stats() -> Dictionary:
	return {
		"active": match_active,
		"mode": current_mode,
		"time_remaining": match_time_remaining,
		"score_limit": score_limit,
		"player_stats": player_stats,
	}


func get_player_stats(peer_id: int) -> Dictionary:
	return player_stats.get(peer_id, {})


func is_match_active() -> bool:
	return match_active


func get_time_remaining_formatted() -> String:
	var minutes: int = int(match_time_remaining) / 60
	var seconds: int = int(match_time_remaining) % 60
	return "%02d:%02d" % [minutes, seconds]


func get_leaderboard() -> Array:
	var leaderboard: Array = []
	for peer_id in player_stats.keys():
		var info: Dictionary = MultiplayerManager.get_player_info(peer_id)
		var stats: Dictionary = player_stats[peer_id]
		leaderboard.append({
			"peer_id": peer_id,
			"name": info.get("name", "Player"),
			"team": info.get("team", 0),
			"score": stats.get("score", 0),
			"kills": stats.get("kills", 0),
			"deaths": stats.get("deaths", 0),
		})
	leaderboard.sort_custom(func(a, b): return a["score"] > b["score"])
	return leaderboard


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
	match_active = false
	if match_timer:
		match_timer.stop()
	match_ended.emit(winner_info)


@rpc("authority", "call_local", "reliable")
func sync_player_stats(stats: Dictionary) -> void:
	player_stats = stats


@rpc("authority", "call_local", "reliable")
func sync_match_pause_state(show: bool) -> void:
	match_paused = show
	match_pause_state_changed.emit(show)


@rpc("any_peer", "call_remote", "reliable")
func request_match_pause(show: bool) -> void:
	if MultiplayerManager and MultiplayerManager.is_server():
		_set_match_paused(show)


func remove_player_from_match(peer_id: int) -> void:
	if peer_id in player_stats:
		player_stats.erase(peer_id)
		if MultiplayerManager and MultiplayerManager.is_server():
			sync_player_stats.rpc(player_stats)


func _reset_player_stats() -> void:
	player_stats.clear()
	if not MultiplayerManager:
		return
	for peer_id in MultiplayerManager.get_connected_peer_ids():
		_initialize_player_stats(peer_id)


func _initialize_player_stats(peer_id: int) -> void:
	player_stats[peer_id] = {
		"kills": 0,
		"deaths": 0,
		"score": 0,
		"join_time": Time.get_unix_time_from_system(),
	}


func _get_kill_points() -> int:
	match current_mode:
		GameMode.DEATHMATCH, GameMode.TEAM_DEATHMATCH:
			return 1
		GameMode.COOPERATIVE:
			return 1
		_:
			return 1


func _calculate_winner() -> Dictionary:
	var winner_info: Dictionary = {
		"type": "none",
		"peer_id": -1,
		"team_id": -1,
		"name": "No Winner",
		"score": 0,
	}
	match current_mode:
		GameMode.DEATHMATCH:
			var highest_score: int = -1
			var winner_peer_id: int = -1
			for peer_id in player_stats.keys():
				var score: int = int(player_stats[peer_id].get("score", 0))
				if score > highest_score:
					highest_score = score
					winner_peer_id = peer_id
			if winner_peer_id != -1:
				var info: Dictionary = MultiplayerManager.get_player_info(winner_peer_id)
				winner_info = {
					"type": "player",
					"peer_id": winner_peer_id,
					"team_id": -1,
					"name": info.get("name", "Player"),
					"score": highest_score,
				}
		GameMode.TEAM_DEATHMATCH:
			var team_scores: Dictionary = {}
			for peer_id in player_stats.keys():
				var info: Dictionary = MultiplayerManager.get_player_info(peer_id)
				var team_id: int = int(info.get("team", 0))
				if not team_id in team_scores:
					team_scores[team_id] = 0
				team_scores[team_id] += player_stats[peer_id].get("score", 0)
			var highest_team_score: int = -1
			var winning_team: int = -1
			for team_id in team_scores.keys():
				var score: int = int(team_scores[team_id])
				if score > highest_team_score:
					highest_team_score = score
					winning_team = team_id
			if winning_team != -1:
				winner_info = {
					"type": "team",
					"peer_id": -1,
					"team_id": winning_team,
					"name": "Team %d" % winning_team,
					"score": highest_team_score,
				}
	return winner_info


func _on_match_timeout() -> void:
	end_match()


func _on_player_connected(peer_id: int) -> void:
	_initialize_player_stats(peer_id)
	if match_active:
		sync_player_stats.rpc_id(peer_id, player_stats)


func _on_player_disconnected(peer_id: int) -> void:
	if MultiplayerManager and MultiplayerManager.is_server():
		remove_player_from_match(peer_id)


func _ensure_pause_menu() -> CanvasLayer:
	if pause_menu_instance and is_instance_valid(pause_menu_instance):
		return pause_menu_instance
	var existing: CanvasLayer = get_node_or_null("/root/PauseMenu")
	if existing:
		pause_menu_instance = existing
		_connect_pause_menu_buttons()
		return pause_menu_instance
	pause_menu_instance = PAUSE_MENU_SCENE.instantiate()
	pause_menu_instance.name = "PauseMenu"
	pause_menu_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(pause_menu_instance)
	pause_menu_instance.hide()
	_connect_pause_menu_buttons()
	return pause_menu_instance


func _apply_pause_menu_visibility(show: bool) -> void:
	if not pause_menu_instance or not is_instance_valid(pause_menu_instance):
		return
	if show:
		if pause_menu_instance.has_method("show_menu"):
			pause_menu_instance.call("show_menu")
		else:
			pause_menu_instance.show()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		if pause_menu_instance.has_method("hide_menu"):
			pause_menu_instance.call("hide_menu")
		else:
			pause_menu_instance.hide()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _set_match_paused(show: bool) -> void:
	sync_match_pause_state.rpc(show)


func _connect_pause_menu_buttons() -> void:
	if not pause_menu_instance or not is_instance_valid(pause_menu_instance):
		return
	var resume_button: Button = pause_menu_instance.get_node_or_null("Panel/VBoxContainer/ResumeButton")
	var return_button: Button = pause_menu_instance.get_node_or_null("Panel/VBoxContainer/ReturnButton")
	var disconnect_button: Button = pause_menu_instance.get_node_or_null("Panel/VBoxContainer/DisconnectButton")
	if resume_button:
		resume_button.pressed.connect(_on_resume_pressed)
	if return_button:
		return_button.pressed.connect(_on_return_to_lobby_pressed.bind())
	if disconnect_button:
		disconnect_button.pressed.connect(_on_disconnect_pressed.bind())


func _on_resume_pressed() -> void:
	show_pause_menu_ui(false, true)


func _on_return_to_lobby_pressed() -> void:
	show_pause_menu_ui(false)
	MultiplayerManager.return_to_lobby()


func _on_disconnect_pressed() -> void:
	show_pause_menu_ui(false)
	MultiplayerManager.disconnect_from_game()
