extends Node3D
class_name NetworkedEntity

## Base class for entities that participate in network state replication
## Implements capture_network_state() and apply_network_state() for automatic sync

# --- Network Configuration ---
@export var replicate_position: bool = true
@export var replicate_rotation: bool = true
@export var replicate_velocity: bool = false
@export var network_priority: float = 1.0

# --- Network State ---
var network_entity_id: int = -1
var is_locally_controlled: bool = false

# --- Interpolation ---
@export var enable_interpolation: bool = true
@export var interpolation_speed: float = 10.0

var interpolation_target_position: Vector3 = Vector3.ZERO
var interpolation_target_rotation: Vector3 = Vector3.ZERO
var has_interpolation_target: bool = false

# --- Velocity Tracking ---
var velocity: Vector3 = Vector3.ZERO
var last_position: Vector3 = Vector3.ZERO

# --- State History (for lag compensation) ---
var state_history: Array[Dictionary] = []
var max_state_history: int = 32

signal network_state_changed(state: Dictionary)

func _ready() -> void:
	last_position = global_position
	
	# Auto-register with StateReplicationManager if available
	if MultiplayerManager and MultiplayerManager.is_server():
		call_deferred("_register_with_replication_manager")

func _process(delta: float) -> void:
	# Update velocity tracking
	_update_velocity(delta)
	
	# Apply interpolation if not locally controlled
	if not is_locally_controlled and enable_interpolation and has_interpolation_target:
		_apply_interpolation(delta)
	
	# Store state history on server
	if MultiplayerManager and MultiplayerManager.is_server():
		_store_state_history()

## Register this entity with the state replication manager
func _register_with_replication_manager() -> void:
	var replication_manager = get_node_or_null("/root/StateReplicationManager")
	if not replication_manager:
		return
	
	network_entity_id = replication_manager.register_entity(self)
	print("[NetworkedEntity] Registered %s with ID %d" % [name, network_entity_id])

## Unregister from replication manager
func _unregister_from_replication_manager() -> void:
	var replication_manager = get_node_or_null("/root/StateReplicationManager")
	if replication_manager and network_entity_id != -1:
		replication_manager.unregister_entity(network_entity_id)
		network_entity_id = -1

## Capture current state for network replication
func capture_network_state() -> Dictionary:
	var state = {}
	
	# Basic transform
	if replicate_position:
		state["position"] = global_position
	
	if replicate_rotation:
		state["rotation"] = global_rotation
	
	# Velocity for prediction
	if replicate_velocity:
		state["velocity"] = velocity
	
	# Custom state from derived classes
	var custom_state = _capture_custom_state()
	state.merge(custom_state, true)
	
	return state

## Apply received state from network
func apply_network_state(state: Dictionary) -> void:
	# Don't apply state if locally controlled
	if is_locally_controlled:
		return
	
	# Apply position with interpolation
	if "position" in state and replicate_position:
		var new_position = state["position"]
		if enable_interpolation:
			interpolation_target_position = new_position
			has_interpolation_target = true
		else:
			global_position = new_position
	
	# Apply rotation with interpolation
	if "rotation" in state and replicate_rotation:
		var new_rotation = state["rotation"]
		if enable_interpolation:
			interpolation_target_rotation = new_rotation
		else:
			global_rotation = new_rotation
	
	# Apply velocity
	if "velocity" in state and replicate_velocity:
		velocity = state["velocity"]
	
	# Apply custom state
	_apply_custom_state(state)
	
	network_state_changed.emit(state)

## Override in derived classes to capture custom state
func _capture_custom_state() -> Dictionary:
	return {}

## Override in derived classes to apply custom state
func _apply_custom_state(_state: Dictionary) -> void:
	pass

## Update velocity tracking
func _update_velocity(delta: float) -> void:
	if delta > 0:
		velocity = (global_position - last_position) / delta
		last_position = global_position

## Apply interpolation to smooth out network updates
func _apply_interpolation(delta: float) -> void:
	if not has_interpolation_target:
		return
	
	# Interpolate position
	if replicate_position:
		global_position = global_position.lerp(interpolation_target_position, interpolation_speed * delta)
		
		# Stop interpolation when close enough
		if global_position.distance_to(interpolation_target_position) < 0.01:
			global_position = interpolation_target_position
			has_interpolation_target = false
	
	# Interpolate rotation
	if replicate_rotation:
		global_rotation = global_rotation.lerp(interpolation_target_rotation, interpolation_speed * delta)

