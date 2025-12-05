extends Node
class_name StateReplicationManager

## State Replication Manager - Source Engine-inspired networking
## Handles entity state synchronization with delta compression and priority updates

# --- Configuration ---
@export var snapshot_rate: float = 60.0  # Snapshots per second (Source uses 20-66, competitive uses 60-66)
@export var max_snapshot_history: int = 64  # Keep last 64 snapshots for delta calculation
@export var enable_delta_compression: bool = true
@export var enable_priority_updates: bool = true
@export var interpolation_delay: float = 0.1  # Client interpolation buffer
@export var debug_logging: bool = false

# --- State ---
var registered_entities: Dictionary = {}  # entity_id -> NetworkedEntity
var snapshot_history: Array[NetworkStateSnapshot] = []
var current_snapshot_id: int = 0
var client_baselines: Dictionary = {}  # peer_id -> snapshot_id (last acked snapshot)
var disconnected_peers: Array[int] = []  # Track peers we know are disconnected to avoid sending RPCs

# --- Update Management ---
var snapshot_timer: Timer
var next_entity_id: int = 1000  # Start from 1000, below reserved for special entities

# --- Bandwidth Tracking ---
var bytes_sent_this_second: int = 0
var bandwidth_limit: int = 128000  # 128 KB/s default
var bandwidth_timer: Timer

# --- Priority System ---
var entity_priorities: Dictionary = {}  # entity_id -> priority_score
var update_buckets: Dictionary = {}  # bucket_index -> [entity_ids]

signal entity_registered(entity_id: int, entity: Node)
signal entity_unregistered(entity_id: int)
signal snapshot_sent(snapshot_id: int, size_bytes: int)
signal baseline_sent_to_peer(peer_id: int, snapshot_id: int)

func _ready() -> void:
	# Setup snapshot timer
	snapshot_timer = Timer.new()
	snapshot_timer.wait_time = 1.0 / snapshot_rate
	snapshot_timer.timeout.connect(_on_snapshot_timer_timeout)
	add_child(snapshot_timer)
	
	# Setup bandwidth tracking timer
	bandwidth_timer = Timer.new()
	bandwidth_timer.wait_time = 1.0
	bandwidth_timer.timeout.connect(_reset_bandwidth_counter)
	add_child(bandwidth_timer)
	
	# Connect to multiplayer disconnect signals for cleanup
	if MultiplayerManager:
		MultiplayerManager.player_disconnected.connect(_on_player_disconnected)
		MultiplayerManager.player_connected.connect(_on_player_reconnected)
	
	# Also connect to engine-level peer disconnect
	if multiplayer:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	# Only server sends snapshots
	if MultiplayerManager and MultiplayerManager.is_server():
		snapshot_timer.start()
		bandwidth_timer.start()
	
	# Connect to scene tree exit to stop sending when scene is destroyed
	if get_tree():
		get_tree().node_removed.connect(_on_node_removed)

func _exit_tree() -> void:
	# Stop timers when exiting scene tree
	if snapshot_timer:
		snapshot_timer.stop()
	if bandwidth_timer:
		bandwidth_timer.stop()

func _on_node_removed(node: Node) -> void:
	# If our parent (GameWorldStateSync) or GameWorld is being removed, stop sending
	if node == get_parent() or (get_parent() and node == get_parent().get_parent()):
		if snapshot_timer:
			snapshot_timer.stop()
		if bandwidth_timer:
			bandwidth_timer.stop()

# --- Entity Registration ---

## Register an entity for network replication
func register_entity(entity: Node, entity_id: int = -1) -> int:
	if entity_id == -1:
		entity_id = _generate_entity_id()
	
	if entity_id in registered_entities:
		push_warning("[StateReplicationManager] Entity ID %d already registered" % entity_id)
		return entity_id
	
	registered_entities[entity_id] = entity
	entity_priorities[entity_id] = 1.0  # Default priority
	
	if debug_logging:
		print("[StateReplicationManager] Registered entity %d: %s" % [entity_id, entity.name])
	entity_registered.emit(entity_id, entity)
	
	return entity_id

## Unregister an entity from replication
func unregister_entity(entity_id: int) -> void:
	if entity_id not in registered_entities:
		return
	
	registered_entities.erase(entity_id)
	entity_priorities.erase(entity_id)
	
	entity_unregistered.emit(entity_id)
	if debug_logging:
		print("[StateReplicationManager] Unregistered entity %d" % entity_id)

