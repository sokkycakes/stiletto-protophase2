extends Node

# Multiplayer Manager for simplified P2P networking with join codes
# Handles connection setup, player management, and synchronization

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed(reason: String)
signal join_code_generated(code: String)
signal hosting_started()
signal joined_game()

# Connection settings
const DEFAULT_PORT = 7000
const MAX_PLAYERS = 8

# Join code system
var current_join_code: String = ""
var is_hosting: bool = false
var connected_players: Dictionary = {}
var local_player_name: String = "Player"

# Game state
enum GameState { LOBBY, STARTING, IN_GAME }
var current_game_state: GameState = GameState.LOBBY

# Relay server settings (for join codes)
# You can replace this with your own relay service or use a third-party service
const RELAY_SERVER_URL = "wss://your-relay-server.com"  # Replace with actual relay server
var relay_connection: WebSocketPeer

# Player spawn points
var spawn_points: Array[Vector3] = []
var next_spawn_index: int = 0

func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Set default spawn points (you can customize these)
	spawn_points = [
		Vector3(0, 1, 0),
		Vector3(5, 1, 0),
		Vector3(-5, 1, 0),
		Vector3(0, 1, 5),
		Vector3(0, 1, -5),
		Vector3(5, 1, 5),
		Vector3(-5, 1, -5),
		Vector3(5, 1, -5)
	]

# Host a new game
func host_game(player_name: String = "Host") -> bool:
	local_player_name = player_name
	
	# Create ENet multiplayer peer
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(DEFAULT_PORT, MAX_PLAYERS)
	
	if error != OK:
		print("Failed to create server: ", error)
		connection_failed.emit("Failed to create server")
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = true
	
	# Generate join code
	_generate_join_code()
	
	print("Server started on port ", DEFAULT_PORT)
	hosting_started.emit()
	return true

# Join a game using a join code
func join_game(join_code: String, player_name: String = "Player") -> bool:
	local_player_name = player_name
	
	# For now, we'll use a simple approach where the join code contains the IP:PORT
	# In a production system, you'd resolve this through a relay server
	var connection_info = _resolve_join_code(join_code)
	if connection_info.is_empty():
		connection_failed.emit("Invalid join code")
		return false
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(connection_info.ip, connection_info.port)
	
	if error != OK:
		print("Failed to create client: ", error)
		connection_failed.emit("Failed to connect to server")
		return false
	
	multiplayer.multiplayer_peer = peer
	is_hosting = false
	
	print("Attempting to connect to ", connection_info.ip, ":", connection_info.port)
	return true

# Disconnect from current game
func disconnect_from_game():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	is_hosting = false
	current_join_code = ""
	connected_players.clear()
	current_game_state = GameState.LOBBY
	print("Disconnected from game")

# Get the current join code
func get_join_code() -> String:
	return current_join_code

# Get connected player count
func get_player_count() -> int:
	return connected_players.size() + 1  # +1 for local player

# Get next spawn position
func get_next_spawn_position() -> Vector3:
	if spawn_points.is_empty():
		return Vector3.ZERO
	
	var pos = spawn_points[next_spawn_index]
	next_spawn_index = (next_spawn_index + 1) % spawn_points.size()
	return pos

# Add custom spawn points
func add_spawn_point(position: Vector3):
	spawn_points.append(position)

func clear_spawn_points():
	spawn_points.clear()
	next_spawn_index = 0

# Private methods

func _generate_join_code():
	# Simple join code generation - in production, use a proper relay service
	# For now, we'll create a code based on local IP and port
	var local_ip = _get_local_ip()
	current_join_code = _encode_connection_info(local_ip, DEFAULT_PORT)
	join_code_generated.emit(current_join_code)
	print("Join code generated: ", current_join_code)

func _get_local_ip() -> String:
	# Get the local IP address
	var addresses = IP.get_local_addresses()
	for address in addresses:
		# Skip localhost and IPv6 addresses for simplicity
		if not address.begins_with("127.") and not address.contains(":"):
			return address
	return "127.0.0.1"  # Fallback to localhost

func _encode_connection_info(ip: String, port: int) -> String:
	# Simple encoding using base64 - more reliable than compression for short strings
	var info = ip + ":" + str(port)
	var encoded = Marshalls.utf8_to_base64(info)
	# Add some random padding to make codes look more "game-like"
	var random_suffix = str(randi() % 1000).pad_zeros(3)
	return encoded + random_suffix

func _resolve_join_code(join_code: String) -> Dictionary:
	# Simple decoding - remove the random suffix and decode
	if join_code.length() < 4:
		return {}

	var encoded_part = join_code.substr(0, join_code.length() - 3)
	var decoded = Marshalls.base64_to_utf8(encoded_part)

	if decoded.is_empty():
		return {}

	var parts = decoded.split(":")
	if parts.size() != 2:
		return {}

	return {
		"ip": parts[0],
		"port": int(parts[1])
	}

# Signal handlers

func _on_peer_connected(peer_id: int):
	print("Player connected: ", peer_id)
	connected_players[peer_id] = {
		"name": "Player" + str(peer_id),
		"ready": false
	}

	# If we're the server and game is in progress, notify the new player
	if is_server() and current_game_state != GameState.LOBBY:
		_rpc_sync_game_state.rpc_id(peer_id, current_game_state)

	player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int):
	print("Player disconnected: ", peer_id)
	if peer_id in connected_players:
		connected_players.erase(peer_id)
	player_disconnected.emit(peer_id)

func _on_connection_failed():
	print("Connection failed")
	connection_failed.emit("Connection failed")

func _on_connected_to_server():
	print("Connected to server")
	joined_game.emit()

func _on_server_disconnected():
	print("Server disconnected")
	disconnect_from_game()

# RPC methods for player management

@rpc("any_peer", "call_local", "reliable")
func register_player(peer_id: int, player_name: String):
	if peer_id in connected_players:
		connected_players[peer_id]["name"] = player_name
	print("Player registered: ", player_name, " (", peer_id, ")")

@rpc("any_peer", "call_local", "reliable")
func player_ready(peer_id: int):
	if peer_id in connected_players:
		connected_players[peer_id]["ready"] = true
	print("Player ready: ", peer_id)

# Utility methods

func is_server() -> bool:
	return multiplayer.is_server()

func get_local_peer_id() -> int:
	return multiplayer.get_unique_id()

func get_connected_peer_ids() -> Array:
	return connected_players.keys()

# Game state management
func set_game_state(new_state: GameState):
	current_game_state = new_state
	print("Game state changed to: ", GameState.keys()[new_state])

func get_game_state() -> GameState:
	return current_game_state

func is_game_in_progress() -> bool:
	return current_game_state == GameState.IN_GAME

func is_game_starting() -> bool:
	return current_game_state == GameState.STARTING

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_game_state(game_state: GameState):
	# Called on clients to sync game state from server
	current_game_state = game_state
	print("Game state synced from server: ", GameState.keys()[game_state])
