@tool
extends BTAction
## Pursues a target in 3D space using CharacterBody3D movement.
## Adapted for 3D from LimboAI demo.
## Returns SUCCESS when close enough to target, RUNNING while pursuing, FAILURE if no target.

## Blackboard variable that stores the target to pursue.
@export var target_var: StringName = &"target"

## Blackboard variable that stores desired speed.
@export var speed_var: StringName = &"speed"

## How close we need to get to the target to consider SUCCESS.
@export var approach_distance: float = 2.0

## Tolerance for waypoint navigation.
const TOLERANCE: float = 1.0

var _waypoint: Vector3

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "Pursue3D %s speed: %s" % [
		LimboUtility.decorate_var(target_var),
		LimboUtility.decorate_var(speed_var)]

# Called each time this task is entered.
func _enter() -> void:
	_waypoint = agent.global_position

# Called each time this task is ticked (aka executed).
func _tick(_delta: float) -> Status:
	var target: Node3D = blackboard.get_var(target_var, null)
	if not is_instance_valid(target):
		return FAILURE

	var desired_pos: Vector3 = _get_desired_position(target)
	if agent.global_position.distance_to(desired_pos) < approach_distance:
		return SUCCESS

	if agent.global_position.distance_to(_waypoint) < TOLERANCE:
		_select_new_waypoint(desired_pos)

	var speed: float = blackboard.get_var(speed_var, 5.0)
	var direction: Vector3 = agent.global_position.direction_to(_waypoint)
	direction.y = 0  # Keep movement horizontal
	direction = direction.normalized()
	
	# Move the CharacterBody3D
	if agent is CharacterBody3D:
		agent.velocity.x = direction.x * speed
		agent.velocity.z = direction.z * speed
		agent.move_and_slide()
	
	return RUNNING

func _get_desired_position(target: Node3D) -> Vector3:
	return target.global_position

func _select_new_waypoint(desired_pos: Vector3) -> void:
	var dir: Vector3 = agent.global_position.direction_to(desired_pos)
	dir.y = 0
	dir = dir.normalized()
	_waypoint = agent.global_position + dir * min(5.0, agent.global_position.distance_to(desired_pos))