## Get registered entity by ID
func get_entity(entity_id: int) -> Node:
	return registered_entities.get(entity_id, null)

## Generate unique entity ID
func _generate_entity_id() -> int:
	var id = next_entity_id
	next_entity_id += 1
	return id

# --- Snapshot Generation ---

## Create snapshot of all registered entities
func create_snapshot(type: NetworkStateSnapshot.StateType = NetworkStateSnapshot.StateType.BASELINE) -> NetworkStateSnapshot:
	current_snapshot_id += 1
	var snapshot = NetworkStateSnapshot.create_snapshot(current_snapshot_id, type)
	
	# Capture state of all registered entities
	for entity_id in registered_entities:
		var entity = registered_entities[entity_id]
		
		if not is_instance_valid(entity):
			continue
		
		var state = _capture_entity_state(entity)
		if not state.is_empty():
			snapshot.add_entity_state(entity_id, state)
	
	# Store in history
	snapshot_history.append(snapshot)
	
	# Limit history size
	if snapshot_history.size() > max_snapshot_history:
		snapshot_history.pop_front()
	
	return snapshot

## Capture state from an entity
func _capture_entity_state(entity: Node) -> Dictionary:
	var state = {}
	
	# Check if entity has custom state capture method
	if entity.has_method("capture_network_state"):
		state = entity.capture_network_state()
	else:
		# Default state capture
		if entity is Node3D:
			state["position"] = entity.global_position
			state["rotation"] = entity.global_rotation
	
	# Always include entity type for reconstruction
	state["type"] = entity.get_class()
	state["scene_path"] = entity.scene_file_path if entity.scene_file_path else ""
	
	return state

## Apply state to an entity
func _apply_entity_state(entity: Node, state: Dictionary) -> void:
	if entity.has_method("apply_network_state"):
		entity.apply_network_state(state)
	else:
		# Default state application
		if entity is Node3D:
			if "position" in state:
				entity.global_position = state["position"]
			if "rotation" in state:
				entity.global_rotation = state["rotation"]

# --- Server: Snapshot Distribution ---

func _on_snapshot_timer_timeout() -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	# Skip if no entities are registered (e.g., during character select)
	if registered_entities.is_empty():
		return
	
	# Verify we're still in a valid scene tree
	if not is_inside_tree():
		return
	
	# Verify multiplayer is still active
	if not multiplayer.has_multiplayer_peer():
		return
	
	# Get all connected peers - use a fresh check each time
	var peers = MultiplayerManager.get_connected_players().keys()
	var local_peer_id = multiplayer.get_unique_id()
	
	# If no remote peers, stop sending snapshots
	if peers.size() <= 1:  # Only server or no peers
		return
	
	# Build list of valid peers to send to (double-check each one)
	var valid_peers: Array[int] = []
	for peer_id in peers:
		# Skip server's own peer ID (peer ID 1 is always the server)
		if peer_id == local_peer_id or peer_id == 1:
			continue
		
		# Skip peers we know are disconnected
		if peer_id in disconnected_peers:
			continue
		
		# Verify peer is still in multiplayer system
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.has_method("has_peer"):
			if not multiplayer.multiplayer_peer.has_peer(peer_id):
				# Peer disconnected, clean up immediately
				_cleanup_disconnected_peer(peer_id)
				continue
		
		# Also check if peer is still in connected_players (defensive)
		if peer_id not in MultiplayerManager.get_connected_players():
			_cleanup_disconnected_peer(peer_id)
			continue
		
		valid_peers.append(peer_id)
	
	# Send to valid peers only
	for peer_id in valid_peers:
		_send_snapshot_to_peer(peer_id)

