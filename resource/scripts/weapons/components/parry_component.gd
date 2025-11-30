extends Node
class_name ParryComponent

## Standalone parry component that can be added to any weapon as a child node.
## Activates a hitbox when the weapon attacks, allowing projectiles to be parried/reflected.

# Configuration
@export_group("Parry Settings")
@export var parry_hitbox_duration: float = 0.2  # How long the parry hitbox stays active (seconds)
@export var parry_hitbox_width: float = 2.04  # Width of parry hitbox (meters)
@export var parry_hitbox_height: float = 0.68  # Height of parry hitbox (meters)
@export var parry_reflect_speed_multiplier: float = 1.2  # Speed multiplier for reflected projectiles
@export var parry_push_distance: float = 0.5  # Distance to push projectile forward after parry (meters)

@export_group("Visual Feedback")
@export var parry_sound: AudioStream  # Sound when parrying a projectile
@export var impact_effect_scene: PackedScene  # Effect to spawn at parry contact point
@export var show_parry_hitbox_visualizer: bool = false  # Show visual debug box for parry hitbox

@export_group("Debug")
@export var debug_logging: bool = false

# References (set by parent weapon or auto-detected)
@export var camera: Camera3D  # Camera for aim direction (auto-detected if not set)
@export var melee_range: float = 2.2  # Melee range for hitbox positioning (set by parent)

# Internal state
var _parry_hitbox_active: bool = false
var _parry_hitbox_timer: float = 0.0
var _parried_projectiles: Array = []  # Track projectiles that have already been parried
var _parry_hitbox_visualizer: MeshInstance3D = null

# Signals
signal projectile_parried(projectile: Area3D)  # Emitted when a projectile is successfully parried

func _ready() -> void:
	# Auto-detect camera if not set
	if not camera:
		_find_camera()
	
	# Create visualizer if debug setting is enabled
	if show_parry_hitbox_visualizer:
		_create_parry_hitbox_visualizer()

func _process(delta: float) -> void:
	# Update parry hitbox and check for projectiles
	if _parry_hitbox_active:
		_update_parry_hitbox(delta)

## Activate the parry hitbox (call this when weapon attacks)
func activate() -> void:
	_parry_hitbox_active = true
	_parry_hitbox_timer = parry_hitbox_duration
	_parried_projectiles.clear()
	if debug_logging:
		print("[ParryComponent] Parry hitbox activated for %.2f seconds" % parry_hitbox_duration)

## Deactivate the parry hitbox manually (optional)
func deactivate() -> void:
	_parry_hitbox_active = false
	_parried_projectiles.clear()
	if show_parry_hitbox_visualizer:
		_hide_parry_hitbox_visualizer()

func _find_camera() -> void:
	"""Auto-detect camera from parent weapon or scene"""
	# Try to find camera in parent weapon's hierarchy
	var parent = get_parent()
	if parent:
		# Check if parent has a camera reference (e.g., WeaponManager)
		if "camera" in parent:
			camera = parent.camera
			return
		
		# Search parent's children for Camera3D
		var cameras = _find_nodes_of_type(parent, Camera3D)
		if cameras.size() > 0:
			camera = cameras[0]
			return
	
	# Fallback: search scene for active camera
	var scene_root = get_tree().current_scene if get_tree() else null
	if scene_root:
		var cameras = _find_nodes_of_type(scene_root, Camera3D)
		for cam in cameras:
			if cam.current:
				camera = cam
				return

func _find_nodes_of_type(root: Node, node_type: Variant) -> Array:
	"""Recursively find all nodes of a specific type"""
	var results: Array = []
	# Check if root matches the type
	# For Camera3D specifically, use direct type check
	if node_type == Camera3D and root is Camera3D:
		results.append(root)
	elif node_type is String and root.get_class() == node_type:
		results.append(root)
	
	for child in root.get_children():
		results.append_array(_find_nodes_of_type(child, node_type))
	
	return results

func _get_world_3d() -> World3D:
	"""Get World3D from scene tree or parent Node3D"""
	# Try to get from scene tree
	if is_inside_tree():
		var scene = get_tree().current_scene
		if scene and scene is Node3D:
			return (scene as Node3D).get_world_3d()
	
	# Try to get from parent Node3D
	var parent = get_parent()
	if parent and parent is Node3D:
		return (parent as Node3D).get_world_3d()
	
	return null

