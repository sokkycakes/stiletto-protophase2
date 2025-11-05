extends CharacterBody3D
class_name RangedEnemy3D

# Health system
@export var max_health: float = 80.0
var current_health: float

# Movement
@export var gravity: float = 20.0

# Ranged combat
@export var projectile_scene: PackedScene
@export var shoot_cooldown: float = 2.0
var can_shoot: bool = true

# Node references
@onready var bt_player: BTPlayer = $BTPlayer
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var hurtbox: Area3D = $Hurtbox
@onready var debug_label: Label3D = $DebugLabel
@onready var shoot_point: Marker3D = $ShootPoint

func _ready() -> void:
	current_health = max_health
	add_to_group("enemy")
	
	# Load default projectile if none specified
	if not projectile_scene:
		projectile_scene = preload("res://enemies/projectile_3d.tscn")
	
	# Connect signals
	if hurtbox:
		hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	
	# Set up navigation
	if navigation_agent:
		navigation_agent.velocity_computed.connect(_on_velocity_computed)

func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Let BTPlayer handle movement, but ensure we call move_and_slide
	if velocity != Vector3.ZERO:
		move_and_slide()
	
	# Update debug info
	if debug_label:
		var cooldown_text = "Ready" if can_shoot else "Cooldown"
		debug_label.text = "Ranged\nHP: %d/%d\n%s" % [current_health, max_health, cooldown_text]

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity

func _on_hurtbox_body_entered(body: Node3D) -> void:
	# Handle collision with player attacks
	if body.is_in_group("player_attack"):
		take_damage(30.0)  # Less health than others

func take_damage(amount: float) -> void:
	current_health -= amount
	
	if current_health <= 0:
		die()

func die() -> void:
	# Disable AI
	if bt_player:
		bt_player.set_active(false)
	
	# Remove from enemy group
	remove_from_group("enemy")
	
	# Simple death effect - fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.TRANSPARENT, 1.0)
	tween.tween_callback(queue_free)

# Method for behavior tree to shoot projectiles
func shoot_at_target(target: Node3D) -> bool:
	if not can_shoot or not projectile_scene or not is_instance_valid(target):
		return false
	
	# Calculate direction to target
	var spawn_pos = shoot_point.global_position if shoot_point else global_position + Vector3(0, 1.5, 0)
	var direction = (target.global_position - spawn_pos).normalized()
	
	# Create and configure projectile
	var projectile = projectile_scene.instantiate()
	get_parent().add_child(projectile)
	projectile.global_position = spawn_pos
	
	# Set projectile direction
	if projectile.has_method("set_direction"):
		projectile.set_direction(direction)
	elif "velocity" in projectile:
		projectile.velocity = direction * 15.0
	elif "linear_velocity" in projectile:
		projectile.linear_velocity = direction * 15.0
	
	# Orient projectile
	if projectile is Node3D:
		projectile.look_at(spawn_pos + direction, Vector3.UP)
	
	# Start cooldown
	can_shoot = false
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = shoot_cooldown
	timer.one_shot = true
	timer.timeout.connect(func(): 
		can_shoot = true
		timer.queue_free()
	)
	timer.start()
	
	return true
