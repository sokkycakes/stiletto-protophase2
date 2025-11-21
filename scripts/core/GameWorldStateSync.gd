extends Node
class_name GameWorldStateSync

## Integration of StateReplicationManager with GameWorld
## Handles late-joiner synchronization and state replication

var game_world: GameWorld
var state_replication_manager: StateReplicationManager

# --- Configuration ---
@export var enable_state_replication: bool = true
@export var snapshot_rate: float = 20.0
@export var enable_delta_compression: bool = true
@export var debug_logging: bool = false

signal late_joiner_sync_complete(peer_id: int)

func _ready() -> void:
	# Get reference to GameWorld
	game_world = get_parent() as GameWorld
	if not game_world:
		push_error("[GameWorldStateSync] Must be child of GameWorld!")
		return
	
	# Create StateReplicationManager on all peers (needed for RPC path resolution)
	# But only server will actually use it for replication
	state_replication_manager = StateReplicationManager.new()
	state_replication_manager.name = "StateReplicationManager"
	add_child(state_replication_manager)
	
	# Only setup replication on server
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	if enable_state_replication:
		_setup_state_replication()

## Setup state replication manager
func _setup_state_replication() -> void:
	# StateReplicationManager already created in _ready()
	# Just configure it for server use
	if not state_replication_manager:
		return
	
	state_replication_manager.snapshot_rate = snapshot_rate
	state_replication_manager.enable_delta_compression = enable_delta_compression
	
	# Connect signals
	state_replication_manager.baseline_sent_to_peer.connect(_on_baseline_sent_to_peer)
	
	if debug_logging:
		print("[GameWorldStateSync] State replication manager initialized")

## Register player with state replication
func register_player(player: NetworkedPlayer) -> void:
	if not state_replication_manager:
		return
	
	# Register player entity
	var entity_id = state_replication_manager.register_entity(player, player.peer_id)
	if debug_logging:
		print("[GameWorldStateSync] Registered player %s with entity ID %d" % [player.player_name, entity_id])

## Unregister player from state replication
func unregister_player(player: NetworkedPlayer) -> void:
	if not state_replication_manager:
		return
	
	# Find entity by peer_id and unregister it
	var entity_id_to_remove: int = -1
	for entity_id in state_replication_manager.registered_entities:
		var entity = state_replication_manager.registered_entities[entity_id]
		if entity == player:
			entity_id_to_remove = entity_id
			break
	
	if entity_id_to_remove != -1:
		state_replication_manager.unregister_entity(entity_id_to_remove)

## Send full baseline to newly connected player
func sync_late_joiner(peer_id: int) -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	if not state_replication_manager:
		return
	
	if debug_logging:
		print("[GameWorldStateSync] Syncing late joiner: ", peer_id)
	
	# Wait a moment for the client to be fully ready
	await get_tree().create_timer(0.5).timeout
	
	# Send baseline snapshot with all current game state
	state_replication_manager.send_baseline_to_peer(peer_id)
	
	# Also send individual player snapshots via RPC for reliability
	_send_all_player_states_to_peer(peer_id)

## Send all player states to a specific peer
func _send_all_player_states_to_peer(peer_id: int) -> void:
	if not game_world:
		return
	
	var all_player_states: Array[Dictionary] = []
	
	# Collect all player states
	for existing_peer_id in game_world.players:
		if existing_peer_id == peer_id:
			continue  # Don't send their own state
		
		var player: NetworkedPlayer = game_world.players[existing_peer_id]
		if not player:
			continue
		
		# Capture full player state
		var state = _capture_full_player_state(player)
		all_player_states.append(state)
	
	# Send via reliable RPC
	if all_player_states.size() > 0:
		_rpc_receive_late_join_player_states.rpc_id(peer_id, all_player_states)

