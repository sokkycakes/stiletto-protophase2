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

# --- Noray Configuration ---
# IMPORTANT: Replace "noray.example.com" with your actual Noray server address
# You can find public Noray servers or host your own at: https://github.com/foxssake/noray
const NORAY_HOST: String = "tomfol.io"  # Replace with your noray server address
const NORAY_PORT: int = 8890
const NORAY_REGISTRAR_PORT: int = 8809

# --- Current State ---
var is_hosting: bool = false
var is_connected: bool = false
var current_lobby_info: Dictionary = {}
var connected_players: Dictionary = {}

# --- Noray State ---
var noray_connected: bool = false
var noray_oid: String = ""  # Open ID (public, shareable)
var noray_pid: String = ""  # Private ID (internal)
var noray_registered_port: int = -1
var pending_noray_connection: bool = false
var target_host_oid: String = ""  # OID of host we're trying to connect to

# --- LAN Discovery ---
var lan_discovery: LanDiscovery
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
	
	# Check if Noray autoloads are available
	var noray_node = get_node_or_null("/root/Noray")
	var handshake_node = get_node_or_null("/root/PacketHandshake")
	
	if not noray_node:
		push_error("[MultiplayerManager] Noray autoload not found! Please enable the netfox.noray plugin in Project Settings > Plugins")
		return
	
	if not handshake_node:
		push_error("[MultiplayerManager] PacketHandshake autoload not found! Please enable the netfox.noray plugin in Project Settings > Plugins")
		return
	
	# Connect to Noray
	_connect_to_noray()
	
	# Connect Noray signals (using get_node to avoid compile-time errors)
	var noray = get_node("/root/Noray")
	noray.on_connect_to_host.connect(_on_noray_connected)
	noray.on_disconnect_from_host.connect(_on_noray_disconnected)
	noray.on_oid.connect(_on_noray_oid_received)
	noray.on_pid.connect(_on_noray_pid_received)
	# Route connection signals based on role (host vs client)
	noray.on_connect_nat.connect(_handle_noray_connect_nat)
	noray.on_connect_relay.connect(_handle_noray_connect_relay)
	
	# Initialize LAN discovery
	_setup_lan_discovery()

# --- Public API ---

## Host a new game lobby with Noray support
func host_game(player_name: String = "Host", port: int = DEFAULT_PORT) -> bool:
	# Ensure Noray is connected
	if not noray_connected:
		await _connect_to_noray()
		if not noray_connected:
			connection_failed.emit("Failed to connect to Noray server")
			return false
	
	# Get Noray node
	var noray = get_node("/root/Noray")
	
	# Register as host with Noray
	print("[Noray] Registering as host...")
	var error = noray.register_host()
	if error != OK:
		print("[Noray] Failed to register host: ", error)
		connection_failed.emit("Failed to register with Noray")
		return false
	
	# Wait for OID and PID
	pending_noray_connection = true
	await noray.on_oid
	await noray.on_pid
	
	if noray_oid.is_empty() or noray_pid.is_empty():
		connection_failed.emit("Failed to get Noray IDs")
		pending_noray_connection = false
		return false
	
	# Register our port with Noray
	error = await noray.register_remote(NORAY_REGISTRAR_PORT)
	if error != OK:
		print("[Noray] Failed to register port: ", error)
		connection_failed.emit("Failed to register port with Noray")
		pending_noray_connection = false
		return false
	
	noray_registered_port = noray.local_port
	if noray_registered_port <= 0:
		noray_registered_port = port  # Fallback to requested port
	
	print("[Noray] Registered port: ", noray_registered_port)
	
	# Create ENet server on the registered port
	var peer = ENetMultiplayerPeer.new()
	error = peer.create_server(noray_registered_port, MAX_CLIENTS)
	
	if error != OK:
		print("Failed to host game: ", error)
		connection_failed.emit("Failed to start server on port %d" % noray_registered_port)
		pending_noray_connection = false
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = true
	is_connected = true
	pending_noray_connection = false
	
	# Add host player with Noray OID
	var host_info = {
		"name": player_name,
		"peer_id": 1,
		"team": 0,
		"score": 0,
		"noray_oid": noray_oid
	}
	connected_players[1] = host_info
	
	print("Server started on port ", noray_registered_port)
	print("[Noray] Host OID: ", noray_oid, " (share this for players to join)")
	
	# Start broadcasting server info (optional - can include OID)
	_start_server_broadcast(player_name, noray_registered_port)
	
	lobby_ready.emit()
	return true

