@tool
extends BTAction
## Rotates the agent to face a target in 3D space.
## Adapted for 3D from LimboAI demo.
## Returns SUCCESS when facing the target.

## Blackboard variable that stores the target to face.
@export var target_var: StringName = &"target"

## How fast to rotate (radians per second).
@export var turn_speed: float = 5.0

## Angle tolerance for considering "facing" complete (radians).
@export var angle_tolerance: float = 0.1

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "FaceTarget3D " + LimboUtility.decorate_var(target_var)

# Called each time this task is ticked (aka executed).
func _tick(delta: float) -> Status:
	var target: Node3D = blackboard.get_var(target_var)
	if not is_instance_valid(target):
		return FAILURE
	
	# Calculate direction to target (horizontal only)
	var direction = target.global_position - agent.global_position
	direction.y = 0
	direction = direction.normalized()
	
	if direction.length() < 0.01:
		return SUCCESS  # Too close to determine direction
	
	# Calculate target rotation
	var target_rotation = atan2(direction.x, direction.z)
	var current_rotation = agent.rotation.y
	
	# Calculate angle difference
	var angle_diff = angle_difference(target_rotation, current_rotation)
	
	# Check if we're close enough
	if abs(angle_diff) < angle_tolerance:
		return SUCCESS
	
	# Rotate towards target
	var rotation_step = sign(angle_diff) * min(abs(angle_diff), turn_speed * delta)
	agent.rotation.y += rotation_step
	
	return RUNNING

# Helper function to calculate the shortest angle difference
func angle_difference(target: float, current: float) -> float:
	var diff = target - current
	while diff > PI:
		diff -= 2 * PI
	while diff < -PI:
		diff += 2 * PI
	return diff
