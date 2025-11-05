## Enhanced Locomotion Component Implementation

class_name EnhancedLocomotionComponent
extends ILocomotion

# Navigation
var nav_agent: NavigationAgent3D
var path_follower: NextBotPathFollower

# Movement state
var desired_velocity: Vector3 = Vector3.ZERO
var is_moving: bool = false
var last_position: Vector3 = Vector3.ZERO

func on_initialize() -> void:
    nav_agent = bot.get_navigation_agent()
    if not nav_agent:
        print("EnhancedLocomotionComponent: No NavigationAgent3D found")
        return
    
    path_follower = NextBotPathFollower.new(bot)
    path_follower.path_complete.connect(_on_path_complete)
    path_follower.path_failed.connect(_on_path_failed)
    
    # Set default speeds
    desired_speed = 5.0
    run_speed = 5.0
    walk_speed = 2.0
    crawl_speed = 1.0
    
    # Initialize stuck detection
    stuck_position = bot.global_position
    last_position = bot.global_position

func on_update(delta: float) -> void:
    if not nav_agent:
        return
    
    # Update path following
    if path_follower:
        path_follower.update(delta)
    
    # Update movement state
    _update_movement_state(delta)
    
    # Update stuck detection
    _update_stuck_detection(delta)
    
    # Update ground state
    _update_ground_state()

# Core locomotion interface implementation
func approach(goal_pos: Vector3, goal_weight: float = 1.0) -> void:
    if not nav_agent:
        return
    
    nav_agent.target_position = goal_pos
    is_moving = true
    
    # Create and follow path
    var path = NextBotPath.new()
    if await path.compute_to_position(bot, goal_pos):
        path_follower.set_path(path)

func drive_to(pos: Vector3) -> void:
    if not nav_agent:
        return
    
    # Immediate movement - teleport to position
    bot.global_position = pos
    velocity = Vector3.ZERO
    is_moving = false

func face_towards(pos: Vector3) -> void:
    var direction = (pos - bot.global_position).normalized()
    if direction.length() > 0.1:
        var target_transform = bot.global_transform.looking_at(bot.global_position + direction, Vector3.UP)
        bot.global_transform = bot.global_transform.interpolate_with(target_transform, 0.1)

# Jumping and climbing - enhanced implementations
func climb_up_to_ledge(landing_goal: Vector3, landing_forward: Vector3, obstacle: Node3D) -> bool:
    # Enhanced climbing implementation
    current_state = LocomotionState.CLIMBING
    
    # Create climbing path
    var climb_path = NextBotPath.new()
    if await climb_path.compute_to_position(bot, landing_goal):
        path_follower.set_path(climb_path)
        return true
    
    return false

func jump_across_gap(landing_goal: Vector3, landing_forward: Vector3) -> void:
    # Enhanced gap jumping
    current_state = LocomotionState.JUMPING
    velocity.y = 8.0  # Jump velocity
    
    # Set horizontal velocity towards landing goal
    var horizontal_direction = (landing_goal - bot.global_position)
    horizontal_direction.y = 0
    horizontal_direction = horizontal_direction.normalized()
    
    velocity.x = horizontal_direction.x * desired_speed
    velocity.z = horizontal_direction.z * desired_speed

func jump() -> void:
    if is_on_ground:
        velocity.y = 10.0  # Jump velocity
        current_state = LocomotionState.JUMPING
        on_leave_ground(ground_entity)

# Enhanced movement state management
func _update_movement_state(delta: float) -> void:
    if not nav_agent:
        return
    
    # Update velocity from navigation
    if not nav_agent.is_navigation_finished():
        var next_position = nav_agent.get_next_path_position()
        var direction = (next_position - bot.global_position).normalized()
        desired_velocity = direction * desired_speed
        nav_agent.velocity = desired_velocity
    else:
        desired_velocity = Vector3.ZERO
        is_moving = false
    
    # Update motion vectors
    velocity = bot.velocity
    ground_speed = Vector3(velocity.x, 0, velocity.z).length()
    motion_vector = velocity.normalized() if velocity.length() > 0.1 else Vector3.ZERO
    ground_motion_vector = Vector3(velocity.x, 0, velocity.z).normalized() if ground_speed > 0.1 else Vector3.ZERO

func _update_ground_state() -> void:
    var was_on_ground = is_on_ground
    is_on_ground = bot.is_on_floor()
    
    if is_on_ground and not was_on_ground:
        # Just landed
        if current_state == LocomotionState.JUMPING or current_state == LocomotionState.FALLING:
            current_state = LocomotionState.GROUND
            on_land_on_ground(ground_entity)
    elif not is_on_ground and was_on_ground:
        # Just left ground
        if current_state == LocomotionState.GROUND:
            current_state = LocomotionState.FALLING
            on_leave_ground(ground_entity)

# Enhanced stuck detection
func _update_stuck_detection(delta: float) -> void:
    if not is_moving:
        return
    
    var current_pos = bot.global_position
    var movement_delta = (current_pos - last_position).length()
    
    if movement_delta < 0.1:  # Very little movement
        stuck_timer += delta
        if stuck_timer > stuck_threshold and not is_stuck:
            is_stuck = true
            stuck_position = current_pos
            on_stuck()
    else:
        if is_stuck:
            is_stuck = false
            on_unstuck()
        stuck_timer = 0.0
    
    last_position = current_pos

# Path following callbacks
func _on_path_complete() -> void:
    is_moving = false
    on_move_to_success(path_follower.get_path())

func _on_path_failed(reason: NextBotPath.FailureType) -> void:
    is_moving = false
    on_move_to_failure(path_follower.get_path(), reason)

# Area traversal
func is_area_traversable(area: NavigationRegion3D) -> bool:
    # Enhanced traversal checking
    if not area:
        return false
    
    # Check if area is enabled
    if not area.enabled:
        return false
    
    # Check navigation layers (if your game uses them)
    # This would depend on your specific navigation setup
    
    return true

# Collision detection
func should_collide_with(object: Node3D) -> bool:
    # Enhanced collision filtering
    if not object:
        return false
    
    # Don't collide with other bots of same team
    if object.has_method("get_team") and bot.has_method("get_team"):
        if object.get_team() == bot.get_team():
            return false
    
    # Don't collide with projectiles we fired
    if object.has_method("get_owner") and object.get_owner() == bot:
        return false
    
    return true

# Speed control
func set_desired_speed(speed: float) -> void:
    desired_speed = speed
    if nav_agent:
        nav_agent.max_speed = speed

# Utility methods
func get_path_follower() -> NextBotPathFollower:
    return path_follower

func is_path_valid() -> bool:
    return path_follower and path_follower.is_path_valid()

func get_distance_to_goal() -> float:
    if path_follower:
        return path_follower.get_distance_to_goal()
    return INF

func get_current_goal() -> Vector3:
    if path_follower:
        return path_follower.get_current_goal()
    return Vector3.ZERO

# Debug
func draw_debug() -> void:
    if path_follower:
        path_follower.draw_debug()
