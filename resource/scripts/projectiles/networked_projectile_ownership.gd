extends Node
class_name NetworkedProjectileOwnership

## Utility class for managing projectile ownership in multiplayer
## Provides helper functions for finding owners and tracking projectiles

## Get the owner NetworkedPlayer from a weapon or player node
static func get_owner_networked_player(weapon_or_player: Node) -> NetworkedPlayer:
	if not weapon_or_player:
		return null
	
	var node := weapon_or_player
	while node:
		if node is NetworkedPlayer:
			return node
		node = node.get_parent()
	
	return null

## Get the owner's peer_id from a weapon or player node
static func get_owner_peer_id(weapon_or_player: Node) -> int:
	var np := get_owner_networked_player(weapon_or_player)
	if np:
		return np.peer_id
	return -1

## Get the owner's pawn/body node from a NetworkedPlayer or weapon node
static func get_owner_pawn(weapon_or_player: Node) -> Node3D:
	var np := get_owner_networked_player(weapon_or_player)
	if not np:
		return null
	
	# Try to get pawn if NetworkedPlayer has that method
	if np.has_method("get_pawn"):
		var pawn = np.get_pawn()
		if pawn and pawn.has_method("get_node"):
			# Try to get Body node from pawn
			return pawn.get_node_or_null("Body") as Node3D
		return pawn as Node3D
	
	return np as Node3D

## Find a NetworkedPlayer by peer_id in the scene
static func find_networked_player_by_peer_id(scene_root: Node, peer_id: int) -> NetworkedPlayer:
	if peer_id < 0 or not scene_root:
		return null
	
	var players = scene_root.find_children("*", "NetworkedPlayer", true, false)
	for player in players:
		if player.peer_id == peer_id:
			return player
	
	return null

## Get the pawn/body node for a NetworkedPlayer by peer_id
static func get_pawn_by_peer_id(scene_root: Node, peer_id: int) -> Node3D:
	var np := find_networked_player_by_peer_id(scene_root, peer_id)
	if not np:
		return null
	
	# Try to get pawn if NetworkedPlayer has that method
	if np.has_method("get_pawn"):
		var pawn = np.get_pawn()
		if pawn and pawn.has_method("get_node"):
			return pawn.get_node_or_null("Body") as Node3D
		return pawn as Node3D
	
	return np as Node3D

