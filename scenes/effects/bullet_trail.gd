extends Node3D
class_name BulletTrail

@export var trail_duration: float = 0.1
@export var trail_width: float = 0.03
@export var trail_color: Color = Color(1, 0.8, 0.2, 0.8)

var trail_mesh: MeshInstance3D
var trail_material: StandardMaterial3D
var cleanup_timer: Timer

func _ready():
	# Timer for self-cleanup
	cleanup_timer = Timer.new()
	cleanup_timer.one_shot = true
	cleanup_timer.wait_time = trail_duration
	add_child(cleanup_timer)
	cleanup_timer.timeout.connect(_on_timeout)

func create_trail(from_position: Vector3, to_position: Vector3):
	var dir: Vector3 = to_position - from_position
	var distance := dir.length()
	if distance <= 0.01:
		queue_free()
		return
	dir = dir.normalized()

	# Create cylinder mesh representing the tracer
	var cyl := CylinderMesh.new()
	cyl.top_radius    = trail_width
	cyl.bottom_radius = trail_width
	cyl.height        = distance

	# Material – glowing colour that fades
	trail_material = StandardMaterial3D.new()
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.albedo_color = trail_color
	trail_material.emission_enabled = true
	trail_material.emission = trail_color
	trail_material.emission_energy_multiplier = 2.0
	trail_material.disable_ambient_light = true
	trail_material.disable_fog = true
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	cyl.material = trail_material

	trail_mesh = MeshInstance3D.new()
	trail_mesh.mesh = cyl
	trail_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail_mesh)

	# Position mesh so its centre is mid-point between from and to
	var mid_point = (from_position + to_position) * 0.5
	global_position = mid_point  # position root at centre

	# Orient the mesh so its local Y axis matches direction vector
	var basis := Vector3.UP.cross(dir)
	if basis.length() < 0.0001:
		basis = Vector3.RIGHT  # fallback if parallel with UP
	var rot_quat = Quaternion(basis.normalized(), acos(Vector3.UP.dot(dir)))
	rotation = rot_quat.get_euler()

	cleanup_timer.start()

func _on_timeout():
	# Fade out then free
	var tween = create_tween()
	tween.tween_property(trail_material, "albedo_color:a", 0.0, 0.05)
	tween.tween_callback(queue_free)

static func create_trail_effect(from_pos: Vector3, to_pos: Vector3, parent_node: Node3D = null):
	var scene := preload("res://scenes/effects/bullet_trail.tscn")
	var trail := scene.instantiate()
	if parent_node:
		parent_node.add_child(trail)
	else:
		var root: Node = Engine.get_main_loop().current_scene
		if root:
			root.add_child(trail)
	trail.create_trail(from_pos, to_pos)
	return trail 
