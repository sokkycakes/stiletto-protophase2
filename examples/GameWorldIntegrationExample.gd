extends Node

## Example: How to integrate State Replication into your existing GameWorld
## This shows the minimal changes needed to add Source Engine-style networking

## STEP 1: Add to your GameWorld.gd _ready() function
## Add this code after line 59 (_collect_spawn_points)

func _ready_with_state_sync() -> void:
	# ... existing _ready code ...
	_collect_spawn_points()
	
	# NEW: Setup state replication system (server only)
	if MultiplayerManager and MultiplayerManager.is_server():
		_setup_state_replication()
	
	# ... rest of existing code ...

func _setup_state_replication() -> void:
	"""Initialize the state replication system"""
	var state_sync = GameWorldStateSync.new()
	state_sync.name = "StateSync"
	state_sync.enable_state_replication = true
	state_sync.snapshot_rate = 20.0
	state_sync.enable_delta_compression = true
	add_child(state_sync)
	
	print("[GameWorld] State replication enabled")

## STEP 2: Modify _spawn_player() to register with state sync
## Replace your existing _spawn_player (line 155) with this enhanced version:

func _spawn_player_with_state_sync(peer_id: int) -> void:
	if peer_id in players:
		return  # Already spawned
	
	var player_info = MultiplayerManager.get_player_info(peer_id)
	var player_name = player_info.get("name", "Player " + str(peer_id))
	var team_id = player_info.get("team", 0)
	
	# Create networked player
	var networked_player = NetworkedPlayer.new()
	networked_player.name = "Player_" + str(peer_id)
	
	# Set spawn position
	var spawn_pos = get_spawn_point_for_player(peer_id)
	networked_player.global_position = spawn_pos
	
	# Wire in character selection if provided
	var chosen_character_path = ""
	if player_info and player_info.has("character_path"):
		chosen_character_path = player_info["character_path"]
	
	var requires_character = _requires_character_selection()
	if chosen_character_path == "" and requires_character:
		print("[GameWorld] Waiting for character selection before spawning peer ", peer_id)
		return
	
	if chosen_character_path != "":
		var character_scene = load(chosen_character_path) as PackedScene
		if character_scene:
			networked_player.pawn_scene = character_scene
			print("[GameWorld] Set pawn_scene to: ", chosen_character_path)
	
	# Initialize player
	networked_player.initialize_player(peer_id, player_name, team_id)
	
	# Add to scene
	if players_container:
		players_container.add_child(networked_player)
	else:
		get_tree().get_root().add_child(networked_player)
	
	players[peer_id] = networked_player
	
	# NEW: Register with state replication
	var state_sync = get_node_or_null("StateSync") as GameWorldStateSync
	if state_sync and MultiplayerManager.is_server():
		state_sync.register_player(networked_player)
	
	# If this is the local player, set up UI connections
	if peer_id == MultiplayerManager.get_local_peer_id():
		local_player = networked_player
		_setup_local_player_ui()
	
	print("Spawned player: ", player_name, " at ", spawn_pos)

## STEP 3: Modify _on_player_connected_to_game() for late joiners
## Replace your existing function (line 280) with this:

func _on_player_connected_to_game_with_state_sync(peer_id: int, _player_info: Dictionary) -> void:
	# Spawn the newly connected player
	_spawn_player(peer_id)
	
	# If we're the server, handle late-joiner synchronization
	if MultiplayerManager.is_server():
		var state_sync = get_node_or_null("StateSync") as GameWorldStateSync
		
		if state_sync:
			# NEW: Use state replication system for late joiners
			# This sends a full baseline snapshot + all player states
			call_deferred("_sync_late_joiner_via_state_system", peer_id, state_sync)
		else:
			# Fallback to original method
			call_deferred("_spawn_existing_players_for_new_client", peer_id)

func _sync_late_joiner_via_state_system(peer_id: int, state_sync: GameWorldStateSync) -> void:
	"""Send full game state to late joiner using state replication"""
	# Wait a bit longer for client to be fully ready
	await get_tree().create_timer(0.5).timeout
	
	# Send baseline snapshot
	state_sync.sync_late_joiner(peer_id)
	
	print("[GameWorld] Late joiner %d synchronized via state replication" % peer_id)

## STEP 4: Modify _on_player_disconnected() to unregister
## Add this to your existing function (line 250):

func _on_player_disconnected_with_state_sync(peer_id: int) -> void:
	if peer_id in players:
		var player = players[peer_id]
		
		# NEW: Unregister from state replication
		var state_sync = get_node_or_null("StateSync") as GameWorldStateSync
		if state_sync and MultiplayerManager.is_server():
			state_sync.unregister_player(player)
		
		player.queue_free()
		players.erase(peer_id)
		print("Removed disconnected player: ", peer_id)