## Send appropriate snapshot to a specific peer
func _send_snapshot_to_peer(peer_id: int) -> void:
	# Skip local peer (server doesn't need to send snapshots to itself)
	var local_peer_id = multiplayer.get_unique_id()
	if peer_id == local_peer_id or peer_id == 1:
		return
	
	# Verify peer is still connected before sending RPC
	if not multiplayer.has_multiplayer_peer():
		return
	
	# Check if peer still exists in connected players list
	if MultiplayerManager:
		var connected_peers = MultiplayerManager.get_connected_players()
		if peer_id not in connected_peers:
			# Peer disconnected, clean up
			_cleanup_disconnected_peer(peer_id)
			return
	
	# Also check if peer exists in the multiplayer system (if available)
	if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.has_method("has_peer"):
		if not multiplayer.multiplayer_peer.has_peer(peer_id):
			# Peer disconnected, clean up
			_cleanup_disconnected_peer(peer_id)
			return
	
	# Skip if no entities registered
	if registered_entities.is_empty():
		return

	# Check bandwidth limit
	if bytes_sent_this_second >= bandwidth_limit:
		return  # Skip this update to stay under bandwidth limit
	
	var baseline_id = client_baselines.get(peer_id, -1)
	var snapshot: NetworkStateSnapshot
	
	if baseline_id == -1 or not enable_delta_compression:
		# Send full baseline snapshot
		snapshot = create_snapshot(NetworkStateSnapshot.StateType.BASELINE)
		client_baselines[peer_id] = snapshot.snapshot_id
		baseline_sent_to_peer.emit(peer_id, snapshot.snapshot_id)
	else:
		# Send delta snapshot
		var current_snapshot = create_snapshot(NetworkStateSnapshot.StateType.BASELINE)
		var baseline = _get_snapshot_by_id(baseline_id)
		
		if baseline:
			snapshot = current_snapshot.calculate_delta(baseline)
		else:
			# Baseline not found, send full snapshot
			snapshot = current_snapshot
			client_baselines[peer_id] = snapshot.snapshot_id
	
	# Apply priority filtering if enabled
	if enable_priority_updates:
		snapshot = _apply_priority_filtering(snapshot, peer_id)
	
	# Serialize and send
	var snapshot_data = snapshot.serialize()
	var estimated_size = snapshot.get_estimated_size()
	
	# Final verification before sending RPC - check multiple sources
	# This prevents sending to peers whose scenes have been destroyed
	
	# 0. Check our disconnected peers list first (fastest check)
	if peer_id in disconnected_peers:
		return
	
	# 1. Check MultiplayerManager's connected players list
	if MultiplayerManager:
		var connected_peers = MultiplayerManager.get_connected_players()
		if peer_id not in connected_peers:
			_cleanup_disconnected_peer(peer_id)
			return
	
	# 2. Verify multiplayer peer still exists
	if not multiplayer.has_multiplayer_peer():
		return
	
	# 3. Check if peer exists in multiplayer system
	if multiplayer.multiplayer_peer:
		if multiplayer.multiplayer_peer.has_method("has_peer"):
			if not multiplayer.multiplayer_peer.has_peer(peer_id):
				_cleanup_disconnected_peer(peer_id)
				return
		# For ENetMultiplayerPeer, check get_peer() instead
		elif multiplayer.multiplayer_peer.has_method("get_peer"):
			var peer = multiplayer.multiplayer_peer.get_peer(peer_id)
			if not peer or peer.get("connection_status") != 2:  # 2 = CONNECTION_CONNECTED
				_cleanup_disconnected_peer(peer_id)
				return
	
	# 4. Final check: verify we're still in scene tree (defensive)
	if not is_inside_tree():
		return
	
	# All checks passed - send RPC
	# Note: Even with all checks, Godot's RPC system may still try to resolve
	# the node path on the remote peer. If that peer's scene is destroyed,
	# we'll get a warning, but the RPC will fail gracefully.
	_rpc_receive_snapshot.rpc_id(peer_id, snapshot_data)
	
	# Track bandwidth
	bytes_sent_this_second += estimated_size
	snapshot_sent.emit(snapshot.snapshot_id, estimated_size)

## Apply priority-based filtering to snapshot
func _apply_priority_filtering(snapshot: NetworkStateSnapshot, peer_id: int) -> NetworkStateSnapshot:
	# Get peer's player entity for distance calculations
	var peer_entity = _get_peer_entity(peer_id)
	if not peer_entity:
		return snapshot
	
	var filtered_snapshot = NetworkStateSnapshot.create_snapshot(snapshot.snapshot_id, snapshot.state_type)
	filtered_snapshot.timestamp = snapshot.timestamp
	
	# Calculate priorities for all entities
	var entity_priority_list: Array[Dictionary] = []
	
	for entity_id in snapshot.get_entity_ids():
		var entity = _get_valid_entity(entity_id)
		if not entity:
			continue
		
		var priority = _calculate_entity_priority(entity, peer_entity)
		entity_priority_list.append({
			"entity_id": entity_id,
			"priority": priority
		})
	
	# Sort by priority (highest first)
	entity_priority_list.sort_custom(func(a, b): return a["priority"] > b["priority"])
	
	# Include top priority entities (up to bandwidth limit)
	var entities_included = 0
	var max_entities_per_snapshot = 32  # Configurable
	
	for entry in entity_priority_list:
		if entities_included >= max_entities_per_snapshot:
			break
		
		var entity_id = entry["entity_id"]
		var state = snapshot.get_entity_state(entity_id)
		filtered_snapshot.add_entity_state(entity_id, state)
		entities_included += 1
	
	return filtered_snapshot