## Join an existing game using Noray
## host_oid: The Open ID of the host (from Noray)
## player_name: Player's name
func join_game(host_oid: String, player_name: String, port: int = DEFAULT_PORT) -> bool:
	# Check if we're trying to connect to ourselves (same machine)
	# This happens when both host and client are on the same PC
	if noray_oid == host_oid:
		print("[Noray] Detected local connection (same OID), using direct localhost connection")
		return join_game_direct("127.0.0.1", player_name, port)
	
	# Ensure Noray is connected
	if not noray_connected:
		await _connect_to_noray()
		if not noray_connected:
			connection_failed.emit("Failed to connect to Noray server")
			return false
	
	# Get Noray node
	var noray = get_node("/root/Noray")
	
	# Register as client with Noray (to get our PID)
	print("[Noray] Registering as client...")
	var error = noray.register_host()  # This gets us a PID
	if error != OK:
		print("[Noray] Failed to register: ", error)
		connection_failed.emit("Failed to register with Noray")
		return false
	
	# Wait for PID
	await noray.on_pid
	if noray_pid.is_empty():
		connection_failed.emit("Failed to get Noray PID")
		return false
	
	# Register our port
	error = await noray.register_remote(NORAY_REGISTRAR_PORT)
	if error != OK:
		print("[Noray] Failed to register port: ", error)
		# Continue anyway, we'll use the requested port
	
	noray_registered_port = noray.local_port
	if noray_registered_port <= 0:
		noray_registered_port = port
	
	# Store target host OID for relay fallback
	target_host_oid = host_oid
	
	# Request connection to host via NAT punchthrough
	print("[Noray] Requesting NAT connection to host: ", host_oid)
	pending_noray_connection = true
	error = noray.connect_nat(host_oid)
	if error != OK:
		print("[Noray] Failed to request NAT connection: ", error)
		# Try relay as fallback
		error = noray.connect_relay(host_oid)
		if error != OK:
			connection_failed.emit("Failed to connect via Noray")
			pending_noray_connection = false
			target_host_oid = ""
			return false
	
	# Wait for connection instructions (handled in signal handlers)
	# The _on_noray_connect_nat or _on_noray_connect_relay will call
	# _establish_enet_connection() which will complete the join
	
	# Store player info
	var unique_name = player_name
	current_lobby_info = {
		"name": unique_name,
		"team": 0,
		"score": 0
	}
	
	return true

## Join an existing game using direct IP/port (bypasses Noray)
## address: IP address or hostname of the server
## player_name: Player's name
## port: Port number of the server
func join_game_direct(address: String, player_name: String, port: int = DEFAULT_PORT) -> bool:
	print("[MultiplayerManager] Joining game directly at ", address, ":", port)
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	
	if error != OK:
		print("[MultiplayerManager] Failed to create client: ", error)
		connection_failed.emit("Failed to connect to %s:%d (error: %d)" % [address, port, error])
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = false
	
	# Store player info
	var unique_name = player_name
	current_lobby_info = {
		"name": unique_name,
		"team": 0,
		"score": 0
	}
	
	print("[MultiplayerManager] Connecting to ", address, ":", port)
	return true

