@tool
extends BTAction
## Gets the first node from a specified group and stores it in the blackboard.
## Adapted for 3D from LimboAI demo.
## Returns SUCCESS if a node is found, FAILURE otherwise.

## Group name to search for nodes.
@export var group_name: StringName = &"player"

## Blackboard variable to store the found node.
@export var output_var: StringName = &"target"

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "GetFirstInGroup3D group: %s → %s" % [group_name, LimboUtility.decorate_var(output_var)]

# Called each time this task is ticked (aka executed).
func _tick(_delta: float) -> Status:
	var nodes = agent.get_tree().get_nodes_in_group(group_name)
	if nodes.size() == 0:
		return FAILURE
	
	# Find the first valid 3D node
	for node in nodes:
		if is_instance_valid(node) and node is Node3D:
			blackboard.set_var(output_var, node)
			return SUCCESS
	
	return FAILURE
