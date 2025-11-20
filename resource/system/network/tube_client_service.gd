extends Node
class_name TubeClientServiceSingleton

signal session_state_changed(new_state: State)
signal session_id_changed(session_id: String)
signal lobby_message(message: String)
signal player_list_changed(players: Dictionary)
signal lobby_error(code: int, message: String)
signal session_joined
signal session_created
signal session_left

enum State {
	IDLE,
	HOSTING,
	CONNECTED,
}

const _SERVER_PEER_ID := 1
const _TUBE_CLIENT_SCENE := preload("res://resource/system/network/tube_client.tscn")

var tube_client: TubeClient

var state: State = State.IDLE:
	set(value):
		if state == value:
			return
		state = value
		session_state_changed.emit(state)

var local_player_name: String = "Player"
var session_id: String = "":
	set(value):
		if session_id == value:
			return
		session_id = value
		session_id_changed.emit(session_id)

var connected_players: Dictionary = {}
var spawn_points: Array[Vector3] = []
var next_spawn_index := 0

var _pending_host: bool = false
var _pending_join: bool = false

func _ready():
	_instantiate_tube_client()


func _physics_process(_delta: float) -> void:
	# Keep autoload alive in case TubeClient gets removed accidentally.
	if not is_instance_valid(tube_client):
		_instantiate_tube_client()


func _instantiate_tube_client() -> void:
	if is_instance_valid(tube_client):
		return
	
	tube_client = get_node_or_null("TubeClient")
	if not is_instance_valid(tube_client):
		var instance := _TUBE_CLIENT_SCENE.instantiate()
		tube_client = instance
		add_child(tube_client)
	
	_connect_tube_signals()


func _connect_tube_signals() -> void:
	tube_client.session_created.connect(_on_session_created)
	tube_client.session_joined.connect(_on_session_joined)
	tube_client.session_left.connect(_on_session_left)
	tube_client.peer_connected.connect(_on_peer_connected)
	tube_client.peer_disconnected.connect(_on_peer_disconnected)
	tube_client.error_raised.connect(_on_error_raised)

	# Multiplayer API signals for fallbacks
	if tube_client.multiplayer_api:
		var multiplayer_api := tube_client.multiplayer_api
		if not multiplayer_api.peer_connected.is_connected(_on_peer_connected):
			multiplayer_api.peer_connected.connect(_on_peer_connected)
			multiplayer_api.peer_disconnected.connect(_on_peer_disconnected)


func host_game(player_name: String = "Host") -> void:
	if not is_instance_valid(tube_client):
		_instantiate_tube_client()
	
	if state != State.IDLE:
		_emit_lobby_message("Already in a session; leave before hosting.")
		return
	
	local_player_name = player_name
	_pending_host = true
	tube_client.create_session()


func join_game(join_session_id: String, player_name: String = "Player") -> void:
	if not is_instance_valid(tube_client):
		_instantiate_tube_client()
	
	if state != State.IDLE:
		_emit_lobby_message("Already in a session; leave before joining.")
		return
	
	local_player_name = player_name
	_pending_join = true
	tube_client.join_session(join_session_id.strip_edges())


func leave_game() -> void:
	if not is_instance_valid(tube_client):
		return
	
	tube_client.leave_session()


func is_host() -> bool:
	return is_instance_valid(tube_client) and tube_client.is_server


func get_peer_id() -> int:
	return tube_client.peer_id if is_instance_valid(tube_client) else 0


func get_player_count() -> int:
	return connected_players.size()


func get_connected_players() -> Dictionary:
	return connected_players.duplicate()


func add_spawn_point(position: Vector3) -> void:
	spawn_points.append(position)


func clear_spawn_points() -> void:
	spawn_points.clear()
	next_spawn_index = 0


func get_next_spawn_point() -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO
	var position := spawn_points[next_spawn_index]
	next_spawn_index = (next_spawn_index + 1) % spawn_points.size()
	return position


func _emit_lobby_message(message: String) -> void:
	lobby_message.emit(message)


func _on_session_created() -> void:
	session_created.emit()
	_pending_host = false
	state = State.HOSTING
	session_id = tube_client.session_id
	connected_players.clear()
	connected_players[_SERVER_PEER_ID] = {
		"name": local_player_name,
		"ready": false,
		"team": 0,
		"score": 0,
	}
	player_list_changed.emit(get_connected_players())
	_register_local_player_name(true)


