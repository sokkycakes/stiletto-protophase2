extends Node

# Signals
signal attack_started
signal attack_ended
signal player_hit

# Node references
@onready var attack_hitbox: Area3D = $AttackHitbox
@onready var attack_sound: AudioStreamPlayer = $AttackSound

# Attack parameters
@export var attack_damage: float = 10.0
@export var attack_cooldown: float = 1.0
@export var attack_duration: float = 0.5
@export var launch_force: float = 11.0
@export var launch_angle: float = 45.0  # Angle in degrees

# State variables
var can_attack: bool = true
var is_attacking: bool = false

func _ready() -> void:
	# Verify required nodes exist
	if not attack_hitbox:
		push_error("Attack hitbox not found!")
		return
		
	if not attack_sound:
		push_error("Attack sound not found!")
		return
	
	# Connect hitbox signal
	attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)
	
	# Initialize hitbox state
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = false

func start_attack() -> void:
	if not can_attack or is_attacking:
		return
	
	print("Starting attack")
	is_attacking = true
	can_attack = false
	attack_started.emit()
	
	# Enable hitbox
	attack_hitbox.monitoring = true
	attack_hitbox.monitorable = true
	
	# Play attack sound
	attack_sound.play()
	
	# Start attack duration timer
	await get_tree().create_timer(attack_duration).timeout
	
	# End attack
	end_attack()
	
	# Start cooldown
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func end_attack() -> void:
	if not is_attacking:
		return
	
	print("Ending attack")
	is_attacking = false
	attack_ended.emit()
	
	# Disable hitbox
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = false

func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	
	print("Player hit!")
	player_hit.emit()
	launch_player(body)

func launch_player(player: Node3D) -> void:
	if not player is CharacterBody3D:
		return
	
	# Calculate launch direction (away from enemy)
	var launch_direction = (player.global_position - get_parent().global_position).normalized()
	launch_direction.y = 0  # Keep horizontal component
	
	# Calculate vertical component based on launch angle
	var vertical_component = sin(deg_to_rad(launch_angle))
	
	# Create final launch vector
	var launch_vector = launch_direction * launch_force
	launch_vector.y = vertical_component * launch_force
	
	# Apply launch
	player.velocity = launch_vector 