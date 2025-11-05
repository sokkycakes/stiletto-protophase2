## NextBot Locomotion Interface
## Based on Source SDK NextBotLocomotionInterface.h
class_name ILocomotion
extends INextBotComponent

# Locomotion states
enum LocomotionState {
	GROUND,
	CLIMBING,
	JUMPING,
	FALLING,
	SWIMMING
}

# Movement properties
var desired_speed: float = 5.0
var max_acceleration: float = 1000.0
var max_deceleration: float = 2000.0
var step_height: float = 0.5
var max_jump_height: float = 2.0
var max_drop_height: float = 10.0
var run_speed: float = 5.0
var walk_speed: float = 2.0
var crawl_speed: float = 1.0

# Current state
var current_state: LocomotionState = LocomotionState.GROUND
var velocity: Vector3 = Vector3.ZERO
var ground_speed: float = 0.0
var motion_vector: Vector3 = Vector3.ZERO
var ground_motion_vector: Vector3 = Vector3.ZERO

# Ground tracking
var ground_entity: Node3D
var ground_normal: Vector3 = Vector3.UP
var is_on_ground: bool = false

# Stuck detection
var is_stuck: bool = false
var stuck_timer: float = 0.0
var stuck_position: Vector3
var stuck_threshold: float = 1.0

# Movement methods - must be implemented by derived classes
func approach(goal_pos: Vector3, goal_weight: float = 1.0) -> void:
	assert(false, "approach() must be implemented by derived class")

func drive_to(pos: Vector3) -> void:
	assert(false, "drive_to() must be implemented by derived class")

func face_towards(pos: Vector3) -> void:
	assert(false, "face_towards() must be implemented by derived class")

# Jumping and climbing
func climb_up_to_ledge(landing_goal: Vector3, landing_forward: Vector3, obstacle: Node3D) -> bool:
	assert(false, "climb_up_to_ledge() must be implemented by derived class")
	return false

func jump_across_gap(landing_goal: Vector3, landing_forward: Vector3) -> void:
	assert(false, "jump_across_gap() must be implemented by derived class")

func jump() -> void:
	assert(false, "jump() must be implemented by derived class")

# State queries
func is_on_ground_query() -> bool:
	return is_on_ground

func is_climbing() -> bool:
	return current_state == LocomotionState.CLIMBING

func is_climbing_or_jumping() -> bool:
	return current_state == LocomotionState.CLIMBING or current_state == LocomotionState.JUMPING

func is_climbing_up_to_ledge() -> bool:
	return current_state == LocomotionState.CLIMBING

func is_jumping() -> bool:
	return current_state == LocomotionState.JUMPING

func is_scrambling() -> bool:
	return current_state == LocomotionState.CLIMBING

func is_running() -> bool:
	return ground_speed > walk_speed

func is_stuck_query() -> bool:
	return is_stuck

# Movement properties
func get_velocity() -> Vector3:
	return velocity

func get_speed() -> float:
	return velocity.length()

func get_ground_speed() -> float:
	return ground_speed

func get_motion_vector() -> Vector3:
	return motion_vector

func get_ground_motion_vector() -> Vector3:
	return ground_motion_vector

# Ground interaction
func get_ground() -> Node3D:
	return ground_entity

func get_ground_normal() -> Vector3:
	return ground_normal

# Speed control
func set_desired_speed(speed: float) -> void:
	desired_speed = speed

func get_desired_speed() -> float:
	return desired_speed

func get_run_speed() -> float:
	return run_speed

func get_walk_speed() -> float:
	return walk_speed

func get_crawl_speed() -> float:
	return crawl_speed

# Traversal
func get_step_height() -> float:
	return step_height

func get_max_jump_height() -> float:
	return max_jump_height

func get_max_drop_height() -> float:
	return max_drop_height

func get_traversable_slope_limit() -> float:
	return 0.7  # cos(45 degrees)

# Area traversal
func is_area_traversable(area: NavigationRegion3D) -> bool:
	# Default implementation - can be overridden
	return area != null

# Collision
func should_collide_with(object: Node3D) -> bool:
	# Default implementation - can be overridden
	return true

# Stuck handling
func clear_stuck_status() -> void:
	is_stuck = false
	stuck_timer = 0.0

# Component name
func _init() -> void:
	component_name = "Locomotion"

# Update stuck detection
func _update_stuck_detection(delta: float) -> void:
	if not is_on_ground:
		return
		
	var current_pos = bot.get_position()
	var movement_delta = (current_pos - stuck_position).length()
	
	if movement_delta < 0.1:  # Very little movement
		stuck_timer += delta
		if stuck_timer > stuck_threshold and not is_stuck:
			is_stuck = true
			on_stuck()
	else:
		if is_stuck:
			is_stuck = false
			on_unstuck()
		stuck_timer = 0.0
		stuck_position = current_pos
