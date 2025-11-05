extends CharacterBody3D

# Core parameters
@export var max_health: float = 100.0
@export var move_speed: float = 5.0
@export var gravity: float = 20.0
@export var jump_velocity: float = 4.5

# Current state
var current_health: float
var is_alive: bool = true

# Node references
@onready var ai_node = $AI
@onready var attack_system = $AttackSystem
@onready var parameters = $Parameters
@onready var collisions = $CollisionsAndVolumes

func _ready():
	current_health = max_health
	add_to_group("enemy") # Register for Overwhelm and grapple detection
	initialize_systems()


# Allows external systems (GameMaster) to boost movement speed in special events
func boost_speed(multiplier: float):
	move_speed *= multiplier

func initialize_systems():
	# Initialize AI system
	if ai_node.has_method("initialize"):
		ai_node.initialize()
	
	# Initialize attack system
	if attack_system.has_method("initialize"):
		attack_system.initialize()
	
	# Initialize parameters
	if parameters.has_method("initialize"):
		parameters.initialize()
	
	# Initialize collisions
	if collisions.has_method("initialize"):
		collisions.initialize()

func _physics_process(delta):
	if not is_alive:
		return
		
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Let AI control movement
	if ai_node.has_method("get_movement_direction"):
		var direction = ai_node.get_movement_direction()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	
	move_and_slide()

func take_damage(amount: float):
	if not is_alive:
		return
		
	current_health -= amount
	if current_health <= 0:
		die()

func die():
	is_alive = false
	# Notify GameMaster for kill statistics and hook recharge
	for gm in get_tree().get_nodes_in_group("gamemaster"):
		if gm.has_method("register_kill"):
			gm.register_kill(1)
	# Signal death to other systems
	if ai_node.has_method("on_death"):
		ai_node.on_death()
	if attack_system.has_method("on_death"):
		attack_system.on_death()
	
	# Disable collision
	$CollisionShape3D.set_deferred("disabled", true)
	
	# TODO: Add death animation and cleanup

func get_health_percentage() -> float:
	return current_health / max_health 
