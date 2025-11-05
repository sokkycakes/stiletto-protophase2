extends Area3D
class_name Projectile

@export var speed: float = 80.0
@export var damage: int = 25
@export var lifetime: float = 3.0  # Shorter lifetime for faster projectiles
@export var impact_particle_scene: PackedScene

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
		print("Bigshot projectile sweep hit: ", collider.name)
		# Spawn impact effect
		spawn_impact_particle(result.position, result.normal)
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
			destroy()
			return
	# No collision, move projectile
	position = next_pos
	previous_position = position

func initialize(start_position: Vector3, shoot_direction: Vector3):
	position = start_position
	previous_position = start_position
	direction = shoot_direction.normalized()
	
	# Rotate projectile to face direction
	look_at(position + direction)

func _on_body_entered(body):
	# Handle collision with bodies
	print("Bigshot projectile hit body: ", body.name)
	spawn_impact_particle(global_position)
	if body.has_method("take_damage"):
		body.take_damage(damage)
		print("Applied ", damage, " damage to ", body.name)
	destroy()

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