func _update_parry_hitbox(delta: float) -> void:
	"""Update parry hitbox each frame and check for projectiles"""
	if not _parry_hitbox_active:
		return
	
	# Decrement timer
	_parry_hitbox_timer -= delta
	if _parry_hitbox_timer <= 0.0:
		_parry_hitbox_active = false
		_parried_projectiles.clear()
		if show_parry_hitbox_visualizer:
			_hide_parry_hitbox_visualizer()
		return
	
	# Ensure we have a camera
	if not camera:
		_find_camera()
		if not camera:
			_parry_hitbox_active = false
			return
	
	# Position hitbox in front of player (at melee range)
	var origin: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var hitbox_center = origin + forward * (melee_range * 0.5)  # Center of melee range
	
	# Use a box shape for the parry hitbox
	var world = _get_world_3d()
	if not world:
		return
	var space_state = world.direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(parry_hitbox_width, parry_hitbox_height, melee_range)
	query.shape = box_shape
	
	# Position and orient the hitbox
	var hitbox_transform = Transform3D()
	hitbox_transform.origin = hitbox_center
	var up = camera.global_transform.basis.y
	var right = camera.global_transform.basis.x
	hitbox_transform.basis = Basis(right, up, -forward)
	query.transform = hitbox_transform
	
	query.collide_with_areas = true
	query.collide_with_bodies = false  # Only interested in areas (projectiles)
	query.exclude = [self]
	
	# Update visualizer position and visibility
	if show_parry_hitbox_visualizer:
		_update_parry_hitbox_visualizer(hitbox_transform)
	
	# Check for projectiles in the hitbox
	var results = space_state.intersect_shape(query, 32)
	
	for result in results:
		var area = result.get("collider") as Area3D
		if area and _is_projectile(area):
			# Check if this projectile has already been parried
			if area in _parried_projectiles:
				continue
			
			# Found a parryable projectile!
			if debug_logging:
				print("[ParryComponent] Projectile detected in parry hitbox: ", area.name)
			
			# Mark as parried before actually parrying (prevents double-parry in same frame)
			_parried_projectiles.append(area)
			_parry_projectile(area)
			projectile_parried.emit(area)
			# Only parry one projectile per frame
			break

func _is_projectile(area: Area3D) -> bool:
	"""Check if an area is a projectile that can be parried"""
	if not area:
		return false
	
	# Check if it has projectile properties
	if area.has_method("set_owner_info") or area.has_method("set_owner"):
		return true
	
	# Check for common projectile properties
	if "owner_peer_id" in area or "owner_node" in area or "direction" in area:
		return true
	
	# Check if it's a known projectile class
	if area is Projectile or (area.get_script() and "Projectile" in str(area.get_script().resource_path)):
		return true
	
	return false

func _parry_projectile(projectile: Area3D) -> void:
	"""Parry/reflect a projectile in the direction the parrier is looking"""
	if not projectile:
		return
	
	if debug_logging:
		print("[ParryComponent] Parrying projectile: ", projectile.name)
	
	# Get contact point for impact effect (before moving the projectile)
	var contact_position: Vector3 = Vector3.ZERO
	var contact_normal: Vector3 = Vector3.UP
	if projectile is Node3D:
		contact_position = (projectile as Node3D).global_position
		# Normal is opposite of incoming direction
		if "direction" in projectile:
			contact_normal = -projectile.direction.normalized()
		else:
			# Fallback: use camera forward
			if camera:
				contact_normal = -camera.global_transform.basis.z
	
	# Play parry sound
	if parry_sound:
		_play_sound(parry_sound)
	
	# Spawn impact effect at contact point
	if impact_effect_scene:
		_spawn_impact(contact_position, contact_normal)
	
	# Get parrier's NetworkedPlayer
	var parrier_np = _get_networked_player()
	var parrier_peer_id: int = -1
	var parrier_node: Node3D = null
	
	if parrier_np:
		parrier_peer_id = parrier_np.peer_id
		var parrier_body = parrier_np.get_node_or_null("Body")
		if parrier_body and parrier_body is Node3D:
			parrier_node = parrier_body
		else:
			parrier_node = parrier_np
	
	# Reflect projectile in the direction the parrier is looking (TF2 airblast style)
	# Use raycast to determine precise aim direction (where crosshair is pointing)
	var reflect_direction: Vector3 = Vector3.FORWARD
	if camera:
		# Cast a ray from camera to determine where player is actually aiming
		var ray_start = camera.global_position
		var ray_end = ray_start + (-camera.global_transform.basis.z * 1000.0)  # Long range ray
		
		var world = _get_world_3d()
		if not world:
			reflect_direction = -camera.global_transform.basis.z.normalized()
		else:
			var space_state = world.direct_space_state
			var ray_query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
			ray_query.exclude = [self]
			if parrier_node:
				# Exclude parrier's collision bodies from raycast
				var parrier_exclusions = _get_parrier_collision_bodies(parrier_node)
				ray_query.exclude.append_array(parrier_exclusions)
			
			var ray_result = space_state.intersect_ray(ray_query)
			
			if ray_result.has("position"):
				# Ray hit something - reflect towards the hit point
				var hit_point = ray_result.get("position")
				reflect_direction = (hit_point - projectile.global_position).normalized()
			else:
				# Ray didn't hit anything - use camera forward direction
				reflect_direction = -camera.global_transform.basis.z.normalized()
	elif parrier_node:
		# Fallback: use parrier's forward direction
		reflect_direction = -parrier_node.global_transform.basis.z.normalized()
	
	reflect_direction = reflect_direction.normalized()
	
	# CRITICAL: Change ownership FIRST before updating direction
	if parrier_node and parrier_peer_id >= 0:
		var parrier_exclusions = _get_parrier_collision_bodies(parrier_node)
		
		# Use set_owner_info if available (preferred method)
		if projectile.has_method("set_owner_info"):
			projectile.set_owner_info(parrier_node, parrier_peer_id)
		else:
			# Direct property assignment
			if "owner_node" in projectile:
				projectile.owner_node = parrier_node
			if "owner_peer_id" in projectile:
				projectile.owner_peer_id = parrier_peer_id
		
		# Update owner exclusions
		if "owner_exclusions" in projectile:
			projectile.owner_exclusions = parrier_exclusions
			if debug_logging:
				print("[ParryComponent] Updated owner_exclusions: ", parrier_exclusions.size(), " bodies")
	
	# Move projectile forward in the new direction to avoid immediate collision
	if projectile is Node3D:
		var proj_node = projectile as Node3D
		var new_position = proj_node.global_position + reflect_direction * parry_push_distance
		
		# Update both global_position and position
		proj_node.global_position = new_position
		if "position" in projectile:
			if proj_node.get_parent():
				projectile.position = proj_node.get_parent().to_local(new_position)
			else:
				projectile.position = new_position
		
		# Update previous_position
		if "previous_position" in projectile:
			projectile.previous_position = new_position
		elif "position" in projectile:
			projectile.previous_position = projectile.position
	
	# Update projectile direction AFTER ownership is set
	if "direction" in projectile:
		projectile.direction = reflect_direction
		if "speed" in projectile and parry_reflect_speed_multiplier != 1.0:
			projectile.speed *= parry_reflect_speed_multiplier
	
	# Update projectile rotation to face new direction
	if projectile is Node3D:
		var proj_node = projectile as Node3D
		proj_node.look_at(proj_node.global_position + reflect_direction)
	
	if debug_logging:
		print("[ParryComponent] Projectile parried! New owner: ", parrier_peer_id, ", direction: ", reflect_direction)