## Disconnect from current game
func disconnect_from_game() -> void:
	# If we're already fully disconnected (no peer, no game), still ensure we return
	# to the main menu so the UI isn't stuck in the lobby.
	if not is_connected and not is_hosting and current_game_path == "":
		print("[MultiplayerManager] Already disconnected – returning to main menu UI")
		get_tree().change_scene_to_file("res://scenes/mp_framework/main_menu.tscn")
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	
	# Use call_deferred to handle async cleanup safely
	call_deferred("_disconnect_from_game_async")

## Internal async version of disconnect_from_game
func _disconnect_from_game_async() -> void:
	print("[MultiplayerManager] Disconnecting from game...")
	
	# Release mouse capture immediately
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Clean up game world if we're in one
	if current_game_path != "":
		var current_scene = get_tree().current_scene
		if current_scene and is_instance_valid(current_scene):
			# Check if current scene is a GameWorld or has game world logic
			var game_world: GameWorld = null
			if current_scene is GameWorld:
				game_world = current_scene as GameWorld
			else:
				game_world = get_tree().get_first_node_in_group("game_world") as GameWorld
			
			if game_world and is_instance_valid(game_world):
				print("[MultiplayerManager] Cleaning up game world before disconnect")
				# Clean up all players first (synchronous cleanup)
				game_world.cleanup_all_players()
				# Wait a frame for cleanup to complete
				await get_tree().process_frame
		
		# Also clean up current_game_scene if it exists
		if current_game_scene and is_instance_valid(current_game_scene):
			current_game_scene.queue_free()
			current_game_scene = null
	
	# Close multiplayer connection (do this after cleanup to prevent RPC issues)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	pending_local_lobby = false
	is_hosting = false
	is_connected = false
	connected_players.clear()
	current_lobby_info.clear()
	
	# Reset Noray state (but keep connection alive for future games)
	noray_oid = ""
	noray_pid = ""
	noray_registered_port = -1
	pending_noray_connection = false
	target_host_oid = ""
	
	# Stop LAN broadcasting/discovery
	_stop_server_broadcast()
	_stop_server_discovery()
	
	# Reset game state
	current_game_path = ""
	current_game_scene = null
	
	# Clean up GameRulesManager state if it exists
	if GameRulesManager:
		GameRulesManager.match_active = false
		GameRulesManager.match_paused = false
		if GameRulesManager.game_paused:
			GameRulesManager.game_paused = false
			GameRulesManager.pause_menu_visibility_changed.emit(false)
	
	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/mp_framework/main_menu.tscn")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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
func start_game(scene_path: String = "res://scenes/mp_framework/game_world.tscn") -> void:
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
	# Ensure we're not in a game world before starting
	if current_game_path != "":
		var current_scene = get_tree().current_scene
		if current_scene:
			var game_world: GameWorld = null
			if current_scene is GameWorld:
				game_world = current_scene as GameWorld
			else:
				game_world = get_tree().get_first_node_in_group("game_world") as GameWorld
			
			if game_world:
				print("[MultiplayerManager] Cleaning up existing game world before starting new game")
				game_world.cleanup_all_players()
				await get_tree().process_frame
	
	current_game_path = scene_path
	game_scene = load(scene_path)
	if game_scene:
		get_tree().change_scene_to_packed(game_scene)
		# Wait for scene to be ready
		await get_tree().process_frame
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
	
	# If the host (peer_id == 1) disconnects and we're the host, clean up the server
	if id == 1 and is_hosting:
		print("[MultiplayerManager] Host disconnected from their own server - cleaning up")
		# Only disconnect if we're still connected (prevent double cleanup)
		if is_connected or current_game_path != "":
			disconnect_from_game()
		return
	
	# Only process client disconnections if we still have a valid multiplayer peer
	if not multiplayer.has_multiplayer_peer():
		return
	
	if id in connected_players:
		var player_info = connected_players[id]
		connected_players.erase(id)
		print("Player left: ", player_info.get("name", "Unknown"))
		player_disconnected.emit(id)
		
		# Update all clients with new player list (only if we still have multiplayer peer)
		if is_hosting and multiplayer.has_multiplayer_peer():
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
	# If we're a client, gracefully return to the lobby scene instead of hanging.
	if is_hosting:
		disconnect_from_game()
	else:
		print("[MultiplayerManager] Server disconnected – returning to lobby scene for client")
		_change_to_lobby_scene()

