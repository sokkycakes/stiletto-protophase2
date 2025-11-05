@tool
extends BTAction
## Shoots a projectile at a target in 3D space.
## Adapted for 3D from LimboAI demo.
## Returns SUCCESS when projectile is fired, FAILURE if no target.

## Blackboard variable that stores the target to shoot at.
@export var target_var: StringName = &"target"

## Projectile scene to instantiate.
@export var projectile_scene: PackedScene

## Projectile speed.
@export var projectile_speed: float = 20.0

## Spawn offset from agent position.
@export var spawn_offset: Vector3 = Vector3(0, 1, 0)

# Display a customized name (requires @tool).
func _generate_name() -> String:
	return "ShootProjectile3D " + LimboUtility.decorate_var(target_var)

# Called each time this task is ticked (aka executed).
func _tick(_delta: float) -> Status:
	var target: Node3D = blackboard.get_var(target_var)
	if not is_instance_valid(target):
		return FAILURE

	# Try to use the agent's shoot method if available
	if agent.has_method("shoot_at_target"):
		if agent.shoot_at_target(target):
			return SUCCESS
		else:
			return FAILURE

	# Fallback: manual projectile creation
	if not projectile_scene:
		projectile_scene = preload("res://enemies/projectile_3d.tscn")

	if not projectile_scene:
		return FAILURE

	# Calculate direction to target
	var spawn_pos = agent.global_position + spawn_offset
	var direction = (target.global_position - spawn_pos).normalized()

	# Create and configure projectile
	var projectile = projectile_scene.instantiate()
	agent.get_parent().add_child(projectile)
	projectile.global_position = spawn_pos

	# Set projectile velocity if it has the property
	if projectile.has_method("set_direction"):
		projectile.set_direction(direction)
	elif "velocity" in projectile:
		projectile.velocity = direction * projectile_speed
	elif "linear_velocity" in projectile:
		projectile.linear_velocity = direction * projectile_speed

	# Orient projectile to face direction
	if projectile is Node3D:
		projectile.look_at(spawn_pos + direction, Vector3.UP)

	return SUCCESS
