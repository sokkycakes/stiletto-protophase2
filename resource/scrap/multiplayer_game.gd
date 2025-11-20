extends Node3D

# Player scene to spawn
const PLAYER_SCENE = preload("res://resource/entities/player/ss_player_multiplayerv2.tscn")

# Node references
@onready var players_container = $Players
@onready var spawn_points_container = $SpawnPoints
@onready var multiplayer_spawner = $MultiplayerSpawner

# Spawn management
var spawn_points: Array[Vector3] = []
var used_spawn_points: Array[bool] = []

func _ready():
	# Collect spawn points
	_collect_spawn_points()

	# Setup multiplayer spawner
	multiplayer_spawner.spawn_function = _spawn_player

	# Connect multiplayer signals
	if MultiplayerManager:
		MultiplayerManager.player_connected.connect(_on_player_connected)
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

	# Wait a frame to ensure all nodes are ready
	await get_tree().process_frame

	# Spawn local player
	_spawn_local_player()

	# If we're the server, spawn players for already connected peers
	if multiplayer.is_server():
		print("=== SERVER SPAWNING REMOTE PLAYERS ===")

		# Notify all clients that the game has started (for late joiners)
		_rpc_game_started.rpc()

		# CRITICAL: Spawn the host (server) as a remote player for all clients
		var server_peer_id = 1  # Server is always peer 1
		print("Spawning server (peer 1) as remote player for all clients")
		_rpc_spawn_player.rpc(server_peer_id)

		# Spawn existing connected players
		var connected_peers = MultiplayerManager.get_connected_peer_ids()
		print("Connected peers to spawn: ", connected_peers)
		for peer_id in connected_peers:
			print("Spawning remote player for peer: ", peer_id)
			_spawn_player_for_peer(peer_id)

		print("======================================")
		
		if GameRulesManager:
			GameRulesManager.start_match()

	print("Multiplayer game scene loaded for peer: ", multiplayer.get_unique_id())

	# Debug: List all players after spawning
	await get_tree().create_timer(1.0).timeout
	_debug_list_all_players()

@rpc("authority", "call_local", "reliable")
func _rpc_game_started():
	# Called on all clients when the game starts
	print("Game started notification received")

func _collect_spawn_points():
	spawn_points.clear()
	used_spawn_points.clear()
	
	for child in spawn_points_container.get_children():
		if child is Marker3D:
			spawn_points.append(child.global_position)
			used_spawn_points.append(false)
	
	# Update MultiplayerManager with spawn points
	if MultiplayerManager:
		MultiplayerManager.clear_spawn_points()
		for point in spawn_points:
			MultiplayerManager.add_spawn_point(point)

func _get_next_spawn_point() -> Vector3:
	# Find first unused spawn point
	for i in range(spawn_points.size()):
		if not used_spawn_points[i]:
			used_spawn_points[i] = true
			return spawn_points[i]

	# If all spawn points are used, use a random one
	if spawn_points.size() > 0:
		var index = randi() % spawn_points.size()
		return spawn_points[index]

	return Vector3.ZERO

func _get_spawn_point_for_peer(peer_id: int) -> Vector3:
	# Deterministic spawn point allocation based on peer ID
	# This ensures each peer gets the same spawn point on all clients
	if spawn_points.size() == 0:
		print("WARNING: No spawn points available!")
		return Vector3.ZERO

	# Get all peer IDs (including server and clients)
	var all_peer_ids = []

	# Always add server peer ID (1)
	all_peer_ids.append(1)

	# Add all connected client peer IDs
	if MultiplayerManager:
		var connected_peers = MultiplayerManager.get_connected_peer_ids()
		for connected_peer_id in connected_peers:
			if connected_peer_id not in all_peer_ids:
				all_peer_ids.append(connected_peer_id)

		# If we're a client, ensure our own peer ID is included
		if not multiplayer.is_server():
			var local_peer_id = multiplayer.get_unique_id()
			if local_peer_id not in all_peer_ids:
				all_peer_ids.append(local_peer_id)

	# Sort for consistency across all clients
	all_peer_ids.sort()

	print("Spawn point allocation - All peer IDs: ", all_peer_ids, " Target peer: ", peer_id)

	# Find the index of this peer in the sorted list
	var peer_index = all_peer_ids.find(peer_id)
	if peer_index == -1:
		print("WARNING: Peer ID ", peer_id, " not found in peer list, using index 0")
		peer_index = 0  # Fallback

	# Use modulo to wrap around if more players than spawn points
	var spawn_index = peer_index % spawn_points.size()
	var spawn_pos = spawn_points[spawn_index]

	print("Peer ", peer_id, " assigned spawn index ", spawn_index, " at position ", spawn_pos)
	return spawn_pos

func _free_spawn_point(position: Vector3):
	# Mark spawn point as free
	for i in range(spawn_points.size()):
		if spawn_points[i].distance_to(position) < 1.0:
			used_spawn_points[i] = false
			break

func _spawn_local_player():
	var local_peer_id = multiplayer.get_unique_id()
	print("=== SPAWNING LOCAL PLAYER ===")
	print("Local peer ID: ", local_peer_id)
	print("Is server: ", multiplayer.is_server())

	var spawn_pos = _get_spawn_point_for_peer(local_peer_id)
	var player = PLAYER_SCENE.instantiate()

	# Set player properties
	player.name = "Player_" + str(local_peer_id)
	player.position = spawn_pos

	# CRITICAL: Set authority for local player
	player.set_multiplayer_authority(local_peer_id)

	# Add to scene
	players_container.add_child(player)

	print("LOCAL PLAYER SPAWNED:")
	print("  Name: ", player.name)
	print("  Position: ", spawn_pos)
	print("  Authority: ", player.get_multiplayer_authority())
	print("===============================")