# --- Utility Methods ---

## Check if an address is local (localhost or local network)
func _is_local_address(address: String) -> bool:
	if address == "127.0.0.1" or address == "localhost":
		return true
	
	# Check if it matches any of our local IPs
	var local_ips = IP.get_local_addresses()
	for local_ip in local_ips:
		if address == local_ip:
			return true
		# Also check for common local network ranges
		if address.begins_with("192.168.") and local_ip.begins_with("192.168."):
			return true
		if address.begins_with("10.") and local_ip.begins_with("10."):
			return true
		if address.begins_with("172.16.") and local_ip.begins_with("172.16."):
			return true
	
	return false

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
	lan_discovery = LanDiscovery.new()
	lan_discovery.name = "LanDiscovery"
	lan_discovery.server_list_updated.connect(_on_server_list_updated)
	lan_discovery.server_found.connect(func(info): server_discovered.emit(info))
	add_child(lan_discovery)

## Handle server list updates from LanDiscovery
func _on_server_list_updated(servers: Array[Dictionary]) -> void:
	# Preserve localhost entry if exists in our manual list?
	# Actually, let's just trust LanDiscovery + our manual localhost addition if needed.
	# But LanDiscovery won't find localhost (we filtered it).
	# So we need to merge LanDiscovery results with our manual localhost entry if we are hosting.
	
	# Create a new list based on LanDiscovery results
	var new_list = servers.duplicate()
	
	# If we are hosting, ensure localhost is in the list for ourselves
	if is_hosting and noray_registered_port > 0:
		var localhost_entry = {
			"name": connected_players.get(1, {}).get("name", "Host"),
			"ip": "127.0.0.1",
			"port": noray_registered_port,
			"players": connected_players.size(),
			"max_players": MAX_CLIENTS,
			"timestamp": Time.get_unix_time_from_system(),
			"unique_id": "localhost" # Dummy ID
		}
		new_list.append(localhost_entry)
		
	discovered_servers = new_list
	servers_list_updated.emit(discovered_servers)

## Start broadcasting server information
func _start_server_broadcast(server_name: String, port: int) -> void:
	if not is_hosting:
		return
		
	var server_info = {
		"name": server_name,
		"port": port,
		"players": connected_players.size(),
		"max_players": MAX_CLIENTS
	}
	
	lan_discovery.start_broadcasting(server_info)
	
	# Trigger an immediate update to show localhost
	# Accessing internal for now or just pass empty array and let it rebuild
	var empty_list: Array[Dictionary] = []
	_on_server_list_updated(empty_list) # This will add localhost entry


## Stop broadcasting server information
func _stop_server_broadcast() -> void:
	if lan_discovery:
		lan_discovery.stop_broadcasting()
	
	# Clear list if we stop hosting (remove localhost entry)
	if is_hosting:
		var empty_list: Array[Dictionary] = []
		_on_server_list_updated(empty_list)


## Start discovering servers on LAN
func start_server_discovery() -> void:
	lan_discovery.start_listening()
	print("[LAN Discovery] Started scanning for local servers...")

## Stop discovering servers
func _stop_server_discovery() -> void:
	lan_discovery.stop_listening()
	# print("[LAN Discovery] Stopped scanning for servers")

## Get list of discovered servers
func get_discovered_servers() -> Array[Dictionary]:
	return discovered_servers



