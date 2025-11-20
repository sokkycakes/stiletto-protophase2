extends Node
class_name StateReplicationManager

## State Replication Manager - Source Engine-inspired networking
## Handles entity state synchronization with delta compression and priority updates

# --- Configuration ---
@export var snapshot_rate: float = 20.0  # Snapshots per second (Source uses 20-66)
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
	
	# Only server sends snapshots
	if MultiplayerManager and MultiplayerManager.is_server():
		snapshot_timer.start()
		bandwidth_timer.start()

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
	
	# Get all connected peers
	var peers = MultiplayerManager.get_connected_players().keys()
	
	for peer_id in peers:
		_send_snapshot_to_peer(peer_id)

## Send appropriate snapshot to a specific peer
func _send_snapshot_to_peer(peer_id: int) -> void:
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

## Clear all state (for cleanup)
func clear_all_state() -> void:
	registered_entities.clear()
	entity_priorities.clear()
	snapshot_history.clear()
	client_baselines.clear()
	current_snapshot_id = 0
