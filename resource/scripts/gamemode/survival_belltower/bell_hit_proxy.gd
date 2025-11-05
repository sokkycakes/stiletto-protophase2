extends StaticBody3D

# Bell Hit Proxy
# Attach this to the bell's collision body (StaticBody3D or Area3D).
# It forwards any take_damage() call from the weapon system to the main BellController.

@export var bell_controller_path: NodePath = NodePath("..")

var bell_controller: Node

func _ready():
	bell_controller = get_node_or_null(bell_controller_path)
	if not bell_controller:
		print("[BellHitProxy] BellController not found via path: ", bell_controller_path)
	else:
		print("[BellHitProxy] Connected to BellController: ", bell_controller.name)

# Called by weapon_system.gd when the collider is hit via hitscan ray
func take_damage(damage_amount := 0, attacker: Variant = null):
	if bell_controller and bell_controller.has_method("ring"):
		bell_controller.ring()
	else:
		print("[BellHitProxy] BellController not available to ring") 