func _change_to_lobby_scene(reset_match_state: bool = true) -> void:
	pending_local_lobby = false
	
	# Release mouse capture immediately to prevent input issues
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Clean up game world and all player instances before changing scenes
	if current_game_path != "" or reset_match_state:
		var current_scene = get_tree().current_scene
		if current_scene:
			# Check if current scene is a GameWorld or has game world logic
			var game_world: GameWorld = null
			if current_scene is GameWorld:
				game_world = current_scene as GameWorld
			else:
				game_world = get_tree().get_first_node_in_group("game_world") as GameWorld
			
			if game_world:
				print("[MultiplayerManager] Cleaning up game world and players before returning to lobby")
				game_world.cleanup_all_players()
				
				# Wait a frame to ensure cleanup completes
				await get_tree().process_frame
	
	# Clear character selections from all players when returning to lobby
	# This ensures character select UI will be shown again for the next game
	if reset_match_state:
		for peer_id in connected_players:
			if connected_players[peer_id].has("character_path"):
				connected_players[peer_id].erase("character_path")
				print("[MultiplayerManager] Cleared character_path for peer %d" % peer_id)
		
		# Sync cleared player list to all clients
		if is_hosting and multiplayer.has_multiplayer_peer():
			sync_player_list.rpc(connected_players)
	
	if GameRulesManager:
		if GameRulesManager.game_paused:
			GameRulesManager.game_paused = false
			GameRulesManager.pause_menu_visibility_changed.emit(false)
		if reset_match_state:
			GameRulesManager.match_active = false
			GameRulesManager.match_paused = false
	
	# Reset game path before scene change
	if reset_match_state:
		current_game_path = ""
		current_game_scene = null
	
	# Change scene - this will automatically free the old scene
	get_tree().change_scene_to_file("res://scenes/mp_framework/lobby.tscn")
	
	# Wait for scene to be ready
	await get_tree().process_frame
	
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

# --- Noray Connection Methods ---

## Connect to Noray server
func _connect_to_noray() -> void:
	var noray = get_node_or_null("/root/Noray")
	if not noray:
		push_error("[MultiplayerManager] Cannot connect to Noray - autoload not available")
		noray_connected = false
		return
	
	if noray.is_connected_to_host():
		noray_connected = true
		return
	
	print("[Noray] Connecting to Noray server...")
	var error = await noray.connect_to_host(NORAY_HOST, NORAY_PORT)
	if error != OK:
		print("[Noray] Failed to connect: ", error)
		noray_connected = false
	else:
		noray_connected = true
		print("[Noray] Connected successfully")

## Handle Noray connection events
func _on_noray_connected() -> void:
	noray_connected = true
	print("[Noray] Connected to Noray server")

func _on_noray_disconnected() -> void:
	noray_connected = false
	noray_oid = ""
	noray_pid = ""
	noray_registered_port = -1
	print("[Noray] Disconnected from Noray server")

func _on_noray_oid_received(oid: String) -> void:
	noray_oid = oid
	print("[Noray] Received OID: ", oid)
	# Store OID in player info for sharing
	if is_hosting and 1 in connected_players:
		connected_players[1]["noray_oid"] = oid

func _on_noray_pid_received(pid: String) -> void:
	noray_pid = pid
	print("[Noray] Received PID: ", pid)

## Route NAT connection signal based on role (host vs client)
func _handle_noray_connect_nat(address: String, port: int) -> void:
	if is_hosting:
		_on_noray_connect_nat_host(address, port)
	else:
		_on_noray_connect_nat_client(address, port)

## Route relay connection signal based on role (host vs client)
func _handle_noray_connect_relay(address: String, port: int) -> void:
	if is_hosting:
		_on_noray_connect_relay_host(address, port)
	else:
		_on_noray_connect_relay_client(address, port)

## Client: Handle NAT connection instructions
func _on_noray_connect_nat_client(address: String, port: int) -> void:
	print("[Noray] Client: NAT connection instructions: ", address, ":", port)
	_establish_enet_connection(address, port, false)

