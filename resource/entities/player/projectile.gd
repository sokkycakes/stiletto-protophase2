extends Area3D
class_name Projectile

## Base projectile class with universal ownership tracking support
## Extend this or use set_owner_info() when spawning to enable ownership checks

@export var speed: float = 80.0
@export var damage: int = 1  # Reduced from 25 to match 4 HP health system
@export var lifetime: float = 3.0  # Shorter lifetime for faster projectiles
@export var impact_particle_scene: PackedScene
@export var bullet_decal_texture: Texture2D
@export var bullet_decal_size: float = 0.12
@export var bullet_decal_lifetime: float = 8.0

# Ownership tracking (uses universal ownership utilities)
var owner_node: Node3D = null
var owner_peer_id: int = -1
var owner_exclusions: Array = []  # Array of CollisionObject3D nodes to exclude from raycast

# Prevent double damage from multiple collision handlers in same frame
var has_hit: bool = false

# If true, this projectile is visual-only (spawned on remote client, doesn't deal damage)
var is_visual_only: bool = false

var direction: Vector3
var previous_position: Vector3
var timer: Timer

func _ready():
	# Add to projectiles group for airblast detection
	add_to_group("projectiles")
	
	# Set up collision detection
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# Set up lifetime timer
	timer = Timer.new()
	timer.wait_time = lifetime
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_on_lifetime_timeout)
	timer.start()

func _physics_process(delta):
	# Guard against multiple hits in same frame
	if has_hit:
		return
	
	# Continuous collision detection: sweep a ray from last to next position
	var next_pos = position + direction * speed * delta
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(position, next_pos)
	
	# Exclude self and all owner collision bodies
	var exclude_list: Array = [self]
	exclude_list.append_array(owner_exclusions)
	query.exclude = exclude_list
	
	query.collision_mask = 0xFFFFFFFF  # collide with all layers
	query.hit_from_inside = true
	var result = space_state.intersect_ray(query)
	if result:
		has_hit = true  # Mark as hit before applying damage
		var collider = result.collider
		var hit_pos = result.position
		var hit_normal = result.normal
		
		# Check ownership before applying damage
		if is_owner(collider):
			print("Projectile: Ignoring raycast hit with owner")
			destroy()
			return
		
		print("Projectile sweep hit: ", collider.name, " at ", hit_pos)
		
		# Spawn impact effect
		spawn_impact_particle(hit_pos, hit_normal)
		
		# Spawn decal on impact (for static geometry)
		_spawn_decal(hit_pos, hit_normal)
		
		# Find damage receiver and check ownership
		# Only deal damage if not visual-only (visual-only projectiles are spawned on remote clients)
		var receiver := _find_damage_receiver(collider)
		if receiver and not is_owner(receiver) and not is_visual_only:
			# Hit a damageable entity
			# Check for NetworkedPlayer first (must use RPC for networked damage)
			if receiver is NetworkedPlayer:
				var receiver_np := receiver as NetworkedPlayer
				var attacker_peer_id := owner_peer_id if owner_peer_id >= 0 else -1
				var target_peer_id := receiver_np.peer_id if receiver_np else -1
				receiver.apply_damage.rpc_id(target_peer_id, float(damage), attacker_peer_id, target_peer_id)
				print("Projectile hit NetworkedPlayer: ", receiver_np.player_name)
			elif receiver.has_method("take_damage"):
				receiver.take_damage(damage)
				print("Projectile hit damageable entity: ", receiver.name)
		else:
			# Hit static geometry, non-damageable object, or visual-only projectile
			if is_visual_only:
				print("Projectile (visual-only) hit: ", collider.name)
			else:
				print("Projectile hit static geometry: ", collider.name)
		
		# Always destroy on impact (whether it's an entity or static geometry)
		destroy()
		return
	# No collision, move projectile
	position = next_pos
	previous_position = position

func initialize(start_position: Vector3, shoot_direction: Vector3, owner_ref: Node3D = null, owner_id: int = -1):
	position = start_position
	previous_position = start_position
	direction = shoot_direction.normalized()
	
	# Set owner information for ownership tracking
	set_owner_info(owner_ref, owner_id)
	
	# Build exclusion list from owner if not already set
	if owner_exclusions.is_empty() and owner_ref:
		owner_exclusions = _get_owner_collision_bodies(owner_ref)
	
	# Rotate projectile to face direction
	look_at(position + direction)

## Set owner information for this projectile (universal ownership tracking)
func set_owner_info(owner_ref: Node3D = null, owner_id: int = -1) -> void:
	owner_node = owner_ref
	owner_peer_id = owner_id
	
	# Build exclusion list from owner
	if owner_ref:
		owner_exclusions = _get_owner_collision_bodies(owner_ref)

## Get all collision bodies from owner for exclusion
func _get_owner_collision_bodies(owner: Node3D) -> Array:
	var collision_bodies: Array = []
	if not owner:
		return collision_bodies
	
	# Recursively collect all CollisionObject3D nodes (CharacterBody3D, RigidBody3D, StaticBody3D, Area3D)
	var nodes_to_check: Array = [owner]
	while nodes_to_check.size() > 0:
		var current_node = nodes_to_check.pop_back()
		
		if current_node is CollisionObject3D:
			collision_bodies.append(current_node)
		
		# Add children to check
		for child in current_node.get_children():
			nodes_to_check.append(child)
	
	return collision_bodies

