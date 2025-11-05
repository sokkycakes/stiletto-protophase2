## Concrete Locomotion Component Implementation
class_name LocomotionComponent
extends ILocomotion

# Navigation
var nav_agent: NavigationAgent3D
var path_follower: NextBotPathFollower

# Movement state
var desired_velocity: Vector3 = Vector3.ZERO
var is_moving: bool = false

func on_initialize() -> void:
    nav_agent = bot.get_navigation_agent()
    if not nav_agent:
        print("LocomotionComponent: No NavigationAgent3D found")
        return

    path_follower = NextBotPathFollower.new(bot)
    path_follower.path_complete.connect(_on_path_complete)
    path_follower.path_failed.connect(_on_path_failed)

    # Set default speeds
    desired_speed = 5.0
    run_speed = 5.0
    walk_speed = 2.0
    crawl_speed = 1.0

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

func face_towards(pos: Vector3) -> void:
    var direction = (pos - bot.global_position).normalized()
    if direction.length() > 0.1:
        var target_transform = bot.global_transform.looking_at(bot.global_position + direction, Vector3.UP)
        bot.global_transform = bot.global_transform.interpolate_with(target_transform, 0.1)

# Jumping and climbing - basic implementations
func climb_up_to_ledge(landing_goal: Vector3, landing_forward: Vector3, obstacle: Node3D) -> bool:
    # Basic implementation - just move to the goal
    approach(landing_goal)
    return true

func jump_across_gap(landing_goal: Vector3, landing_forward: Vector3) -> void:
    # Basic implementation - just move to the goal
    approach(landing_goal)

func jump() -> void:
    # Basic jump implementation
    if is_on_ground:
        velocity.y = 10.0  # Jump velocity
        current_state = LocomotionState.JUMPING

# Movement helpers
func move_to(target_position: Vector3) -> void:
    approach(target_position)

func approach_entity(target: Node) -> void:
    if target:
        approach(target.global_position)

# Update movement state
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

    # Update ground state
    is_on_ground = bot.is_on_floor()
    if is_on_ground and current_state == LocomotionState.JUMPING:
        current_state = LocomotionState.GROUND
        on_land_on_ground(null)

# Path following callbacks
func _on_path_complete() -> void:
    is_moving = false
    on_move_to_success(path_follower.get_path())

func _on_path_failed(reason: NextBotPath.FailureType) -> void:
    is_moving = false
    on_move_to_failure(path_follower.get_path(), reason)