func _spawn_player_for_peer(peer_id: int):
	if not multiplayer.is_server():
		return
	
	# Call RPC to spawn player on all clients
	_rpc_spawn_player.rpc(peer_id)

func _spawn_player(data: Dictionary) -> Node:
	var peer_id = data.get("peer_id", 1)
	var spawn_pos = data.get("position", Vector3.ZERO)

	var player = PLAYER_SCENE.instantiate()
	player.name = "Player_" + str(peer_id)
	player.position = spawn_pos

	# CRITICAL: Set multiplayer authority BEFORE adding to scene
	player.set_multiplayer_authority(peer_id)

	print("Player created for peer ", peer_id, " with authority: ", player.get_multiplayer_authority())
	return player

@rpc("authority", "call_local", "reliable")
func _rpc_spawn_player(peer_id: int):
	print("=== SPAWNING REMOTE PLAYER VIA RPC ===")
	print("Target peer ID: ", peer_id)
	print("Local peer ID: ", multiplayer.get_unique_id())
	print("Is server: ", multiplayer.is_server())

	# Don't spawn ourselves as a remote player - we already have a local player
	if peer_id == multiplayer.get_unique_id():
		print("Skipping spawn - this is our local player")
		return

	# Check if player already exists
	var existing_player = players_container.get_node_or_null("Player_" + str(peer_id))
	if existing_player:
		print("Player already exists, skipping spawn")
		return

	var spawn_pos = _get_spawn_point_for_peer(peer_id)

	var spawn_data = {
		"peer_id": peer_id,
		"position": spawn_pos
	}

	var player = _spawn_player(spawn_data)
	players_container.add_child(player)

	print("REMOTE PLAYER SPAWNED:")
	print("  Name: ", player.name)
	print("  Position: ", spawn_pos)
	print("  Authority: ", player.get_multiplayer_authority())
	print("======================================")

@rpc("authority", "call_local", "reliable")
func _rpc_despawn_player(peer_id: int):
	var player_name = "Player_" + str(peer_id)
	var player = players_container.get_node_or_null(player_name)
	
	if player:
		# Free the spawn point
		_free_spawn_point(player.position)
		player.queue_free()
		print("Player despawned for peer ", peer_id)

# Signal handlers

func _on_player_connected(peer_id: int):
	if multiplayer.is_server():
		print("Player connected during game: ", peer_id)

		# Small delay to ensure the new player's scene is ready
		await get_tree().create_timer(0.5).timeout

		# CRITICAL: Spawn the host (server) for the new client
		var server_peer_id = 1  # Server is always peer 1
		_rpc_spawn_player.rpc_id(peer_id, server_peer_id)

		# Spawn the new client for all existing players
		_spawn_player_for_peer(peer_id)

		# Spawn all existing clients for the new player
		for existing_peer_id in MultiplayerManager.get_connected_peer_ids():
			if existing_peer_id != peer_id:  # Don't spawn the new player for themselves
				_rpc_spawn_player.rpc_id(peer_id, existing_peer_id)

		# Notify the new player that the game is active
		_rpc_game_started.rpc_id(peer_id)

func _on_player_disconnected(peer_id: int):
	if multiplayer.is_server():
		# Despawn player
		_rpc_despawn_player.rpc(peer_id)

# Input handling - Removed direct ui_cancel handling to allow pause menu to work
# The pause menu (autoload singleton) will handle ui_cancel input via _unhandled_input()

func _return_to_menu():
	# Called by pause menu when "Return to Title" is pressed
	# Restore mouse visibility for menu navigation
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Disconnect from multiplayer
	if MultiplayerManager:
		MultiplayerManager.disconnect_from_game()

	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")

# Debug function to list all players and their properties
func _debug_list_all_players():
	print("=== DEBUG: ALL PLAYERS ===")
	print("Local peer ID: ", multiplayer.get_unique_id())
	print("Is server: ", multiplayer.is_server())
	print("Connected peers: ", MultiplayerManager.get_connected_peer_ids() if MultiplayerManager else "No MultiplayerManager")
	print("Players in scene (", players_container.get_child_count(), " total):")

	var local_count = 0
	var remote_count = 0

	for child in players_container.get_children():
		if child.name.begins_with("Player_"):
			var authority = child.get_multiplayer_authority()
			var networked_script = child.get_node_or_null("NetworkedPlayerScript")
			var is_local = false
			if networked_script and networked_script.has_method("is_local"):
				is_local = networked_script.is_local()

			if is_local:
				local_count += 1
			else:
				remote_count += 1

			print("  - ", child.name, ":")
			print("    Position: ", child.position)
			print("    Authority: ", authority)
			print("    Is Local: ", is_local)
			print("    Visible: ", child.visible)

			# Check if player mesh is visible
			var player_mesh = child.get_node_or_null("Body/PlayerMesh")
			if player_mesh:
				print("    Player Mesh Visible: ", player_mesh.visible)

	print("Summary: ", local_count, " local, ", remote_count, " remote players")
	print("==========================")
