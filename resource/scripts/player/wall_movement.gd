extends Node3D

@export_group("Wall Jump Settings")
@export var wall_jump_force := 10.0
@export var wall_jump_angle := 35.0  # Angle in degrees

@export_group("Wall Slide Settings")
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
                
            # Check for jump input while on wall
            if Input.is_action_just_pressed("pm_jump"):
                wall_jump()
    else:
        can_wall_jump = false
        wall_normal = Vector3.ZERO

func wall_jump() -> void:
    if not player or not can_wall_jump:
        return
        
    # Convert angle to radians
    var angle_rad = deg_to_rad(wall_jump_angle)
    
    # Calculate horizontal and vertical components
    var horizontal_force = wall_jump_force * cos(angle_rad)
    var vertical_force = wall_jump_force * sin(angle_rad)
    
    # Apply forces: horizontal in opposite direction of wall, vertical upward
    var horizontal_direction = wall_normal
    horizontal_direction.y = 0  # Keep the jump direction horizontal
    horizontal_direction = horizontal_direction.normalized()
    
    player.velocity = horizontal_direction * horizontal_force
    player.velocity.y = vertical_force
    
    can_wall_jump = false 