## Calculate entity update priority for a specific client
func _calculate_entity_priority(entity: Node, viewer: Node) -> float:
	var priority = 1.0
	
	# Distance-based priority
	if entity is Node3D and viewer is Node3D:
		var distance = entity.global_position.distance_to(viewer.global_position)
		var distance_factor = 1.0 / (1.0 + distance * 0.01)  # Closer = higher priority
		priority *= distance_factor
	
	# Custom priority boost
	if entity.has_method("get_network_priority"):
		priority *= entity.get_network_priority()
	
	# Movement-based priority (moving entities get priority)
	if entity.has_method("get_velocity"):
		var velocity = entity.get_velocity()
		if velocity is Vector3:
			var speed = velocity.length()
			priority *= (1.0 + speed * 0.1)
	
	# Always prioritize the viewer's own entity
	if entity == viewer:
		priority *= 10.0
	
	return priority

## Get entity associated with a peer
func _get_peer_entity(peer_id: int) -> Node:
	# This should be implemented by the game
	# For now, search for registered entity with matching peer_id
	for entity_id in registered_entities.keys():
		var entity = _get_valid_entity(entity_id)
		if not entity:
			continue
		if entity.has_method("get_peer_id"):
			if entity.get_peer_id() == peer_id:
				return entity
	return null

## Get entity ensuring it's still valid, prune if freed
func _get_valid_entity(entity_id: int) -> Node:
	if not registered_entities.has(entity_id):
		return null
	var entity = registered_entities[entity_id]
	if not is_instance_valid(entity):
		registered_entities.erase(entity_id)
		entity_priorities.erase(entity_id)
		return null
	return entity

## Get snapshot from history by ID
func _get_snapshot_by_id(snapshot_id: int) -> NetworkStateSnapshot:
	for snapshot in snapshot_history:
		if snapshot.snapshot_id == snapshot_id:
			return snapshot
	return null

## Reset bandwidth counter
func _reset_bandwidth_counter() -> void:
	bytes_sent_this_second = 0

# --- Client: Snapshot Reception ---

@rpc("authority", "call_remote", "unreliable")
func _rpc_receive_snapshot(snapshot_data: Dictionary) -> void:
	# Defensive check: if we're not in the scene tree, ignore the RPC
	# This can happen if the client disconnected and scene was destroyed
	if not is_inside_tree():
		return
	
	var snapshot = NetworkStateSnapshot.deserialize(snapshot_data)
	_apply_snapshot(snapshot)

## Apply received snapshot to entities
func _apply_snapshot(snapshot: NetworkStateSnapshot) -> void:
	# Store snapshot for interpolation
	snapshot_history.append(snapshot)
	
	# Limit history
	if snapshot_history.size() > max_snapshot_history:
		snapshot_history.pop_front()
	
	# Apply states to entities
	for entity_id in snapshot.get_entity_ids():
		var entity = get_entity(entity_id)
		var state = snapshot.get_entity_state(entity_id)
		
		if not entity:
			# Entity doesn't exist yet, need to spawn it
			_spawn_entity_from_state(entity_id, state)
			continue
		
		# Apply state
		_apply_entity_state(entity, state)

## Spawn entity from received state
func _spawn_entity_from_state(entity_id: int, state: Dictionary) -> void:
	# This should be implemented by game-specific logic
	# Emit signal for game to handle spawning
	if debug_logging:
		print("[StateReplicationManager] Need to spawn entity %d with state: %s" % [entity_id, state])

# --- Late Joiner Support ---

## Send full baseline to newly connected peer
func send_baseline_to_peer(peer_id: int) -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
		
	# Skip local peer
	if peer_id == multiplayer.get_unique_id():
		return
	
	# Verify peer is still connected
	var connected_peers = MultiplayerManager.get_connected_players()
	if peer_id not in connected_peers:
		if debug_logging:
			print("[StateReplicationManager] Peer %d not connected, skipping baseline" % peer_id)
		return
	
	if debug_logging:
		print("[StateReplicationManager] Sending baseline to peer %d" % peer_id)
	
	# Create full baseline snapshot
	var baseline = create_snapshot(NetworkStateSnapshot.StateType.BASELINE)
	
	# Mark as this peer's baseline
	client_baselines[peer_id] = baseline.snapshot_id
	
	# Send with reliable RPC
	var snapshot_data = baseline.serialize()
	_rpc_receive_baseline.rpc_id(peer_id, snapshot_data)
	
	baseline_sent_to_peer.emit(peer_id, baseline.snapshot_id)

