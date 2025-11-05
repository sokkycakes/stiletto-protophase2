extends Node3D

@export var wall_jump_force := 10.0
@export var wall_slide_speed := 2.0
@export var wall_gravity_multiplier := 0.5
@export var wall_detection_distance := 0.6

var can_wall_jump := false
var wall_normal := Vector3.ZERO
var player: CharacterBody3D

func _ready() -> void:
	# Get reference to parent CharacterBody3D
	player = get_parent() as CharacterBody3D
	if not player:
		push_error("WallMovement node must be a child of a CharacterBody3D!")

func _physics_process(_delta: float) -> void:
	if not player:
		return
		
	# Check for wall collision
	if player.is_on_wall():
		var collision = player.get_slide_collision(0)
		if collision:
			wall_normal = collision.get_normal()
			can_wall_jump = true
			
			# Apply wall slide gravity
			if player.velocity.y > 0:
				player.velocity.y *= wall_gravity_multiplier
			elif player.velocity.y < -wall_slide_speed:
				player.velocity.y = -wall_slide_speed
	else:
		can_wall_jump = false
		wall_normal = Vector3.ZERO

func wall_jump() -> void:
	if not player:
		return
		
	if can_wall_jump:
		# Apply wall jump force in opposite direction of wall
		player.velocity = wall_normal * wall_jump_force
		player.velocity.y = wall_jump_force * 0.8  # Slightly reduced vertical force
		can_wall_jump = false 