## Client: Handle relay connection instructions
func _on_noray_connect_relay_client(address: String, port: int) -> void:
	print("[Noray] Client: Relay connection instructions: ", address, ":", port)
	
	# Check if this is a local address - if so, connect directly (bypass relay)
	if _is_local_address(address):
		print("[Noray] Detected local address, connecting directly (bypassing relay)")
		_establish_enet_connection(address, port, false)  # Use direct connection, not relay
	else:
		_establish_enet_connection(address, port, true)  # Use relay

## Host: Handle incoming NAT connection
func _on_noray_connect_nat_host(address: String, port: int) -> void:
	if not is_hosting:
		return  # Only host should handle this
	
	print("[Noray] Host: NAT connection from ", address, ":", port)
	var peer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if not peer:
		push_error("[Noray] Host: No ENet peer available")
		return
	
	var handshake = get_node_or_null("/root/PacketHandshake")
	if not handshake:
		push_error("[Noray] Host: PacketHandshake not available")
		return
	
	# Host uses over_enet, not over_packet_peer (as per documentation)
	var err = await handshake.over_enet(peer.host, address, port)
	if err != OK:
		print("[Noray] Host: Handshake failed: ", err)
	else:
		print("[Noray] Host: Handshake successful with ", address, ":", port)

## Host: Handle incoming relay connection
func _on_noray_connect_relay_host(address: String, port: int) -> void:
	if not is_hosting:
		return  # Only host should handle this
	
	print("[Noray] Host: Relay connection from ", address, ":", port)
	var peer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if not peer:
		push_error("[Noray] Host: No ENet peer available")
		return
	
	var handshake = get_node_or_null("/root/PacketHandshake")
	if not handshake:
		push_error("[Noray] Host: PacketHandshake not available")
		return
	
	# According to documentation, host should use over_enet for BOTH NAT and relay
	# The handshake goes through the relay server which forwards it
	var err = await handshake.over_enet(peer.host, address, port)
	if err != OK:
		print("[Noray] Host: Relay handshake failed: ", err)
	else:
		print("[Noray] Host: Relay handshake successful with ", address, ":", port)

