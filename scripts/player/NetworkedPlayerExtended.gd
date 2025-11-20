extends NetworkedPlayer
class_name NetworkedPlayerExtended

## Extended NetworkedPlayer with Source Engine-style state replication
## Uses NetworkedEntity for automatic state synchronization

# --- State Replication (overrides base sync system) ---
var entity_adapter: NetworkedEntity
var use_advanced_sync: bool = true

func _ready() -> void:
	super._ready()
	
	# Create and attach a NetworkedEntity adapter for state replication
	if use_advanced_sync:
		_setup_entity_adapter()

func _setup_entity_adapter() -> void:
	entity_adapter = NetworkedEntity.new()
	entity_adapter.name = "EntityAdapter"
	entity_adapter.replicate_position = true
	entity_adapter.replicate_rotation = true
	entity_adapter.replicate_velocity = true
	entity_adapter.network_priority = 5.0  # Players have high priority
	add_child(entity_adapter)
	
	# Set as locally controlled for authority player
	entity_adapter.set_locally_controlled(is_multiplayer_authority())
	
	print("[NetworkedPlayerExtended] Setup entity adapter for: ", player_name)

## Override to use NetworkedEntity state capture
func capture_network_state() -> Dictionary:
	var state = {}
	
	# Player identity
	state["peer_id"] = peer_id
	state["player_name"] = player_name
	state["team_id"] = team_id
	
	# Health and alive status
	state["health"] = health
	state["is_alive"] = is_alive
	
	# Transform
	if pawn_body:
		state["position"] = pawn_body.global_position
		state["rotation"] = pawn_body.global_rotation
		state["velocity"] = pawn_body.velocity if pawn_body.velocity else Vector3.ZERO
	elif pawn:
		state["position"] = pawn.global_position
		state["rotation"] = pawn.global_rotation
		state["velocity"] = Vector3.ZERO
	
	# View angles
	if pawn_horizontal_view:
		state["view_yaw"] = pawn_horizontal_view.rotation.y
	else:
		state["view_yaw"] = 0.0
	
	if pawn_vertical_view:
		state["view_pitch"] = pawn_vertical_view.rotation.x
	else:
		state["view_pitch"] = 0.0
	
	# Weapon state (if weapon manager exists)
	if weapon_manager:
		state["weapon_index"] = weapon_manager._current_weapon_index if "_current_weapon_index" in weapon_manager else 0
		if weapon_manager.current_weapon:
			state["ammo"] = weapon_manager.current_weapon.ammo_in_clip
	
	return state

## Override to apply networked state from snapshots
func apply_network_state(state: Dictionary) -> void:
	# Don't apply state if we're the authority
	if is_multiplayer_authority():
		return
	
	# Apply basic player data
	if "health" in state:
		health = state["health"]
	
	if "is_alive" in state:
		is_alive = state["is_alive"]
		if pawn:
			pawn.visible = is_alive
	
	# Apply transform
	if "position" in state:
		var new_position = state["position"]
		last_position = new_position
		
		if pawn_body:
			# Use interpolation
			if entity_adapter and entity_adapter.enable_interpolation:
				entity_adapter.interpolation_target_position = new_position
				entity_adapter.has_interpolation_target = true
			else:
				pawn_body.global_position = new_position
				global_position = new_position
		elif pawn:
			pawn.global_position = new_position
			global_position = new_position
	
	if "rotation" in state:
		var new_rotation = state["rotation"]
		last_rotation = new_rotation
		
		if pawn_body:
			pawn_body.global_rotation = new_rotation
		elif pawn:
			pawn.global_rotation = new_rotation
	
	# Apply velocity
	if "velocity" in state and pawn_body:
		pawn_body.velocity = state["velocity"]
	
	# Apply view angles
	if "view_yaw" in state:
		last_view_yaw = state["view_yaw"]
		if pawn_horizontal_view:
			pawn_horizontal_view.rotation.y = last_view_yaw
			pawn_horizontal_view.orthonormalize()
	
	if "view_pitch" in state:
		last_view_pitch = state["view_pitch"]
		if pawn_vertical_view:
			pawn_vertical_view.rotation.x = last_view_pitch
			pawn_vertical_view.orthonormalize()
	
	# Apply weapon state
	if "weapon_index" in state and weapon_manager:
		var weapon_index = state["weapon_index"]
		if weapon_manager._current_weapon_index != weapon_index:
			weapon_manager._switch_weapon(weapon_index)
	
	if "ammo" in state and weapon_manager and weapon_manager.current_weapon:
		weapon_manager.current_weapon.ammo_in_clip = state["ammo"]

## Override get_peer_id for NetworkedEntity priority calculations
func get_peer_id() -> int:
	return peer_id

## Override get_velocity for NetworkedEntity priority calculations
func get_velocity() -> Vector3:
	if pawn_body and pawn_body.velocity:
		return pawn_body.velocity
	elif entity_adapter:
		return entity_adapter.velocity
	return Vector3.ZERO

## Get network priority - players are high priority
func get_network_priority() -> float:
	var priority = 5.0  # Base player priority
	
	# Boost priority if player is moving
	var velocity = get_velocity()
	if velocity.length() > 0.1:
		priority *= 1.5
	
	# Boost priority if player is shooting
	if weapon_manager and weapon_manager.current_weapon:
		if weapon_manager.current_weapon.has_method("is_firing"):
			if weapon_manager.current_weapon.is_firing():
				priority *= 2.0
	
	return priority

## Rewind player to specific time for lag compensation
func rewind_to_time(timestamp: float) -> Dictionary:
	if entity_adapter:
		return entity_adapter.rewind_to_time(timestamp)
	return capture_network_state()

## Restore player from saved state
func restore_state(state: Dictionary) -> void:
	apply_network_state(state)

