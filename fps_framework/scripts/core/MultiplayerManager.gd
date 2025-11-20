extends Node
class_name MPManager
# MultiplayerManager - Autoload Singleton
# Note: No class_name needed for autoload singletons

## Central manager for all multiplayer functionality
## Handles lobby management, server hosting, and client connections

# --- Network Configuration ---
const DEFAULT_PORT = 7000
const MAX_CLIENTS = 8
const BROADCAST_PORT = 7001
const BROADCAST_INTERVAL = 2.0  # Broadcast every 2 seconds

# --- Current State ---
var is_hosting: bool = false
var is_connected: bool = false
var current_lobby_info: Dictionary = {}
var connected_players: Dictionary = {}

# --- LAN Discovery ---
var broadcast_socket: UDPServer
var discovery_socket: PacketPeerUDP
var broadcast_timer: Timer
var discovered_servers: Array[Dictionary] = []

# --- Game State ---
var game_scene: PackedScene
var current_game_scene: Node
var pending_local_lobby: bool = false
var current_game_path: String = ""

# --- Signals ---
signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal lobby_ready()
signal game_started()
signal match_state_changed(active: bool)
signal connection_failed(error: String)
signal server_discovered(server_info: Dictionary)
signal servers_list_updated(servers: Array[Dictionary])
signal returned_to_lobby()

func _ready() -> void:
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Initialize LAN discovery
	_setup_lan_discovery()

# --- Public API ---

## Host a new game lobby
func host_game(player_name: String = "Host", port: int = DEFAULT_PORT) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_CLIENTS)
	
	if error != OK:
		print("Failed to host game: ", error)
		connection_failed.emit("Failed to start server on port %d" % port)
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = true
	is_connected = true
	
	# Add host player
	var host_info = {
		"name": player_name,
		"peer_id": 1,
		"team": 0,
		"score": 0
	}
	connected_players[1] = host_info
	
	print("Server started on port ", port)
	print("[DEBUG] Server hosting initiated. Starting LAN broadcast...")
	
	# Start broadcasting server info
	_start_server_broadcast(player_name, port)
	
	lobby_ready.emit()
	return true

## Join an existing game
func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> bool:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		print("Failed to join game: ", error)
		connection_failed.emit("Failed to connect to %s:%d" % [address, port])
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = false
	
	# Store our player info to send once connected
	# Ensure unique name
	var unique_name = player_name
	if get_local_peer_id() != 1:  # If not host
		unique_name += " " + str(randi() % 1000)
	current_lobby_info = {
		"name": unique_name,
		"team": 0,
		"score": 0
	}
	
	print("Attempting to connect to ", address, ":", port)
	print("[DEBUG] Direct connection attempt. No LAN discovery performed.")
	return true

## Disconnect from current game
func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	pending_local_lobby = false
	is_hosting = false
	is_connected = false
	connected_players.clear()
	current_lobby_info.clear()
	
	# Stop LAN broadcasting/discovery
	_stop_server_broadcast()
	_stop_server_discovery()
	
	# Return to main menu
	if current_game_scene:
		current_game_scene.queue_free()
		current_game_scene = null
	
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	current_game_path = ""
	current_game_scene = null

## Return players to the lobby without shutting down the session
func return_to_lobby() -> void:
	if not multiplayer.has_multiplayer_peer():
		_change_to_lobby_scene()
		return
	
	if is_hosting:
		print("[MultiplayerManager] Host returning all players to lobby")
		return_to_lobby_for_all.rpc()
	else:
		print("[MultiplayerManager] Client requesting lobby return")
		request_return_to_lobby.rpc_id(1, get_local_peer_id())

## Return only this peer to the lobby scene while keeping the session alive
func return_to_lobby_local() -> void:
	print("[MultiplayerManager] Local return to lobby requested")
	if pending_local_lobby:
		return
	if not multiplayer.has_multiplayer_peer():
		_change_to_lobby_scene(false)
		return
	
	pending_local_lobby = true
	request_leave_match.rpc_id(1)

## Start the actual game (host only)
func start_game(scene_path: String = "res://scenes/game_world.tscn") -> void:
	if not is_hosting:
		print("Only host can start the game")
		return
	
	current_game_path = scene_path
	# Load and start the game scene for all clients
	start_game_for_all.rpc(scene_path)

## Get list of connected players
func get_connected_players() -> Dictionary:
	return connected_players

## Get player info by peer ID
func get_player_info(peer_id: int) -> Dictionary:
	return connected_players.get(peer_id, {})

# --- RPC Methods ---

