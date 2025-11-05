extends RigidBody3D
class_name Projectile3D

@export var damage: float = 15.0
@export var speed: float = 15.0
@export var lifetime: float = 5.0

var direction: Vector3 = Vector3.FORWARD
var has_hit: bool = false

func _find_player_target(start_node: Node) -> Node:
	var current: Node = start_node
	while current:
		var state: Node = current.get_node_or_null("PlayerState")
		if state and state.has_method("take_hit"):
			return current
		if current.has_method("take_damage") or current.has_method("take_hit"):
			return current
		current = current.get_parent()
	return start_node

func _ready() -> void:
	# Set up collision detection
	body_entered.connect(_on_body_entered)

	# Set initial velocity
	linear_velocity = direction * speed

	# Auto-destroy after lifetime
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = lifetime
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	timer.start()

	# Debug output
	print("[Projectile3D] Created with direction: ", direction, " speed: ", speed)

func set_direction(new_direction: Vector3, projectile_speed: float = -1) -> void:
	direction = new_direction.normalized()
	if projectile_speed > 0:
		speed = projectile_speed
	linear_velocity = direction * speed
	print("[Projectile3D] Direction set to: ", direction, " velocity: ", linear_velocity)

func set_velocity(new_velocity: Vector3) -> void:
	linear_velocity = new_velocity
	direction = new_velocity.normalized()
	speed = new_velocity.length()
	print("[Projectile3D] Velocity set to: ", linear_velocity)

func set_damage(new_damage: float) -> void:
	damage = new_damage
	print("[Projectile3D] Damage set to: ", damage)

func _on_body_entered(body: Node) -> void:
	if has_hit:
		return

	print("[Projectile3D] Hit body: ", body.name, " groups: ", body.get_groups())

	# Don't hit the shooter
	if body.is_in_group("enemy"):
		print("[Projectile3D] Ignoring enemy collision")
		return

	has_hit = true

	# Resolve the top-level player node and call the existing health pipeline
	# used by ss_player (mirrors knight behavior: call PlayerState.take_hit).
	var hit_node: Node = _find_player_target(body)

	if hit_node and (hit_node.is_in_group("player") or hit_node.get_node_or_null("PlayerState") != null):
		print("[Projectile3D] Hitting player with damage: ", damage)
		# Prefer the PlayerState component when present to integrate with invuln/stun/UI
		var player_state: Node = hit_node.get_node_or_null("PlayerState")
		if player_state and player_state.has_method("take_hit"):
			player_state.take_hit(int(damage))
		elif hit_node.has_method("take_damage"):
			hit_node.take_damage(int(damage))
		elif hit_node.has_method("take_hit"):
			hit_node.take_hit()
		else:
			print("[Projectile3D] Player has no damage interface (expected PlayerState.take_hit)")
	else:
		print("[Projectile3D] Hit non-player object: ", body.name)

	# Destroy projectile on impact
	queue_free()