## Establish ENet connection after Noray handshake
func _establish_enet_connection(address: String, port: int, use_relay: bool = false) -> void:
	print("[Noray] Establishing ENet connection to ", address, ":", port, " (relay: ", use_relay, ")")
	
	# According to documentation, handshake should be performed for BOTH NAT and relay
	# For relay, the handshake goes through the relay server which forwards it
	var udp_peer = PacketPeerUDP.new()
	var noray = get_node("/root/Noray")
	udp_peer.bind(noray.local_port)
	udp_peer.set_dest_address(address, port)
	
	print("[Noray] Performing UDP handshake... (relay: ", use_relay, ")")
	var handshake = get_node_or_null("/root/PacketHandshake")
	if not handshake:
		push_error("[MultiplayerManager] PacketHandshake autoload not available")
		udp_peer.close()
		connection_failed.emit("PacketHandshake not available")
		pending_noray_connection = false
		target_host_oid = ""
		return
	
	var handshake_result = await handshake.over_packet_peer(udp_peer, 8.0, 0.1)
	udp_peer.close()
	
	# For NAT connections, if handshake fails, try relay as fallback
	if not use_relay:
		if handshake_result != OK and handshake_result != ERR_BUSY:
			print("[Noray] NAT handshake failed: ", handshake_result)
			# Try relay as fallback
			if not target_host_oid.is_empty():
				print("[Noray] Attempting relay fallback...")
				var relay_error = noray.connect_relay(target_host_oid)
				if relay_error == OK:
					return  # Will be handled by relay signal
				else:
					connection_failed.emit("Handshake failed and relay unavailable")
					pending_noray_connection = false
					target_host_oid = ""
					return
	else:
		# For relay, handshake might fail but we can still try to connect
		# The relay server forwards packets, so handshake might work differently
		if handshake_result != OK and handshake_result != ERR_BUSY:
			print("[Noray] Relay handshake result: ", handshake_result, " (continuing anyway)")
	
	# Create ENet client
	# CRITICAL: Must specify local_port as the last parameter
	# This is the only port noray recognizes, and failing to specify it will result in broken connectivity
	# Use noray.local_port (already retrieved above)
	var peer = ENetMultiplayerPeer.new()
	var local_port_to_use = noray.local_port
	
	if local_port_to_use <= 0:
		print("[Noray] Warning: local_port is invalid (", local_port_to_use, "), using registered port: ", noray_registered_port)
		local_port_to_use = noray_registered_port
	
	if local_port_to_use <= 0:
		push_error("[Noray] No valid local port available for ENet client")
		connection_failed.emit("No valid local port registered with Noray")
		pending_noray_connection = false
		target_host_oid = ""
		return
	
	print("[Noray] Creating ENet client: address=", address, " port=", port, " local_port=", local_port_to_use, " relay=", use_relay)
	print("[Noray] Client info - registered_port: ", noray_registered_port, ", noray.local_port: ", noray.local_port)
	
	# Create ENet client
	# For relay, we still need to specify the local port so Noray can route traffic correctly
	var error = peer.create_client(address, port, 0, 0, 0, local_port_to_use)
	
	if error != OK:
		print("[Noray] Failed to create ENet client: ", error)
		connection_failed.emit("Failed to create client connection to %s:%d (error: %d)" % [address, port, error])
		pending_noray_connection = false
		target_host_oid = ""
		return
	
	multiplayer.multiplayer_peer = peer
	is_hosting = false
	
	print("[Noray] ENet client created, waiting for connection to ", address, ":", port)
	
	# Wait for connection to establish
	# ENet connections are asynchronous - poll and check status
	var connection_timeout = 20.0  # 20 second timeout (longer for relay)
	var elapsed = 0.0
	var poll_interval = 0.1  # Poll 10 times per second
	var last_status = -1
	var status_log_interval = 2.0  # Log status every 2 seconds
	var last_status_log = 0.0
	
	while elapsed < connection_timeout:
		# Poll the peer to process connection
		peer.poll()
		
		# Check connection status
		var status = peer.get_connection_status()
		
		# Log status changes or periodically for debugging
		if status != last_status:
			print("[Noray] Connection status changed: ", status, " (elapsed: ", elapsed, "s)")
			last_status = status
		elif elapsed - last_status_log >= status_log_interval:
			print("[Noray] Connection status: ", status, " (elapsed: ", elapsed, "s, connecting to ", address, ":", port, ")")
			last_status_log = elapsed
		
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			print("[Noray] Successfully connected to ", address, ":", port)
			pending_noray_connection = false
			target_host_oid = ""
			# The connected_to_server signal will be handled by _on_connected_to_server
			return
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			# Only treat as error if we've been trying for a bit
			# Initial state might be disconnected before connecting starts
			if elapsed > 1.0:  # After 1 second
				print("[Noray] Connection disconnected to ", address, ":", port, " after ", elapsed, "s")
				connection_failed.emit("Connection failed to %s:%d" % [address, port])
				pending_noray_connection = false
				target_host_oid = ""
				multiplayer.multiplayer_peer = null
				peer.close()
				return
		
		await get_tree().create_timer(poll_interval).timeout
		elapsed += poll_interval
	
	# Timeout reached
	var final_status = peer.get_connection_status()
	print("[Noray] Connection timeout to ", address, ":", port, " (status: ", final_status, ", elapsed: ", elapsed, "s)")
	connection_failed.emit("Connection timeout to %s:%d (status: %d)" % [address, port, final_status])
	pending_noray_connection = false
	target_host_oid = ""
	multiplayer.multiplayer_peer = null
	peer.close()
