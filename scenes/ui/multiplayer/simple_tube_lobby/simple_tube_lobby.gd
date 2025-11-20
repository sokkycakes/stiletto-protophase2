class_name SimpleTubeLobby
extends Control

const TubeState := TubeClient.State
const SERVER_PEER_ID := 1

@onready var tube_client: TubeClient = $TubeClient
@onready var status_label: Label = %StatusLabel
@onready var role_label: Label = %RoleLabel
@onready var session_id_label: Label = %SessionIdLabel
@onready var session_id_input: LineEdit = %SessionIdInput
@onready var create_button: Button = %CreateButton
@onready var join_button: Button = %JoinButton
@onready var leave_button: Button = %LeaveButton
@onready var peer_list: ItemList = %PeerList
@onready var log_output: RichTextLabel = %LogOutput
@onready var mp_test_map_button: Button = %mpTestMap
@onready var mp_duelists_map_button: Button = %mpDuelistsMap
@onready var copy_session_id_button: Button = %CopySessionIdButton

@export var mp_test_map_path: String = ""
@export var mp_duelists_map_path: String = ""

var known_peers: Dictionary[int, String] = {}


func _ready() -> void:
	_connect_tube_signals()
	_connect_ui_signals()
	_initialize_ui()


func _connect_tube_signals() -> void:
	if not tube_client.session_created.is_connected(_on_session_created):
		tube_client._session_initiated.connect(_on_session_initiated)
		tube_client.session_created.connect(_on_session_created)
		tube_client.session_joined.connect(_on_session_joined)
		tube_client.session_left.connect(_on_session_left)
		tube_client.peer_connected.connect(_on_peer_connected)
		tube_client.peer_disconnected.connect(_on_peer_disconnected)
		tube_client.error_raised.connect(_on_error_raised)


func _connect_ui_signals() -> void:
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	if copy_session_id_button:
		copy_session_id_button.pressed.connect(_on_copy_session_id_pressed)
	else:
		print("Warning: CopySessionIdButton not found in SimpleTubeLobby UI")
	# Some lobby buttons may be absent in certain builds; guard against null references
	if mp_test_map_button:
		mp_test_map_button.pressed.connect(_on_mp_test_map_pressed)
	else:
		print("Warning: mp_test_map_button not found in SimpleTubeLobby UI")
	if mp_duelists_map_button:
		mp_duelists_map_button.pressed.connect(_on_mp_duelists_map_pressed)
	else:
		print("Warning: mp_duelists_map_button not found in SimpleTubeLobby UI")


func _initialize_ui() -> void:
	log_output.clear()
	_append_log("Tube lobby ready.")
	_enter_idle_state()


func _enter_idle_state() -> void:
	_set_status("Idle")
	_set_role("Not connected")
	_set_session_id("-")
	session_id_input.editable = true
	session_id_input.text = ""
	create_button.disabled = false
	join_button.disabled = false
	leave_button.disabled = true
	known_peers.clear()
	_refresh_peer_list()


func _set_busy_state(description: String) -> void:
	_set_status(description)
	create_button.disabled = true
	join_button.disabled = true
	leave_button.disabled = true


func _set_active_state(is_server: bool) -> void:
	var role_text := "Server (You)" if is_server else "Client (You)"
	_set_role(role_text)
	create_button.disabled = true
	join_button.disabled = true
	leave_button.disabled = false
	session_id_input.editable = not is_server


func _set_status(text: String) -> void:
	status_label.text = "Status: %s" % text


func _set_role(text: String) -> void:
	role_label.text = "Role: %s" % text


func _set_session_id(text: String) -> void:
	session_id_label.text = "Current Session ID: %s" % text
	session_id_input.text = text


func _refresh_peer_list() -> void:
	peer_list.clear()
	var peer_ids := known_peers.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		var label := known_peers[peer_id]
		peer_list.add_item("%s [ID %d]" % [label, peer_id])


func _append_log(message: String) -> void:
	log_output.append_text("%s\n" % message)
	log_output.scroll_to_line(max(0, log_output.get_line_count() - 1))