@rpc("authority", "call_remote", "reliable")
func _rpc_receive_baseline(snapshot_data: Dictionary) -> void:
	# Defensive check: if we're not in the scene tree, ignore the RPC
	# This can happen if the client disconnected and scene was destroyed
	if not is_inside_tree():
		return
	
	if debug_logging:
		print("[StateReplicationManager] Received baseline snapshot")
	var snapshot = NetworkStateSnapshot.deserialize(snapshot_data)
	_apply_snapshot(snapshot)

## Acknowledge snapshot receipt (for reliability)
@rpc("any_peer", "call_remote", "unreliable")
func acknowledge_snapshot(snapshot_id: int) -> void:
	var peer_id = multiplayer.get_remote_sender_id()
	client_baselines[peer_id] = snapshot_id

# --- Utility Functions ---

## Get current snapshot rate
func get_snapshot_rate() -> float:
	return snapshot_rate

## Set snapshot rate dynamically
func set_snapshot_rate(rate: float) -> void:
	snapshot_rate = clamp(rate, 1.0, 128.0)
	snapshot_timer.wait_time = 1.0 / snapshot_rate

## Get bandwidth usage statistics
func get_bandwidth_stats() -> Dictionary:
	return {
		"bytes_sent_this_second": bytes_sent_this_second,
		"bandwidth_limit": bandwidth_limit,
		"utilization": float(bytes_sent_this_second) / float(bandwidth_limit) * 100.0,
		"registered_entities": registered_entities.size(),
		"snapshot_history_size": snapshot_history.size()
	}

## Get entity count
func get_entity_count() -> int:
	return registered_entities.size()

# --- Cleanup for Disconnected Peers ---

## Handle player disconnect from MultiplayerManager
func _on_player_disconnected(peer_id: int) -> void:
	# Clean up immediately and synchronously
	_cleanup_disconnected_peer(peer_id)

## Handle peer disconnect from engine-level multiplayer
func _on_peer_disconnected(peer_id: int) -> void:
	# Clean up immediately and synchronously - this fires before scene cleanup
	_cleanup_disconnected_peer(peer_id)

## Handle player reconnection
func _on_player_reconnected(peer_id: int, _player_info: Dictionary) -> void:
	# Remove from disconnected list if they reconnect
	if peer_id in disconnected_peers:
		disconnected_peers.erase(peer_id)
		if debug_logging:
			print("[StateReplicationManager] Peer %d reconnected, removed from disconnected list" % peer_id)

## Clean up state for a disconnected peer
func _cleanup_disconnected_peer(peer_id: int) -> void:
	# Mark as disconnected immediately to prevent any further RPCs
	if peer_id not in disconnected_peers:
		disconnected_peers.append(peer_id)
	
	# Remove from client baselines immediately
	if peer_id in client_baselines:
		client_baselines.erase(peer_id)
	
	# Unregister any entities associated with this peer
	var entities_to_remove: Array[int] = []
	for entity_id in registered_entities:
		var entity = registered_entities[entity_id]
		if not is_instance_valid(entity):
			entities_to_remove.append(entity_id)
			continue
		
		# Check if entity is a NetworkedPlayer with matching peer_id
		if entity is NetworkedPlayer:
			var player = entity as NetworkedPlayer
			if player.peer_id == peer_id:
				entities_to_remove.append(entity_id)
	
	# Remove entities
	for entity_id in entities_to_remove:
		unregister_entity(entity_id)
	
	if debug_logging:
		print("[StateReplicationManager] Cleaned up disconnected peer: %d" % peer_id)

## Reset state for when scene changes or game ends
func reset_state() -> void:
	"""Clear all state - useful when returning to lobby"""
	registered_entities.clear()
	client_baselines.clear()
	snapshot_history.clear()
	entity_priorities.clear()
	update_buckets.clear()
	current_snapshot_id = 0
	next_entity_id = 1000
	bytes_sent_this_second = 0
	
	if debug_logging:
		print("[StateReplicationManager] State reset")

## Clear all state (for cleanup)
func clear_all_state() -> void:
	registered_entities.clear()
	entity_priorities.clear()
	snapshot_history.clear()
	client_baselines.clear()
	current_snapshot_id = 0
