extends Node

# Core attack functionality
@export_node_path("Area3D") var attack_hitbox_path: NodePath
@export_node_path("AudioStreamPlayer") var attack_sound_path: NodePath
@onready var attack_hitbox: Area3D = get_node(attack_hitbox_path)
@onready var attack_sound: AudioStreamPlayer = get_node(attack_sound_path)

# Attack settings
@export var launch_force: float = 11.0
@export var launch_angle: float = 45.0  # Angle in degrees
@export var attack_duration: float = 0.5
@export var attack_cooldown: float = 1.0

# State
var can_attack: bool = true

func _ready() -> void:
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
	
	print("Attack system initialized")
	print("Hitbox collision mask: ", attack_hitbox.collision_mask)

func start_attack() -> void:
	if not can_attack:
		return
	
	print("Starting attack")
	can_attack = false
	
	# Enable hitbox and play sound
	attack_hitbox.monitoring = true
	attack_hitbox.monitorable = true
	print("Hitbox enabled - monitoring: ", attack_hitbox.monitoring)
	attack_sound.play()
	
	# Wait for attack duration
	await get_tree().create_timer(attack_duration).timeout
	
	# Disable hitbox
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = false
	print("Hitbox disabled")
	
	# Start cooldown
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	print("Hitbox detected body: ", body.name)
	print("Body collision layer: ", body.collision_layer)
	print("Body is in player group: ", body.is_in_group("player"))
	
	if not body.is_in_group("player"):
		return
	
	print("Player hit!")
	launch_player(body)

func launch_player(player: Node3D) -> void:
	if not player is CharacterBody3D:
		print("Body is not CharacterBody3D")
		return
	
	print("Launching player")
	print("Player position: ", player.global_position)
	print("Enemy position: ", get_parent().global_position)
	
	# Calculate launch direction (away from enemy)
	var launch_direction = (player.global_position - get_parent().global_position).normalized()
	launch_direction.y = 0  # Keep horizontal component
	
	# Calculate vertical component based on launch angle
	var vertical_component = sin(deg_to_rad(launch_angle))
	
	# Create final launch vector
	var launch_vector = launch_direction * launch_force
	launch_vector.y = vertical_component * launch_force
	
	print("Launch vector: ", launch_vector)
	
	# Apply launch
	player.velocity = launch_vector
	print("Player velocity after launch: ", player.velocity)
	
	# Call player's take_hit function
	print("Calling player's take_hit() function")
	var player_script = player.get_script()
	print("Player script: ", player_script)
	
	# Try to get the state module directly
	var state_module = player.get_node_or_null("PlayerState")
	if state_module:
		print("Found PlayerState node directly, calling take_hit()")
		state_module.take_hit()
	else:
		print("ERROR: Could not find PlayerState node or take_hit method!")
		print("Available nodes under player:")
		for child in player.get_children():
			print("- ", child.name) 