## Check if a body belongs to the owner
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

func _on_body_entered(body):
	# Guard against multiple hits in same frame
	if has_hit:
		return
	
	# Handle collision with bodies
	# Check ownership before applying damage
	if is_owner(body):
		print("Bigshot projectile: Ignoring collision with owner")
		destroy()
		return
	
	has_hit = true  # Mark as hit before applying damage
	
	print("Bigshot projectile hit body: ", body.name)
	spawn_impact_particle(global_position)
	
	# Find damage receiver (might be parent of collider)
	# Only deal damage if not visual-only (visual-only projectiles are spawned on remote clients)
	var receiver := _find_damage_receiver(body)
	if receiver and not is_visual_only:
		# Double-check ownership on the receiver
		if not is_owner(receiver):
			# Check for NetworkedPlayer first (must use RPC for networked damage)
			if receiver is NetworkedPlayer:
				# Route damage via RPC with validation
				var receiver_np := receiver as NetworkedPlayer
				var attacker_peer_id := owner_peer_id if owner_peer_id >= 0 else -1
				var target_peer_id := receiver_np.peer_id if receiver_np else -1
				# Send RPC specifically to the authority peer (the player who owns this NetworkedPlayer)
				print("Projectile: Applying damage to NetworkedPlayer - damage: ", damage, ", attacker_peer_id: ", attacker_peer_id, ", target_peer_id: ", target_peer_id, ", owner_peer_id: ", owner_peer_id)
				receiver.apply_damage.rpc_id(target_peer_id, float(damage), attacker_peer_id, target_peer_id)
				print("Applied ", damage, " damage to NetworkedPlayer: ", receiver_np.player_name)
			elif receiver.has_method("take_damage"):
				receiver.take_damage(damage)
				print("Applied ", damage, " damage to ", receiver.name)
		else:
			print("Bigshot projectile: Ignoring damage to owner")
	elif is_visual_only:
		print("Bigshot projectile (visual-only): hit ", body.name)
	
	destroy()

## Find damage receiver node (walks up hierarchy)
func _find_damage_receiver(target: Node) -> Node:
	var node := target
	while node:
		if node is NetworkedPlayer or node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null

func _on_area_entered(area):
	# Guard against multiple hits in same frame
	if has_hit:
		return
	
	# Handle collision with areas
	# Check ownership before applying damage
	if is_owner(area):
		print("Projectile: Ignoring collision with owner area")
		destroy()
		return
	
	has_hit = true  # Mark as hit before applying damage
	
	print("Projectile hit area: ", area.name)
	
	# Get collision position and normal
	var hit_pos = global_position
	var hit_normal = -direction
	
	# Try to get more accurate hit position from raycast
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(previous_position, global_position)
	query.exclude = [self]
	query.exclude.append_array(owner_exclusions)
	var result = space_state.intersect_ray(query)
	if result:
		hit_pos = result.position
		hit_normal = result.normal
	
	spawn_impact_particle(hit_pos, hit_normal)
	_spawn_decal(hit_pos, hit_normal)
	destroy()

func _on_lifetime_timeout():
	# Destroy projectile when lifetime expires
	destroy()

func destroy():
	# Avoid double free
	if is_queued_for_deletion():
		return
	
	# Detach and preserve the trail for 1 second after destruction
	_detach_trail()
	
	# PLACEHOLDER: Add destruction effects here
	print("Bigshot projectile destroyed")
	queue_free()

func _detach_trail() -> void:
	# Find the GPUTrail3D node
	var trail = get_node_or_null("GPUTrail3D")
	if not trail:
		return
	
	# Remove trail from projectile's children
	remove_child(trail)
	
	# Add trail to scene root so it persists after projectile is destroyed
	var scene_root = get_tree().current_scene
	if scene_root:
		scene_root.add_child(trail)
		# Preserve the trail's global position and transform
		trail.global_position = global_position
		trail.global_transform = global_transform
		
		# Stop the trail from emitting new particles (GPUTrail3D extends GPUParticles3D)
		if trail is GPUParticles3D:
			trail.emitting = false
		
		# Set up timer to destroy trail after 1 second
		var cleanup_timer = Timer.new()
		cleanup_timer.wait_time = 1.0
		cleanup_timer.one_shot = true
		cleanup_timer.timeout.connect(func(): 
			if is_instance_valid(trail):
				trail.queue_free()
		)
		trail.add_child(cleanup_timer)
		cleanup_timer.start()
		
		print("Projectile: Trail detached and will be destroyed in 1 second")

func spawn_impact_particle(position: Vector3, normal: Vector3 = Vector3.UP):
	if impact_particle_scene:
		var particle_node = impact_particle_scene.instantiate()
		get_tree().current_scene.add_child(particle_node)
		if particle_node is Node3D:
			particle_node.global_position = position
			particle_node.look_at(position + normal)

func _spawn_decal(pos: Vector3, normal: Vector3) -> void:
	if bullet_decal_texture == null:
		return
	var decal := Decal.new()
	decal.texture_albedo = bullet_decal_texture
	decal.global_position = pos + normal * 0.01
	decal.look_at(decal.global_position + normal, Vector3.UP)
	decal.size = Vector3(bullet_decal_size, bullet_decal_size, 0.05)
	get_tree().current_scene.add_child(decal)
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = bullet_decal_lifetime
	decal.add_child(t)
	t.timeout.connect(func(): decal.queue_free())
	t.start() 
