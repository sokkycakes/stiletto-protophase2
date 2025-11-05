extends CharacterBody3D
class_name ChargerEnemy3D

# Health system
@export var max_health: float = 150.0
var current_health: float

# Movement
@export var gravity: float = 20.0
@export var charge_speed_multiplier: float = 2.0

# Node references
@onready var bt_player: BTPlayer = $BTPlayer
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var attack_area: Area3D = $AttackArea
@onready var hurtbox: Area3D = $Hurtbox
@onready var debug_label: Label3D = $DebugLabel

# Charging state
var is_charging: bool = false

func _ready() -> void:
	current_health = max_health
	add_to_group("enemy")
	
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
		var state = "Charging" if is_charging else "Normal"
		debug_label.text = "Charger\nHP: %d/%d\n%s" % [current_health, max_health, state]

func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity

func _on_hurtbox_body_entered(body: Node3D) -> void:
	# Handle collision with player attacks
	if body.is_in_group("player_attack"):
		take_damage(20.0)  # Slightly more resistant than melee

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

# Method for attack system integration
func start_attack() -> void:
	# This can be called by the behavior tree attack task
	if attack_area:
		# Check for player in attack area
		var bodies = attack_area.get_overlapping_bodies()
		for body in bodies:
			if body.is_in_group("player"):
				if body.has_method("take_damage"):
					body.take_damage(35.0)  # Higher damage than melee
				elif body.has_method("take_hit"):
					body.take_hit()
				break

# Called by behavior tree when starting charge
func start_charge() -> void:
	is_charging = true

# Called by behavior tree when ending charge
func end_charge() -> void:
	is_charging = false