## Store state in history for lag compensation
func _store_state_history() -> void:
	var state = capture_network_state()
	state["timestamp"] = Time.get_unix_time_from_system()
	
	state_history.append(state)
	
	# Limit history size
	if state_history.size() > max_state_history:
		state_history.pop_front()

## Get historical state at a specific time (for lag compensation)
func get_state_at_time(timestamp: float) -> Dictionary:
	if state_history.is_empty():
		return capture_network_state()
	
	# Find closest states before and after the timestamp
	var before_state: Dictionary = {}
	var after_state: Dictionary = {}
	
	for state in state_history:
		var state_time = state.get("timestamp", 0.0)
		
		if state_time <= timestamp:
			before_state = state
		elif state_time > timestamp and after_state.is_empty():
			after_state = state
			break
	
	# If we have both states, interpolate
	if not before_state.is_empty() and not after_state.is_empty():
		return _interpolate_states(before_state, after_state, timestamp)
	elif not before_state.is_empty():
		return before_state
	elif not after_state.is_empty():
		return after_state
	else:
		return capture_network_state()

## Interpolate between two states based on timestamp
func _interpolate_states(state_a: Dictionary, state_b: Dictionary, target_time: float) -> Dictionary:
	var time_a = state_a.get("timestamp", 0.0)
	var time_b = state_b.get("timestamp", 0.0)
	
	if time_b == time_a:
		return state_a
	
	var t = (target_time - time_a) / (time_b - time_a)
	t = clamp(t, 0.0, 1.0)
	
	var interpolated_state = {}
	
	# Interpolate position
	if "position" in state_a and "position" in state_b:
		var pos_a: Vector3 = state_a["position"]
		var pos_b: Vector3 = state_b["position"]
		interpolated_state["position"] = pos_a.lerp(pos_b, t)
	
	# Interpolate rotation
	if "rotation" in state_a and "rotation" in state_b:
		var rot_a: Vector3 = state_a["rotation"]
		var rot_b: Vector3 = state_b["rotation"]
		interpolated_state["rotation"] = rot_a.lerp(rot_b, t)
	
	# Interpolate velocity
	if "velocity" in state_a and "velocity" in state_b:
		var vel_a: Vector3 = state_a["velocity"]
		var vel_b: Vector3 = state_b["velocity"]
		interpolated_state["velocity"] = vel_a.lerp(vel_b, t)
	
	interpolated_state["timestamp"] = target_time
	
	return interpolated_state

## Get network priority for update ordering
func get_network_priority() -> float:
	return network_priority

## Get velocity for priority calculations
func get_velocity() -> Vector3:
	return velocity

## Get peer ID (override in player entities)
func get_peer_id() -> int:
	return -1

## Set whether this entity is locally controlled
func set_locally_controlled(controlled: bool) -> void:
	is_locally_controlled = controlled

## Rewind entity to a specific time (for server-side lag compensation)
func rewind_to_time(timestamp: float) -> Dictionary:
	# Get state at that time
	var historical_state = get_state_at_time(timestamp)
	
	# Store current state for restoration
	var current_state = capture_network_state()
	
	# Apply historical state
	apply_network_state(historical_state)
	
	return current_state

## Restore entity to a saved state
func restore_state(state: Dictionary) -> void:
	apply_network_state(state)

func _exit_tree() -> void:
	_unregister_from_replication_manager()

# --- Utility Functions ---

## Force a state update to all clients (server only)
func force_network_update() -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	var replication_manager = get_node_or_null("/root/StateReplicationManager")
	if replication_manager:
		# This will be picked up in the next snapshot
		pass

## Teleport without interpolation
func teleport(new_position: Vector3) -> void:
	global_position = new_position
	last_position = new_position
	interpolation_target_position = new_position
	velocity = Vector3.ZERO
	has_interpolation_target = false

## Predict movement for client-side prediction
func predict_movement(delta: float) -> void:
	if velocity.length() > 0.01:
		global_position += velocity * delta

