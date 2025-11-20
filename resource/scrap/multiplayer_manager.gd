extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal lobby_ready()
signal game_started()
signal match_state_changed(active: bool)
signal session_id_changed(session_id: String)
signal join_code_generated(code: String)

enum GameState { LOBBY, STARTING, IN_GAME }

var current_game_state: GameState = GameState.LOBBY
var connected_players: Dictionary = {}
var is_hosting: bool = false
var is_connected: bool = false
var session_id: String = ""
var current_game_path: String = ""
var local_player_name: String = "Player"

var _tube_service: TubeClientServiceSingleton
var _pending_join_code: String = ""
var _pending_player_name: String = ""
var _last_player_snapshot: Dictionary = {}
const _SERVER_PEER_ID := 1

# Expose the TubeClient path so debugging tools (Tube Inspector) can connect
@export var tube_client_path: NodePath = NodePath("/root/TubeClientService")

func _ready() -> void:
	_tube_service = get_node_or_null(tube_client_path) as TubeClientServiceSingleton
	if not _tube_service:
		push_error("TubeClientService autoload is missing. Multiplayer will not function.")
		return
	
	_tube_service.session_created.connect(_on_session_created)
	_tube_service.session_joined.connect(_on_session_joined)
	_tube_service.session_left.connect(_on_session_left)
	_tube_service.player_list_changed.connect(_on_player_list_changed)
	_tube_service.lobby_error.connect(_on_lobby_error)
	_tube_service.session_state_changed.connect(_on_session_state_changed)
	_tube_service.session_id_changed.connect(_on_session_id_changed)


func host_game(player_name: String = "Host") -> bool:
	if not _tube_service:
		return false
	local_player_name = player_name.strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Host"
	_tube_service.host_game(local_player_name)
	return true


func join_game(join_code: String, player_name: String = "Player") -> bool:
	if not _tube_service:
		connection_failed.emit("TubeClientService not available")
		return false
	var trimmed_code := join_code.strip_edges()
	if trimmed_code.length() != 5:
		connection_failed.emit("Join code must be 5 characters (received: '%s')" % join_code)
		return false
	local_player_name = player_name.strip_edges()
	if local_player_name.is_empty():
		local_player_name = "Player"
	_pending_join_code = trimmed_code
	_pending_player_name = local_player_name
	print("[MP] Attempting to join session with code: %s as %s" % [trimmed_code, local_player_name])
	_tube_service.join_game(trimmed_code, local_player_name)
	return true


func disconnect_from_game() -> void:
	if not _tube_service:
		return
	_tube_service.leave_game()


func get_join_code() -> String:
	return session_id


func get_player_count() -> int:
	return connected_players.size()


func add_spawn_point(position: Vector3) -> void:
	if _tube_service:
		_tube_service.add_spawn_point(position)


func clear_spawn_points() -> void:
	if _tube_service:
		_tube_service.clear_spawn_points()


func get_next_spawn_position() -> Vector3:
	return _tube_service.get_next_spawn_point() if _tube_service else Vector3.ZERO


func is_server() -> bool:
	return _tube_service.is_host() if _tube_service else false


func get_local_peer_id() -> int:
	return _tube_service.get_peer_id() if _tube_service else 0


func get_connected_peer_ids() -> Array:
	return connected_players.keys()


func get_connected_players() -> Dictionary:
	return connected_players.duplicate()


func get_player_info(peer_id: int) -> Dictionary:
	return connected_players.get(peer_id, {})


func set_game_state(new_state: GameState) -> void:
	current_game_state = new_state


func get_game_state() -> GameState:
	return current_game_state


func is_game_in_progress() -> bool:
	return current_game_state == GameState.IN_GAME


func is_game_starting() -> bool:
	return current_game_state == GameState.STARTING


func register_player(peer_id: int, player_name: String) -> void:
	if not _tube_service:
		return
	var info := {
		"name": player_name,
		"ready": false,
		"team": 0,
		"score": 0,
	}
	_tube_service.update_player_info(peer_id, info)


func player_ready(peer_id: int) -> void:
	if _tube_service:
		_tube_service.mark_player_ready(peer_id)


func update_player_score(peer_id: int, new_score: int) -> void:
	if not _tube_service:
		return
	if is_server():
		_tube_service.update_player_info(peer_id, {"score": new_score})
	else:
		# Request update via host
		_tube_service.update_player_info(peer_id, {"score": new_score})


func start_game(scene_path: String = "res://scenes/multiplayer_game.tscn") -> void:
	if not is_server():
		_request_start_game.rpc_id(1, scene_path)
		return
	current_game_path = scene_path
	current_game_state = GameState.STARTING
	_rpc_start_game_for_all.rpc(scene_path)


func return_to_lobby(scene_path: String = "res://scenes/ui/multiplayer_menu_v2.tscn") -> void:
	if not is_server():
		_request_return_to_lobby.rpc_id(1, scene_path)
		return
	_rpc_return_to_lobby.rpc(scene_path)


func _on_session_created() -> void:
	is_hosting = true
	is_connected = true
	current_game_state = GameState.LOBBY
	register_player(_SERVER_PEER_ID, local_player_name)
	lobby_ready.emit()


func _on_session_joined() -> void:
	is_hosting = _tube_service.is_host()
	is_connected = true
	current_game_state = GameState.LOBBY
	register_player(get_local_peer_id(), local_player_name)
	lobby_ready.emit()


func _on_session_left() -> void:
	is_hosting = false
	is_connected = false
	current_game_state = GameState.LOBBY
	current_game_path = ""
	connected_players.clear()
	_last_player_snapshot.clear()


func _on_player_list_changed(players: Dictionary) -> void:
	var previous_keys := connected_players.keys()
	connected_players = players.duplicate()
	var current_keys := connected_players.keys()
	
	for peer_id in current_keys:
		if not previous_keys.has(peer_id):
			player_connected.emit(peer_id)
	
	for peer_id in previous_keys:
		if not current_keys.has(peer_id):
			player_disconnected.emit(peer_id)


func _on_lobby_error(_code: int, message: String) -> void:
	connection_failed.emit(message)


func _on_session_state_changed(new_state: TubeClientServiceSingleton.State) -> void:
	if new_state == TubeClientService.State.IDLE:
		current_game_state = GameState.LOBBY
		is_connected = false


func _on_session_id_changed(new_session_id: String) -> void:
	session_id = new_session_id
	session_id_changed.emit(session_id)
	if is_hosting and not new_session_id.is_empty():
		join_code_generated.emit(new_session_id)


@rpc("authority", "call_local", "reliable")
func _rpc_start_game_for_all(scene_path: String) -> void:
	current_game_path = scene_path
	current_game_state = GameState.IN_GAME
	var packed := load(scene_path)
	if packed:
		get_tree().change_scene_to_packed(packed)
	game_started.emit()
	match_state_changed.emit(true)


@rpc("authority", "call_local", "reliable")
func _rpc_return_to_lobby(scene_path: String) -> void:
	current_game_state = GameState.LOBBY
	var packed := load(scene_path)
	if packed:
		get_tree().change_scene_to_packed(packed)
	match_state_changed.emit(false)


@rpc("any_peer", "call_remote", "reliable")
func _request_start_game(scene_path: String) -> void:
	if not is_server():
		return
	start_game(scene_path)


@rpc("any_peer", "call_remote", "reliable")
func _request_return_to_lobby(scene_path: String) -> void:
	if not is_server():
		return
	return_to_lobby(scene_path)
