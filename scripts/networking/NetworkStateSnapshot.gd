class_name NetworkStateSnapshot
extends Resource

## Network State Snapshot System
## Captures and applies entity states for synchronization, similar to Source Engine's snapshot system

# --- Snapshot Data ---
var snapshot_id: int = 0
var timestamp: float = 0.0
var entity_states: Dictionary = {}  # entity_id -> state_data

# --- State Types ---
enum StateType {
	BASELINE,    # Full state snapshot (for new connections)
	DELTA,       # Only changed properties
	COMPRESSED   # Delta with compression
}

var state_type: StateType = StateType.BASELINE

## Create a new snapshot
static func create_snapshot(snapshot_id_val: int, type: StateType = StateType.BASELINE) -> NetworkStateSnapshot:
	var snapshot = NetworkStateSnapshot.new()
	snapshot.snapshot_id = snapshot_id_val
	snapshot.timestamp = Time.get_unix_time_from_system()
	snapshot.state_type = type
	return snapshot

## Add entity state to snapshot
func add_entity_state(entity_id: int, state_data: Dictionary) -> void:
	entity_states[entity_id] = state_data.duplicate(true)

## Get entity state from snapshot
func get_entity_state(entity_id: int) -> Dictionary:
	return entity_states.get(entity_id, {})

## Check if snapshot contains entity
func has_entity(entity_id: int) -> bool:
	return entity_id in entity_states

## Get all entity IDs in snapshot
func get_entity_ids() -> Array:
	return entity_states.keys()

## Calculate delta between this snapshot and a baseline
func calculate_delta(baseline: NetworkStateSnapshot) -> NetworkStateSnapshot:
	var delta_snapshot = create_snapshot(snapshot_id, StateType.DELTA)
	delta_snapshot.timestamp = timestamp
	
	for entity_id in entity_states:
		var current_state = entity_states[entity_id]
		var baseline_state = baseline.get_entity_state(entity_id)
		
		if baseline_state.is_empty():
			# New entity, include full state
			delta_snapshot.add_entity_state(entity_id, current_state)
		else:
			# Calculate property differences
			var delta_state = _calculate_property_delta(current_state, baseline_state)
			if not delta_state.is_empty():
				delta_snapshot.add_entity_state(entity_id, delta_state)
	
	return delta_snapshot

## Calculate delta between two state dictionaries
func _calculate_property_delta(current: Dictionary, baseline: Dictionary) -> Dictionary:
	var delta = {}
	
	for key in current:
		if key not in baseline:
			# New property
			delta[key] = current[key]
		elif _is_property_different(current[key], baseline[key]):
			# Changed property
			delta[key] = current[key]
	
	return delta

## Check if two property values are different
func _is_property_different(value_a, value_b) -> bool:
	# Handle different types
	if typeof(value_a) != typeof(value_b):
		return true
	
	# Vector comparison with tolerance
	if value_a is Vector3:
		return not value_a.is_equal_approx(value_b)
	elif value_a is Vector2:
		return not value_a.is_equal_approx(value_b)
	elif value_a is float:
		return not is_equal_approx(value_a, value_b)
	else:
		return value_a != value_b

## Serialize snapshot to Dictionary (for RPC transmission)
func serialize() -> Dictionary:
	return {
		"snapshot_id": snapshot_id,
		"timestamp": timestamp,
		"state_type": state_type,
		"entity_states": _serialize_entity_states()
	}

## Deserialize snapshot from Dictionary
static func deserialize(data: Dictionary) -> NetworkStateSnapshot:
	var snapshot = NetworkStateSnapshot.new()
	snapshot.snapshot_id = data.get("snapshot_id", 0)
	snapshot.timestamp = data.get("timestamp", 0.0)
	snapshot.state_type = data.get("state_type", StateType.BASELINE)
	snapshot.entity_states = _deserialize_entity_states(data.get("entity_states", {}))
	return snapshot

## Serialize entity states for transmission
func _serialize_entity_states() -> Dictionary:
	var serialized = {}
	
	for entity_id in entity_states:
		serialized[str(entity_id)] = _serialize_state_data(entity_states[entity_id])
	
	return serialized

## Deserialize entity states from transmission
static func _deserialize_entity_states(data: Dictionary) -> Dictionary:
	var deserialized = {}
	
	for entity_id_str in data:
		var entity_id = int(entity_id_str)
		deserialized[entity_id] = _deserialize_state_data(data[entity_id_str])
	
	return deserialized

## Serialize individual state data
func _serialize_state_data(state: Dictionary) -> Dictionary:
	var serialized = {}
	
	for key in state:
		var value = state[key]
		
		# Convert special types for RPC
		if value is Vector3:
			serialized[key] = {"type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
		elif value is Vector2:
			serialized[key] = {"type": "Vector2", "x": value.x, "y": value.y}
		elif value is Quaternion:
			serialized[key] = {"type": "Quaternion", "x": value.x, "y": value.y, "z": value.z, "w": value.w}
		elif value is Transform3D:
			serialized[key] = {
				"type": "Transform3D",
				"origin": {"x": value.origin.x, "y": value.origin.y, "z": value.origin.z},
				"basis": {
					"x": {"x": value.basis.x.x, "y": value.basis.x.y, "z": value.basis.x.z},
					"y": {"x": value.basis.y.x, "y": value.basis.y.y, "z": value.basis.y.z},
					"z": {"x": value.basis.z.x, "y": value.basis.z.y, "z": value.basis.z.z}
				}
			}
		else:
			# Primitive types
			serialized[key] = value
	
	return serialized

## Deserialize individual state data
static func _deserialize_state_data(data: Dictionary) -> Dictionary:
	var deserialized = {}
	
	for key in data:
		var value = data[key]
		
		# Reconstruct special types
		if value is Dictionary and "type" in value:
			match value["type"]:
				"Vector3":
					deserialized[key] = Vector3(value["x"], value["y"], value["z"])
				"Vector2":
					deserialized[key] = Vector2(value["x"], value["y"])
				"Quaternion":
					deserialized[key] = Quaternion(value["x"], value["y"], value["z"], value["w"])
				"Transform3D":
					var origin = Vector3(value["origin"]["x"], value["origin"]["y"], value["origin"]["z"])
					var basis_x = Vector3(value["basis"]["x"]["x"], value["basis"]["x"]["y"], value["basis"]["x"]["z"])
					var basis_y = Vector3(value["basis"]["y"]["x"], value["basis"]["y"]["y"], value["basis"]["y"]["z"])
					var basis_z = Vector3(value["basis"]["z"]["x"], value["basis"]["z"]["y"], value["basis"]["z"]["z"])
					var basis = Basis(basis_x, basis_y, basis_z)
					deserialized[key] = Transform3D(basis, origin)
				_:
					deserialized[key] = value
		else:
			deserialized[key] = value
	
	return deserialized

## Get snapshot size (for bandwidth monitoring)
func get_estimated_size() -> int:
	var size = 16  # Base overhead (IDs, timestamps)
	for entity_id in entity_states:
		size += 4  # Entity ID
		size += _estimate_state_size(entity_states[entity_id])
	return size

## Estimate size of state data
func _estimate_state_size(state: Dictionary) -> int:
	var size = 0
	for key in state:
		size += 4  # Key hash
		var value = state[key]
		
		if value is Vector3 or value is Quaternion:
			size += 16  # 4 floats
		elif value is Vector2:
			size += 8   # 2 floats
		elif value is Transform3D:
			size += 48  # 12 floats
		elif value is float:
			size += 4
		elif value is int or value is bool:
			size += 4
		elif value is String:
			size += value.length()
	
	return size

