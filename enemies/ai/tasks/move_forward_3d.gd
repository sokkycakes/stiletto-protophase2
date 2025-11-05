@tool
extends BTAction
## Moves the agent forward in 3D space for a specified duration.
## Adapted for 3D from LimboAI demo.
## Returns SUCCESS when duration is exceeded, RUNNING while moving.

## Blackboard variable that stores desired speed.
@export var speed_var: StringName = &"speed"

## How long to perform this task (in seconds).
@export var duration: float = 0.5

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "MoveForward3D speed: %s duration: %ss" % [
		LimboUtility.decorate_var(speed_var),
		duration]

# Called each time this task is ticked (aka executed).
func _tick(_delta: float) -> Status:
	var speed: float = blackboard.get_var(speed_var, 5.0)
	
	# Get forward direction from agent's rotation
	var forward = -agent.transform.basis.z  # Negative Z is forward in Godot
	forward.y = 0  # Keep movement horizontal
	forward = forward.normalized()
	
	# Move the CharacterBody3D
	if agent is CharacterBody3D:
		agent.velocity.x = forward.x * speed
		agent.velocity.z = forward.z * speed
		agent.move_and_slide()
	
	if elapsed_time > duration:
		return SUCCESS
	return RUNNING
