@tool
extends BTAction
## Moves the agent to a specific position in 3D space.
## Adapted for 3D from LimboAI demo.
## Returns SUCCESS when close enough to position, RUNNING while moving, FAILURE if no position.

## Blackboard variable that stores the target position (Vector3).
@export var pos_var: StringName = &"pos"

## Blackboard variable that stores desired speed.
@export var speed_var: StringName = &"speed"

## How close we need to get to consider SUCCESS.
@export var tolerance: float = 1.0

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "ArrivePos3D %s speed: %s" % [
		LimboUtility.decorate_var(pos_var),
		LimboUtility.decorate_var(speed_var)]

# Called each time this task is ticked (aka executed).
func _tick(_delta: float) -> Status:
	var target_pos: Vector3 = blackboard.get_var(pos_var, Vector3.ZERO)
	if target_pos == Vector3.ZERO:
		return FAILURE
	
	var distance = agent.global_position.distance_to(target_pos)
	if distance <= tolerance:
		return SUCCESS
	
	var speed: float = blackboard.get_var(speed_var, 5.0)
	var direction: Vector3 = agent.global_position.direction_to(target_pos)
	direction.y = 0  # Keep movement horizontal
	direction = direction.normalized()
	
	# Move the CharacterBody3D
	if agent is CharacterBody3D:
		agent.velocity.x = direction.x * speed
		agent.velocity.z = direction.z * speed
		agent.move_and_slide()
	
	return RUNNING
