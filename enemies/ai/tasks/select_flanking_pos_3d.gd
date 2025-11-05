@tool
extends BTAction
## Selects a flanking position around a target in 3D space.
## Adapted for 3D from LimboAI demo.
## Returns SUCCESS when a flanking position is selected.

## Blackboard variable that stores the target to flank.
@export var target_var: StringName = &"target"

## Blackboard variable to store the selected flanking position.
@export var pos_var: StringName = &"flanking_pos"

## Distance from target to position flanking point.
@export var flank_distance: float = 8.0

## How far to the side to position (0.0 = directly behind, 1.0 = to the side).
@export var side_offset: float = 0.7

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "SelectFlankingPos3D %s → %s" % [
		LimboUtility.decorate_var(target_var),
		LimboUtility.decorate_var(pos_var)]

# Called each time this task is ticked (aka executed).
func _tick(_delta: float) -> Status:
	var target: Node3D = blackboard.get_var(target_var)
	if not is_instance_valid(target):
		return FAILURE
	
	# Get direction from target to agent
	var to_agent = agent.global_position - target.global_position
	to_agent.y = 0  # Keep horizontal
	to_agent = to_agent.normalized()
	
	# Create flanking direction by rotating around Y axis
	var flank_angle = PI * side_offset * (1.0 if randf() > 0.5 else -1.0)
	var flank_dir = Vector3(
		to_agent.x * cos(flank_angle) - to_agent.z * sin(flank_angle),
		0,
		to_agent.x * sin(flank_angle) + to_agent.z * cos(flank_angle)
	)
	
	# Calculate flanking position
	var flanking_pos = target.global_position + flank_dir * flank_distance
	
	# Store the position in blackboard
	blackboard.set_var(pos_var, flanking_pos)
	
	return SUCCESS
