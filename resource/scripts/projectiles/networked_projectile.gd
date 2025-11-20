extends Node3D
class_name NetworkedProjectile

## Base class for networked projectiles with universal ownership tracking
## Extend this class or use its helper methods to ensure projectiles don't damage their owners

# Owner tracking
var owner_node: Node3D = null  # Reference to who fired the projectile (pawn/body)
var owner_peer_id: int = -1  # Network peer ID of owner (for multiplayer collision checks)
var owner_networked_player: NetworkedPlayer = null  # Cached reference to NetworkedPlayer

# Called when projectile is initialized with owner information
signal owner_set(owner: NetworkedPlayer)

## Initialize the projectile with owner information
## Call this method when spawning projectiles to set ownership tracking
func set_owner(owner_ref: Node3D = null, owner_id: int = -1) -> void:
	owner_node = owner_ref
	owner_peer_id = owner_id
	
	# Try to find NetworkedPlayer if we have peer_id but no reference
	if owner_peer_id >= 0 and not owner_networked_player:
		var scene_root = get_tree().current_scene if get_tree() else null
		if scene_root:
			owner_networked_player = NetworkedProjectileOwnership.find_networked_player_by_peer_id(scene_root, owner_peer_id)
			if not owner_node and owner_networked_player:
				owner_node = NetworkedProjectileOwnership.get_owner_pawn(owner_networked_player)
	
	# Try to get NetworkedPlayer from owner reference if we don't have it yet
	if owner_node and not owner_networked_player:
		owner_networked_player = NetworkedProjectileOwnership.get_owner_networked_player(owner_node)
		if owner_networked_player and owner_peer_id < 0:
			owner_peer_id = owner_networked_player.peer_id
	
	# Set up collision exceptions
	_setup_collision_exceptions()
	
	owner_set.emit(owner_networked_player)

## Check if a body belongs to the owner (using both object reference and peer_id)
func is_owner(body: Node) -> bool:
	if not body:
		return false
	
	# Direct object reference match
	if body == owner_node:
		return true
	
	# Check if body is part of owner's hierarchy
	if owner_node:
		var node := body
		while node:
			if node == owner_node:
				return true
			node = node.get_parent()
	
	# Check by NetworkedPlayer peer_id (works across network)
	if owner_peer_id >= 0:
		var body_np := NetworkedProjectileOwnership.get_owner_networked_player(body)
		if body_np and body_np.peer_id == owner_peer_id:
			return true
	
	return false

## Get the NetworkedPlayer owner
func get_owner_networked_player() -> NetworkedPlayer:
	return owner_networked_player

## Get the owner's peer_id
func get_owner_peer_id() -> int:
	return owner_peer_id

## Check if a body should receive damage (not the owner)
func should_apply_damage_to(body: Node) -> bool:
	if not body:
		return false
	
	# Don't damage owner
	if is_owner(body):
		return false
	
	# Check resolved damage receiver
	var receiver = _find_damage_receiver(body)
	if not receiver:
		return false
	
	# Double-check: don't damage the owner's NetworkedPlayer (even if collision exception failed)
	var receiver_np := receiver as NetworkedPlayer
	if receiver_np and receiver_np.peer_id == owner_peer_id and owner_peer_id >= 0:
		return false
	
	return true

## Find the damage receiver node (NetworkedPlayer or node with take_damage method)
func _find_damage_receiver(target: Node) -> Node:
	var node := target
	while node:
		if node is NetworkedPlayer or node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null

## Set up collision exceptions with owner and their children
func _setup_collision_exceptions() -> void:
	if not owner_node:
		return
	
	# Only works for RigidBody3D or CharacterBody3D
	if not (self is RigidBody3D or self is CharacterBody3D):
		return
	
	# Add exception for owner if it's a PhysicsBody3D
	if owner_node is PhysicsBody3D:
		if self is RigidBody3D:
			(self as RigidBody3D).add_collision_exception_with(owner_node)
		elif self is CharacterBody3D:
			(self as CharacterBody3D).add_collision_exception_with(owner_node)
	
	# Also add exceptions for all descendant PhysicsBody3D nodes (e.g. ragdoll bodies, hitboxes)
	_add_physics_body_exceptions_recursive(owner_node)

## Recursively add collision exceptions for all PhysicsBody3D descendants
func _add_physics_body_exceptions_recursive(node: Node) -> void:
	if node is PhysicsBody3D:
		if self is RigidBody3D:
			(self as RigidBody3D).add_collision_exception_with(node)
		elif self is CharacterBody3D:
			(self as CharacterBody3D).add_collision_exception_with(node)
	
	for child in node.get_children():
		_add_physics_body_exceptions_recursive(child)

