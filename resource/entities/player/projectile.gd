extends Area3D
class_name Projectile

## Base projectile class with universal ownership tracking support
## Extend this or use set_owner_info() when spawning to enable ownership checks

@export var speed: float = 80.0
@export var damage: int = 25
@export var lifetime: float = 3.0  # Shorter lifetime for faster projectiles
@export var impact_particle_scene: PackedScene

# Ownership tracking (uses universal ownership utilities)
var owner_node: Node3D = null
var owner_peer_id: int = -1

var direction: Vector3
var previous_position: Vector3
var timer: Timer

func _ready():
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
	# Continuous collision detection: sweep a ray from last to next position
	var next_pos = position + direction * speed * delta
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(position, next_pos)
	query.exclude = [self]
	query.collision_mask = 0xFFFFFFFF  # collide with all layers
	query.hit_from_inside = true
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		
		# Check ownership before applying damage
		if is_owner(collider):
			print("Bigshot projectile: Ignoring raycast hit with owner")
			destroy()
			return
		
		print("Bigshot projectile sweep hit: ", collider.name)
		# Spawn impact effect
		spawn_impact_particle(result.position, result.normal)
		
		# Find damage receiver and check ownership
		var receiver := _find_damage_receiver(collider)
		if receiver and not is_owner(receiver):
			if receiver.has_method("take_damage"):
				receiver.take_damage(damage)
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
	
	# Rotate projectile to face direction
	look_at(position + direction)

## Set owner information for this projectile (universal ownership tracking)
func set_owner_info(owner_ref: Node3D = null, owner_id: int = -1) -> void:
	owner_node = owner_ref
	owner_peer_id = owner_id

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
	# Handle collision with bodies
	# Check ownership before applying damage
	if is_owner(body):
		print("Bigshot projectile: Ignoring collision with owner")
		destroy()
		return
	
	print("Bigshot projectile hit body: ", body.name)
	spawn_impact_particle(global_position)
	
	# Find damage receiver (might be parent of collider)
	var receiver := _find_damage_receiver(body)
	if receiver:
		# Double-check ownership on the receiver
		if not is_owner(receiver):
			if receiver.has_method("take_damage"):
				receiver.take_damage(damage)
				print("Applied ", damage, " damage to ", receiver.name)
			elif receiver is NetworkedPlayer:
				# Route damage via RPC with validation
				var receiver_np := receiver as NetworkedPlayer
				var attacker_peer_id := owner_peer_id if owner_peer_id >= 0 else -1
				var target_peer_id := receiver_np.peer_id if receiver_np else -1
				receiver.apply_damage.rpc(damage, attacker_peer_id, target_peer_id)
		else:
			print("Bigshot projectile: Ignoring damage to owner")
	
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
	# Handle collision with areas
	print("Bigshot projectile hit area: ", area.name)
	spawn_impact_particle(global_position)
	destroy()

func _on_lifetime_timeout():
	# Destroy projectile when lifetime expires
	destroy()

func destroy():
	# Avoid double free
	if is_queued_for_deletion():
		return
	# PLACEHOLDER: Add destruction effects here
	print("Bigshot projectile destroyed")
	queue_free()

func spawn_impact_particle(position: Vector3, normal: Vector3 = Vector3.UP):
	if impact_particle_scene:
		var particle_node = impact_particle_scene.instantiate()
		get_tree().current_scene.add_child(particle_node)
		if particle_node is Node3D:
			particle_node.global_position = position
			particle_node.look_at(position + normal) 