func _get_current_session_id() -> String:
	var candidate := session_id_input.text.strip_edges()
	if not candidate.is_empty():
		return candidate
	var label_parts := session_id_label.text.split(":")
	if label_parts.size() > 1:
		return label_parts[1].strip_edges()
	return ""


func _on_create_pressed() -> void:
	_set_busy_state("Creating session...")
	_append_log("Creating new session...")
	tube_client.create_session()


func _on_join_pressed() -> void:
	var session_id := session_id_input.text.strip_edges()
	if session_id.is_empty():
		_append_log("Cannot join: Session ID required.")
		session_id_input.grab_focus()
		return
	
	_set_busy_state("Joining session...")
	_append_log("Joining session %s..." % session_id)
	tube_client.join_session(session_id)


func _on_copy_session_id_pressed() -> void:
	var session_id := _get_current_session_id()
	if session_id.is_empty():
		_append_log("No session ID available to copy.")
		return
	DisplayServer.clipboard_set(session_id)
	_append_log("Copied session ID: %s" % session_id)


func _on_leave_pressed() -> void:
	_append_log("Leaving current session...")
	tube_client.leave_session()


func _on_session_initiated() -> void:
	match tube_client.state:
		TubeState.CREATING_SESSION:
			_set_busy_state("Creating session...")
		TubeState.JOINING_SESSION:
			_set_busy_state("Joining session...")
		_:
			pass


func _on_session_created() -> void:
	_append_log("Session created. Share ID %s" % tube_client.session_id)
	_set_status("Hosting session")
	_set_session_id(tube_client.session_id)
	_set_active_state(true)
	known_peers.clear()
	_add_local_peer()


func _on_session_joined() -> void:
	_append_log("Session joined successfully.")
	_set_status("Connected to server")
	_set_session_id(tube_client.session_id)
	_set_active_state(false)
	session_id_input.text = tube_client.session_id
	known_peers.clear()
	_add_local_peer()


func _on_session_left() -> void:
	_append_log("Session closed.")
	_enter_idle_state()


func _on_peer_connected(peer_id: int) -> void:
	if peer_id == tube_client.peer_id:
		return
	
	var label := "Server" if peer_id == SERVER_PEER_ID else "Peer"
	known_peers[peer_id] = label
	_refresh_peer_list()
	_append_log("Peer %d connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if known_peers.erase(peer_id):
		_refresh_peer_list()
	_append_log("Peer %d disconnected." % peer_id)


func _on_error_raised(code: int, message: String) -> void:
	_append_log("[Error %d] %s" % [code, message])
	if tube_client.state == TubeState.IDLE:
		_enter_idle_state()
	else:
		_set_status("Error: %s" % message)
		leave_button.disabled = false


func _add_local_peer() -> void:
	var label := "You (Server)" if tube_client.is_server else "You (Client)"
	known_peers[tube_client.peer_id] = label
	_refresh_peer_list()


func _on_mp_test_map_pressed() -> void:
	_request_map_load(mp_test_map_path)


func _on_mp_duelists_map_pressed() -> void:
	_request_map_load(mp_duelists_map_path)

func _request_map_load(map_path: String) -> void:
	if not _can_host_map_events(true):
		return
	if map_path.is_empty():
		_append_log("Error: Map path not configured for this button.")
		return
	if not ResourceLoader.exists(map_path):
		_append_log("Error: Map file not found at path: %s" % map_path)
		return
	_rpc_load_map.rpc(map_path)


func _load_map(map_path: String) -> void:
	_append_log("Loading map: %s" % map_path)
	get_tree().change_scene_to_file(map_path)


@rpc("authority", "call_local", "reliable")
func _rpc_load_map(map_path: String) -> void:
	_load_map(map_path)


func _can_host_map_events(log_warning: bool = false) -> bool:
	if not tube_client:
		return false
	if not tube_client.is_server:
		if log_warning:
			_append_log("Only the server host can launch maps.")
		return false
	return true