@rpc("authority", "call_local", "reliable")
func start_game_for_all(scene_path: String) -> void:
	current_game_path = scene_path
	game_scene = load(scene_path)
	if game_scene:
		get_tree().change_scene_to_packed(game_scene)
		current_game_scene = get_tree().current_scene
		game_started.emit()
		match_state_changed.emit(true)

@rpc("authority", "call_remote", "reliable")
func sync_match_state_for_peer(scene_path: String, match_stats: Dictionary) -> void:
	current_game_path = scene_path
	var scene = load(scene_path)
	if scene:
		get_tree().change_scene_to_packed(scene)
		game_started.emit()
	
	if GameRulesManager and match_stats:
		GameRulesManager.apply_match_snapshot(match_stats)

@rpc("authority", "call_local", "reliable")
func return_to_lobby_for_all() -> void:
	_change_to_lobby_scene()

@rpc("any_peer", "call_remote", "reliable")
func request_return_to_lobby(requester_id: int) -> void:
	if not is_hosting:
		return
	
	print("[MultiplayerManager] Received lobby return request from peer ", requester_id)
	return_to_lobby_for_all.rpc()

@rpc("any_peer", "call_remote", "reliable")
func register_player(player_info: Dictionary) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	player_info["peer_id"] = peer_id
	connected_players[peer_id] = player_info
	
	print("Player registered: ", player_info.name)
	player_connected.emit(peer_id, player_info)
	
	# Send updated player list to all clients
	sync_player_list.rpc(connected_players)
	
	# If a match is already in progress, sync the joining player into the game
	if is_hosting and current_game_path != "":
		var match_stats = {}
		if GameRulesManager:
			match_stats = GameRulesManager.get_match_stats()
			match_stats["time_limit"] = GameRulesManager.time_limit
		print("[MultiplayerManager] Syncing ongoing match for peer ", peer_id)
		sync_match_state_for_peer.rpc_id(peer_id, current_game_path, match_stats)

@rpc("authority", "call_local", "reliable")
func sync_player_list(players: Dictionary) -> void:
	print("[MultiplayerManager] Received player list sync: ", players)
	print("Local peer ID: ", get_local_peer_id(), " Is host: ", is_hosting)
	connected_players = players
	# Force UI refresh by emitting player_connected signal
	for peer_id in players:
		if peer_id != 1:  # Don't emit for host
			player_connected.emit(peer_id, players[peer_id])

@rpc("any_peer", "call_local", "reliable")
func update_player_score(peer_id: int, new_score: int) -> void:
	if peer_id in connected_players:
		connected_players[peer_id]["score"] = new_score
		sync_player_list.rpc(connected_players)

# --- Signal Handlers ---

func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	
	# If we're the host, wait for the client to register
	if is_hosting:
		print("Waiting for player registration from peer ", id)

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	
	if id in connected_players:
		var player_info = connected_players[id]
		connected_players.erase(id)
		print("Player left: ", player_info.get("name", "Unknown"))
		player_disconnected.emit(id)
		
		# Update all clients with new player list
		if is_hosting:
			sync_player_list.rpc(connected_players)

func _on_connected_to_server() -> void:
	print("Connected to server successfully")
	is_connected = true
	
	# Register our player with the server
	register_player.rpc_id(1, current_lobby_info)
	lobby_ready.emit()

func _on_connection_failed() -> void:
	print("Failed to connect to server")
	is_connected = false
	connection_failed.emit("Connection to server failed")

func _on_server_disconnected() -> void:
	print("Server disconnected")
	is_connected = false
	disconnect_from_game()

# --- Utility Methods ---

## Check if we are the server authority
func is_server() -> bool:
	return multiplayer.is_server()

## Get our own peer ID
func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()

## Check if a specific peer ID is the server
func is_peer_server(peer_id: int) -> bool:
	return peer_id == 1

# --- LAN Discovery System ---

## Setup LAN discovery system
func _setup_lan_discovery() -> void:
	# Initialize discovery socket for listening to broadcasts
	discovery_socket = PacketPeerUDP.new()
	discovery_socket.bind(BROADCAST_PORT)
	print("[LAN Discovery] Listening for server broadcasts on port ", BROADCAST_PORT)

## Start broadcasting server information
func _start_server_broadcast(server_name: String, port: int) -> void:
	if not is_hosting:
		return
	
	# Setup broadcast socket
	broadcast_socket = UDPServer.new()
	
	# Create broadcast timer
	broadcast_timer = Timer.new()
	broadcast_timer.wait_time = BROADCAST_INTERVAL
	broadcast_timer.timeout.connect(_broadcast_server_info.bind(server_name, port))
	add_child(broadcast_timer)
	broadcast_timer.start()
	
	print("[LAN Discovery] Started broadcasting server: ", server_name)

