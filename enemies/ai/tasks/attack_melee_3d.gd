@tool
extends BTAction
## Performs a melee attack in 3D space, integrating with your attack system.
## Adapted for 3D from LimboAI demo and your existing attack systems.
## Returns SUCCESS when attack is performed, FAILURE if no target or can't attack.

## Blackboard variable that stores the target to attack.
@export var target_var: StringName = &"target"

## Attack range.
@export var attack_range: float = 2.0

## Attack damage.
@export var damage: float = 25.0

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "AttackMelee3D " + LimboUtility.decorate_var(target_var)

# Called each time this task is ticked (aka executed).
func _tick(_delta: float) -> Status:
	var target: Node3D = blackboard.get_var(target_var)
	if not is_instance_valid(target):
		return FAILURE
	
	# Check if target is in range
	var distance = agent.global_position.distance_to(target.global_position)
	if distance > attack_range:
		return FAILURE
	
	# Try to use existing attack system
	if agent.has_node("AttackSystem"):
		var attack_system = agent.get_node("AttackSystem")
		if attack_system.has_method("start_attack"):
			attack_system.start_attack()
			return SUCCESS
	
	# Fallback: direct damage if target has take_damage method
	if target.has_method("take_damage"):
		target.take_damage(damage)
		return SUCCESS
	elif target.has_method("take_hit"):
		target.take_hit()
		return SUCCESS
	
	return FAILURE
