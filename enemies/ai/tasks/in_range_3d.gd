@tool
extends BTCondition
## Checks if a target is within a specified range in 3D space.
## Adapted for 3D from LimboAI demo.
## Returns SUCCESS if target is in range, FAILURE otherwise.

## Blackboard variable that stores the target to check distance to.
@export var target_var: StringName = &"target"

## Maximum distance to consider the target "in range".
@export var range: float = 3.0

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "InRange3D %s ≤ %s" % [LimboUtility.decorate_var(target_var), range]

# Called each time this task is ticked (aka executed).
func _tick(_delta: float) -> Status:
	var target: Node3D = blackboard.get_var(target_var)
	if not is_instance_valid(target):
		return FAILURE
	
	var distance = agent.global_position.distance_to(target.global_position)
	if distance <= range:
		return SUCCESS
	else:
		return FAILURE