func _on_session_joined() -> void:
	session_joined.emit()
	_pending_join = false
	state = State.CONNECTED
	session_id = tube_client.session_id
	connected_players.clear()
	player_list_changed.emit(get_connected_players())
	_request_register_player_name()


func _on_session_left() -> void:
	_reset_state()
	session_left.emit()


func _reset_state() -> void:
	state = State.IDLE
	session_id = ""
	_pending_host = false
	_pending_join = false
	connected_players.clear()
	player_list_changed.emit(get_connected_players())


func _on_peer_connected(peer_id: int) -> void:
	if peer_id == get_peer_id():
		return
	
	if is_host():
		# Send current roster to the new peer, including host.
		for existing_peer_id in connected_players.keys():
			var name: String = str(connected_players[existing_peer_id].get("name", ""))
			_rpc_register_player_name.rpc_id(peer_id, existing_peer_id, name)
	
	player_list_changed.emit(get_connected_players())


func _on_peer_disconnected(peer_id: int) -> void:
	if connected_players.has(peer_id):
		connected_players.erase(peer_id)
		player_list_changed.emit(get_connected_players())


func _on_error_raised(code: int, message: String) -> void:
	lobby_error.emit(code, message)
	_emit_lobby_message(message)
	if _pending_host or _pending_join:
		_reset_state()


func _register_local_player_name(is_host_peer: bool) -> void:
	if is_host_peer:
		_rpc_register_player_name.rpc(get_peer_id(), local_player_name)
	else:
		_rpc_request_register_player.rpc_id(_SERVER_PEER_ID, get_peer_id(), local_player_name)


func _request_register_player_name() -> void:
	if not is_instance_valid(tube_client):
		return
	if is_host():
		_register_local_player_name(true)
	else:
		_register_local_player_name(false)


@rpc("authority", "call_local", "reliable")
func _rpc_request_register_player(peer_id: int, player_name: String) -> void:
	connected_players[peer_id] = {
		"name": player_name,
		"ready": false,
		"team": 0,
		"score": 0,
	}
	player_list_changed.emit(get_connected_players())
	_rpc_register_player_name.rpc(peer_id, player_name)


@rpc("any_peer", "call_local", "reliable")
func _rpc_register_player_name(peer_id: int, player_name: String) -> void:
	connected_players[peer_id] = {
		"name": player_name,
		"ready": false,
		"team": 0,
		"score": 0,
	}
	player_list_changed.emit(get_connected_players())


func mark_player_ready(peer_id: int) -> void:
	if is_host():
		_rpc_player_ready.rpc(peer_id)
	else:
		_rpc_player_ready.rpc_id(_SERVER_PEER_ID, peer_id)


@rpc("any_peer", "call_local", "reliable")
func _rpc_player_ready(peer_id: int) -> void:
	if not connected_players.has(peer_id):
		connected_players[peer_id] = {
			"name": "Player%d" % peer_id,
			"ready": false,
			"team": 0,
			"score": 0,
		}
	
	connected_players[peer_id]["ready"] = true
	player_list_changed.emit(get_connected_players())


func register_player(peer_id: int, player_name: String) -> void:
	if is_host():
		_rpc_register_player_name.rpc(peer_id, player_name)
	else:
		_rpc_request_register_player.rpc_id(_SERVER_PEER_ID, peer_id, player_name)


func update_player_info(peer_id: int, info: Dictionary) -> void:
	if is_host():
		_apply_player_info(peer_id, info)
		_rpc_sync_player_info.rpc(peer_id, info)
	else:
		_rpc_request_player_info_update.rpc_id(_SERVER_PEER_ID, peer_id, info)


func _apply_player_info(peer_id: int, info: Dictionary) -> void:
	if not connected_players.has(peer_id):
		connected_players[peer_id] = {
			"name": info.get("name", "Player%d" % peer_id),
			"ready": info.get("ready", false),
			"team": info.get("team", 0),
			"score": info.get("score", 0),
		}
	else:
		for key in info.keys():
			connected_players[peer_id][key] = info[key]
	player_list_changed.emit(get_connected_players())


@rpc("authority", "call_local", "reliable")
func _rpc_sync_player_info(peer_id: int, info: Dictionary) -> void:
	_apply_player_info(peer_id, info)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_player_info_update(peer_id: int, info: Dictionary) -> void:
	if not is_host():
		return
	_apply_player_info(peer_id, info)
	_rpc_sync_player_info.rpc(peer_id, info)