## Capture complete player state for late joiners
func _capture_full_player_state(player: NetworkedPlayer) -> Dictionary:
	var state = {}
	
	# Basic identity
	state["peer_id"] = player.peer_id
	state["player_name"] = player.player_name
	state["team_id"] = player.team_id
	
	# Health/status
	state["health"] = player.health
	state["max_health"] = player.max_health
	state["is_alive"] = player.is_alive
	
	# Transform
	if player.pawn_body:
		state["position"] = player.pawn_body.global_position
		state["rotation"] = player.pawn_body.global_rotation
	elif player.pawn:
		state["position"] = player.pawn.global_position
		state["rotation"] = player.pawn.global_rotation
	else:
		state["position"] = player.global_position
		state["rotation"] = player.global_rotation
	
	# View angles
	if player.pawn_horizontal_view:
		state["view_yaw"] = player.pawn_horizontal_view.rotation.y
	else:
		state["view_yaw"] = 0.0
	
	if player.pawn_vertical_view:
		state["view_pitch"] = player.pawn_vertical_view.rotation.x
	else:
		state["view_pitch"] = 0.0
	
	# Weapon state
	if player.weapon_manager:
		state["has_weapon_manager"] = true
		state["current_weapon_index"] = player.weapon_manager._current_weapon_index if "_current_weapon_index" in player.weapon_manager else 0
		if player.weapon_manager.current_weapon:
			state["ammo"] = player.weapon_manager.current_weapon.ammo_in_clip
			state["weapon_name"] = player.weapon_manager.current_weapon.name
	else:
		state["has_weapon_manager"] = false
	
	return state

## Client receives late-join player states
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_late_join_player_states(player_states: Array[Dictionary]) -> void:
	if debug_logging:
		print("[GameWorldStateSync] Received %d player states for late join" % player_states.size())
	
	if not game_world:
		return
	
	# Apply each player state
	for state in player_states:
		var peer_id = state.get("peer_id", -1)
		if peer_id == -1:
			continue
		
		# Check if player already exists
		var player = game_world.get_player_by_peer_id(peer_id)
		if player:
			# Update existing player
			_apply_full_player_state(player, state)
		else:
			# Player doesn't exist, they should be spawned separately
			if debug_logging:
				print("[GameWorldStateSync] Player %d not found, will be spawned separately" % peer_id)

## Apply full player state
func _apply_full_player_state(player: NetworkedPlayer, state: Dictionary) -> void:
	# Update health
	if "health" in state:
		player.health = state["health"]
	
	if "is_alive" in state:
		player.is_alive = state["is_alive"]
		if player.pawn:
			player.pawn.visible = player.is_alive
	
	# Update transform
	if "position" in state:
		var pos = state["position"]
		player.last_position = pos
		if player.pawn_body:
			player.pawn_body.global_position = pos
		elif player.pawn:
			player.pawn.global_position = pos
		player.global_position = pos
	
	if "rotation" in state:
		var rot = state["rotation"]
		player.last_rotation = rot
		if player.pawn_body:
			player.pawn_body.global_rotation = rot
		elif player.pawn:
			player.pawn.global_rotation = rot
	
	# Update view angles
	if "view_yaw" in state and player.pawn_horizontal_view:
		player.last_view_yaw = state["view_yaw"]
		player.pawn_horizontal_view.rotation.y = player.last_view_yaw
		player.pawn_horizontal_view.orthonormalize()
	
	if "view_pitch" in state and player.pawn_vertical_view:
		player.last_view_pitch = state["view_pitch"]
		player.pawn_vertical_view.rotation.x = player.last_view_pitch
		player.pawn_vertical_view.orthonormalize()
	
	# Update weapon state
	if state.get("has_weapon_manager", false) and player.weapon_manager:
		if "current_weapon_index" in state:
			var weapon_index = state["current_weapon_index"]
			if weapon_index >= 0 and weapon_index < player.weapon_manager.weapons.size():
				player.weapon_manager._switch_weapon(weapon_index)
		
		if "ammo" in state and player.weapon_manager.current_weapon:
			player.weapon_manager.current_weapon.ammo_in_clip = state["ammo"]
	
	if debug_logging:
		print("[GameWorldStateSync] Applied full state to player: ", player.player_name)

## Called when baseline is sent to a peer
func _on_baseline_sent_to_peer(peer_id: int, snapshot_id: int) -> void:
	if debug_logging:
		print("[GameWorldStateSync] Baseline %d sent to peer %d" % [snapshot_id, peer_id])
	late_joiner_sync_complete.emit(peer_id)

## Get bandwidth statistics
func get_bandwidth_stats() -> Dictionary:
	if state_replication_manager:
		return state_replication_manager.get_bandwidth_stats()
	return {}

## Get entity count
func get_entity_count() -> int:
	if state_replication_manager:
		return state_replication_manager.get_entity_count()
	return 0

## Adjust snapshot rate dynamically
func set_snapshot_rate(rate: float) -> void:
	snapshot_rate = rate
	if state_replication_manager:
		state_replication_manager.set_snapshot_rate(rate)