func _get_networked_player() -> NetworkedPlayer:
	"""Get the NetworkedPlayer that owns this weapon"""
	var node = get_parent()
	var depth = 0
	while node and depth < 10:
		if node is NetworkedPlayer:
			return node as NetworkedPlayer
		# Check if node has a method to get NetworkedPlayer
		if node.has_method("_get_networked_player_for_attacker"):
			var np = node._get_networked_player_for_attacker()
			if np:
				return np
		node = node.get_parent()
		depth += 1
	return null

func _get_parrier_collision_bodies(parrier: Node3D) -> Array:
	"""Get all collision bodies from the parrier for exclusion"""
	var collision_bodies: Array = []
	if not parrier:
		return collision_bodies
	
	# Recursively collect all CollisionObject3D nodes
	var nodes_to_check: Array = [parrier]
	while nodes_to_check.size() > 0:
		var current_node = nodes_to_check.pop_back()
		
		if current_node is CollisionObject3D:
			collision_bodies.append(current_node)
		
		# Add children to check
		for child in current_node.get_children():
			nodes_to_check.append(child)
	
	return collision_bodies

func _create_parry_hitbox_visualizer() -> void:
	"""Create a visual mesh to show the parry hitbox"""
	_parry_hitbox_visualizer = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(parry_hitbox_width, parry_hitbox_height, melee_range)
	_parry_hitbox_visualizer.mesh = box_mesh
	
	# Create a material for the visualizer
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.0, 1.0, 0.0, 0.3)  # Green, semi-transparent
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.flags_wireframe = true
	_parry_hitbox_visualizer.material_override = material
	
	# Add to scene tree
	var scene_root = get_tree().current_scene if get_tree() else null
	if scene_root:
		scene_root.add_child(_parry_hitbox_visualizer)
	else:
		# Fallback: add as child
		add_child(_parry_hitbox_visualizer)
	
	_parry_hitbox_visualizer.visible = false

func _update_parry_hitbox_visualizer(transform: Transform3D) -> void:
	"""Update the visualizer position and make it visible"""
	if not _parry_hitbox_visualizer:
		return
	
	_parry_hitbox_visualizer.global_transform = transform
	_parry_hitbox_visualizer.visible = true

func _hide_parry_hitbox_visualizer() -> void:
	"""Hide the visualizer"""
	if _parry_hitbox_visualizer:
		_parry_hitbox_visualizer.visible = false

func _play_sound(sound: AudioStream) -> void:
	"""Play a sound effect"""
	if not sound:
		return
	
	var audio_player = AudioStreamPlayer.new()
	audio_player.stream = sound
	add_child(audio_player)
	audio_player.play()
	audio_player.finished.connect(func(): audio_player.queue_free())

func _spawn_impact(position: Vector3, normal: Vector3) -> void:
	"""Spawn impact effect at position"""
	if not impact_effect_scene:
		return
	
	var effect = impact_effect_scene.instantiate()
	var scene_root = get_tree().current_scene if get_tree() else null
	if scene_root:
		scene_root.add_child(effect)
		if effect is Node3D:
			effect.global_position = position
			effect.look_at(position + normal)