## Stop broadcasting server information
func _stop_server_broadcast() -> void:
	if broadcast_timer:
		broadcast_timer.queue_free()
		broadcast_timer = null
	
	if broadcast_socket:
		broadcast_socket = null
	
	print("[LAN Discovery] Stopped broadcasting")

## Broadcast server information to LAN
func _broadcast_server_info(server_name: String, port: int) -> void:
	var server_info = {
		"name": server_name,
		"port": port,
		"players": connected_players.size(),
		"max_players": MAX_CLIENTS,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	var message = JSON.stringify(server_info)
	var packet = message.to_utf8_buffer()
	
	# Broadcast to local network
	var broadcast_peer = PacketPeerUDP.new()
	broadcast_peer.connect_to_host("255.255.255.255", BROADCAST_PORT)
	broadcast_peer.put_packet(packet)
	broadcast_peer.close()

## Start discovering servers on LAN
func start_server_discovery() -> void:
	discovered_servers.clear()
	print("[LAN Discovery] Started scanning for local servers...")

## Stop discovering servers
func _stop_server_discovery() -> void:
	discovered_servers.clear()
	print("[LAN Discovery] Stopped scanning for servers")

## Get list of discovered servers
func get_discovered_servers() -> Array[Dictionary]:
	return discovered_servers

## Process incoming broadcast packets
func _process(delta: float) -> void:
	if not discovery_socket:
		return
	
	# Check for incoming broadcast packets
	if discovery_socket.get_available_packet_count() > 0:
		var packet = discovery_socket.get_packet()
		var message = packet.get_string_from_utf8()
		
		var json = JSON.new()
		var parse_result = json.parse(message)
		
		if parse_result == OK:
			var server_info = json.data
			if server_info is Dictionary:
				_handle_server_broadcast(server_info)

## Handle received server broadcast
func _handle_server_broadcast(server_info: Dictionary) -> void:
	# Don't add our own server
	if is_hosting:
		return
	
	# Validate server info
	if not server_info.has("name") or not server_info.has("port"):
		return
	
	# Add IP address from the packet
	server_info["ip"] = discovery_socket.get_packet_ip()
	
	# Check if server already exists in our list
	var existing_index = -1
	for i in range(discovered_servers.size()):
		if discovered_servers[i]["ip"] == server_info["ip"] and discovered_servers[i]["port"] == server_info["port"]:
			existing_index = i
			break
	
	# Update existing or add new server
	if existing_index >= 0:
		discovered_servers[existing_index] = server_info
	else:
		discovered_servers.append(server_info)
		print("[LAN Discovery] Found server: ", server_info["name"], " at ", server_info["ip"], ":", server_info["port"])
	
	# Clean up old servers (older than 10 seconds)
	var current_time = Time.get_unix_time_from_system()
	discovered_servers = discovered_servers.filter(func(server): return current_time - server.get("timestamp", 0) < 10.0)
	
	# Emit signals
	server_discovered.emit(server_info)
	servers_list_updated.emit(discovered_servers)

func _change_to_lobby_scene(reset_match_state: bool = true) -> void:
	pending_local_lobby = false
	if GameRulesManager:
		if GameRulesManager.game_paused:
			GameRulesManager.game_paused = false
			GameRulesManager.pause_menu_visibility_changed.emit(false)
		if reset_match_state:
			GameRulesManager.match_active = false
			GameRulesManager.match_paused = false
	
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if reset_match_state:
		current_game_path = ""
	current_game_scene = get_tree().current_scene
	lobby_ready.emit()
	returned_to_lobby.emit()
	match_state_changed.emit(false)

func _remove_player_from_game(peer_id: int) -> void:
	var world = get_tree().current_scene
	if world and world.has_method("remove_player_from_match"):
		world.remove_player_from_match(peer_id)
	if GameRulesManager:
		GameRulesManager.remove_player_from_match(peer_id)
	confirm_return_to_lobby.rpc_id(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func request_leave_match() -> void:
	if not is_hosting:
		return
	var peer_id = multiplayer.get_remote_sender_id()
	print("[MultiplayerManager] Peer ", peer_id, " requested to leave match")
	_remove_player_from_game(peer_id)

@rpc("authority", "call_remote", "reliable")
func confirm_return_to_lobby() -> void:
	if pending_local_lobby:
		pending_local_lobby = false
		_change_to_lobby_scene(false)

func on_local_player_removed_from_match() -> void:
	print("[MultiplayerManager] Local player removed from match")

func join_active_match() -> void:
	if not current_game_path:
		print("[MultiplayerManager] No active match to join")
		return
	if is_hosting:
		print("[MultiplayerManager] Host already in match")
		return
	print("[MultiplayerManager] Client joining active match")
	start_game_for_all(current_game_path)