## STEP 5: (Optional) Add debug overlay
## Add this function to display networking stats:

func _process_state_sync_debug(delta: float) -> void:
	# Only update debug UI once per second
	if Engine.get_process_frames() % 60 != 0:
		return
	
	var state_sync = get_node_or_null("StateSync") as GameWorldStateSync
	if not state_sync:
		return
	
	var stats = state_sync.get_bandwidth_stats()
	
	# Update debug label (create one if it doesn't exist)
	var debug_label = $UI/DebugOverlay/StatsLabel as Label
	if debug_label:
		debug_label.text = """
State Replication Stats:
------------------------
Entities: %d
Bandwidth: %d / %d bytes/sec (%.1f%%)
Snapshots in history: %d
""" % [
			stats.get("registered_entities", 0),
			stats.get("bytes_sent_this_second", 0),
			stats.get("bandwidth_limit", 0),
			stats.get("utilization", 0.0),
			stats.get("snapshot_history_size", 0)
		]

## STEP 6: (Optional) Dynamic snapshot rate based on player count
## Add this to optimize bandwidth usage:

func _adjust_snapshot_rate_by_player_count() -> void:
	"""Dynamically adjust snapshot rate based on active player count"""
	var state_sync = get_node_or_null("StateSync") as GameWorldStateSync
	if not state_sync or not MultiplayerManager.is_server():
		return
	
	var player_count = players.size()
	
	if player_count <= 2:
		state_sync.set_snapshot_rate(30.0)  # High rate for 1v1
	elif player_count <= 4:
		state_sync.set_snapshot_rate(25.0)  # Good rate for small games
	elif player_count <= 8:
		state_sync.set_snapshot_rate(20.0)  # Standard rate
	elif player_count <= 16:
		state_sync.set_snapshot_rate(15.0)  # Lower rate for many players
	else:
		state_sync.set_snapshot_rate(12.0)  # Minimum for large games
	
	print("[GameWorld] Adjusted snapshot rate to %.1f Hz for %d players" % [
		state_sync.snapshot_rate, player_count
	])

# Call this in _on_player_connected and _on_player_disconnected:
func _on_player_count_changed() -> void:
	_adjust_snapshot_rate_by_player_count()

## COMPLETE EXAMPLE: Minimal GameWorld modifications
## Copy and paste this into your GameWorld.gd:

"""
# At the top of GameWorld.gd, add:
var state_sync: GameWorldStateSync

# In _ready(), after _collect_spawn_points():
if MultiplayerManager and MultiplayerManager.is_server():
	state_sync = GameWorldStateSync.new()
	state_sync.name = "StateSync"
	add_child(state_sync)

# In _spawn_player(), after adding to scene:
if state_sync and MultiplayerManager.is_server():
	state_sync.register_player(networked_player)

# In _on_player_connected_to_game(), replace existing sync code:
if MultiplayerManager.is_server() and state_sync:
	call_deferred("_sync_late_joiner", peer_id)

func _sync_late_joiner(peer_id: int):
	await get_tree().create_timer(0.5).timeout
	state_sync.sync_late_joiner(peer_id)

# In _on_player_disconnected(), before queue_free():
if state_sync and MultiplayerManager.is_server():
	state_sync.unregister_player(player)
"""

## Testing the Integration

func test_late_joiner_sync() -> void:
	"""
	Testing procedure:
	1. Start a server with 2-3 players
	2. Have them move around and shoot
	3. Connect a new player mid-game
	4. New player should see:
	   - All existing players in correct positions
	   - All players' health states
	   - All players' current weapons
	   - Smooth position updates immediately
	
	Monitor console for:
	- "[GameWorldStateSync] Syncing late joiner: X"
	- "[StateReplicationManager] Registered entity..."
	- "[GameWorldStateSync] Baseline X sent to peer Y"
	"""
	pass

func test_bandwidth_usage() -> void:
	"""
	Testing procedure:
	1. Start server with 8+ players
	2. Monitor bandwidth stats in debug overlay
	3. Should see:
	   - Bandwidth utilization < 80%
	   - Smooth player movement
	   - No lag spikes
	
	Adjust snapshot rate if needed:
	- High bandwidth: Reduce to 15 Hz
	- Jerky movement: Increase to 25 Hz
	"""
	pass

func test_delta_compression() -> void:
	"""
	Testing procedure:
	1. Enable delta compression: state_sync.enable_delta_compression = true
	2. Compare bandwidth with/without delta compression
	3. Should see 30-50% reduction with many static entities
	"""
	pass

