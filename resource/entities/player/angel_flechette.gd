extends Projectile
class_name AngelFlechette

enum State { FLYING, STUCK }
var current_state: State = State.FLYING

@export var proximity_radius: float = 4.0
@export var connection_radius: float = 15.0
@export var tether_damage: int = 100 # Instakill
@export var stick_damage: int = 2
@export var weakspot_damage: int = 100 # Instakill on weakspot

# Audio
@export var impact_sound: AudioStream
@export var destroy_sound: AudioStream
@export var detonation_sound: AudioStream
@export var audio_bus: String = "SFX"

# References to connected flechettes
var connected_flechettes: Array[AngelFlechette] = []
var tether_lines: Dictionary = {} # Map[AngelFlechette, MeshInstance3D]

# Reference to the weapon that spawned this (for managing the group)
var spawner_weapon: Node3D = null

# Detection area for proximity stun
var proximity_area: Area3D
var proximity_shape: CollisionShape3D

# Beam Material
var beam_material: StandardMaterial3D

signal destroyed(flechette)
signal triggered(flechette, target)

func _ready():
	super._ready()
	add_to_group("angel_flechettes")
	
	if body_entered.is_connected(_on_body_entered):
		body_entered.disconnect(_on_body_entered)
	body_entered.connect(_on_flechette_body_entered)
	
	# Setup proximity area
	proximity_area = Area3D.new()
	proximity_area.name = "ProximityArea"
	add_child(proximity_area)
	
	var sphere = SphereShape3D.new()
	sphere.radius = proximity_radius
	
	proximity_shape = CollisionShape3D.new()
	proximity_shape.shape = sphere
	proximity_area.add_child(proximity_shape)
	
	proximity_area.body_entered.connect(_on_proximity_enter)
	proximity_area.monitorable = false
	proximity_area.monitoring = false
	
	# Initialize Beam Material
	beam_material = StandardMaterial3D.new()
	beam_material.albedo_color = Color(0.4, 0.9, 1.0, 1.0)
	beam_material.emission_enabled = true
	beam_material.emission = Color(0.2, 0.8, 1.0)
	beam_material.emission_energy_multiplier = 3.0
	beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Optional: Add a texture if available, or just use color

func _physics_process(delta):
	if current_state == State.STUCK:
		return

	if has_hit:
		return
	
	var next_pos = position + direction * speed * delta
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(position, next_pos)
	
	var exclude_list: Array = [self]
	exclude_list.append_array(owner_exclusions)
	if proximity_area:
		exclude_list.append(proximity_area)
	query.exclude = exclude_list
	
	query.collision_mask = 0xFFFFFFFF 
	query.hit_from_inside = true
	
	var result = space_state.intersect_ray(query)
	if result:
		has_hit = true
		var collider = result.collider
		var hit_pos = result.position
		var hit_normal = result.normal
		
		if is_owner(collider):
			destroy()
			return
			
		handle_impact(collider, hit_pos, hit_normal)
	else:
		position = next_pos
		previous_position = position
		if direction != Vector3.ZERO:
			look_at(position + direction)

func _process(delta):
	# Update beam visuals every frame to face camera
	if current_state == State.STUCK and not tether_lines.is_empty():
		update_beam_visuals()

func _on_flechette_body_entered(body):
	if has_hit: return
	if is_owner(body): return
	
	has_hit = true
	handle_impact(body, global_position, -direction)

func handle_impact(collider: Node, hit_pos: Vector3, hit_normal: Vector3):
	spawn_impact_particle(hit_pos, hit_normal)
	
	# Play impact sound
	if impact_sound:
		_play_sound_3d(impact_sound, hit_pos)
	
	var receiver = _find_damage_receiver(collider)
	if receiver and not is_owner(receiver):
		if not is_visual_only:
			var dmg = stick_damage
			if collider.name.to_lower().contains("head") or collider.is_in_group("weakspot"):
				dmg = weakspot_damage
				
			if receiver is NetworkedPlayer:
				var receiver_np := receiver as NetworkedPlayer
				var attacker_peer_id := owner_peer_id if owner_peer_id >= 0 else -1
				var target_peer_id := receiver_np.peer_id if receiver_np else -1
				receiver.apply_damage.rpc_id(target_peer_id, float(dmg), attacker_peer_id, target_peer_id)
			elif receiver.has_method("take_damage"):
				receiver.take_damage(dmg)
			
		destroy()
		return

	stick_to_surface(collider, hit_pos, hit_normal)

func stick_to_surface(collider: Node, hit_pos: Vector3, hit_normal: Vector3):
	current_state = State.STUCK
	global_position = hit_pos
	
	if hit_normal != Vector3.UP and hit_normal != Vector3.DOWN:
		look_at(hit_pos + hit_normal, Vector3.UP)
	elif hit_normal == Vector3.UP:
		look_at(hit_pos + hit_normal, Vector3.BACK)
	elif hit_normal == Vector3.DOWN:
		look_at(hit_pos + hit_normal, Vector3.FORWARD)
		
	if collider.get_parent() and not (collider is StaticBody3D or collider is CSGShape3D):
		var parent = collider
		reparent.call_deferred(parent)
		
	proximity_area.monitoring = true
	if timer: timer.stop()
	
	if spawner_weapon and spawner_weapon.has_method("on_flechette_stuck"):
		spawner_weapon.on_flechette_stuck(self)
		
	call_deferred("scan_and_connect")

func scan_and_connect():
	var others = get_tree().get_nodes_in_group("angel_flechettes")
	for other in others:
		if other == self: continue
		if not is_instance_valid(other): continue
		if other.current_state != State.STUCK: continue
		if other.owner_peer_id != self.owner_peer_id: continue
		
		var dist = global_position.distance_to(other.global_position)
		if dist <= connection_radius:
			connect_to(other)
			other.connect_to(self)

func connect_to(other: AngelFlechette):
	if other in connected_flechettes:
		return
		
	connected_flechettes.append(other)
	create_tether_visual(other)

func disconnect_from(other: AngelFlechette):
	if other in connected_flechettes:
		connected_flechettes.erase(other)
		remove_tether_visual(other)

func create_tether_visual(other: AngelFlechette):
	if tether_lines.has(other): return
	
	# Create MeshInstance with ImmediateMesh for dynamic beam
	var mesh_inst = MeshInstance3D.new()
	var imm_mesh = ImmediateMesh.new()
	
	mesh_inst.mesh = imm_mesh
	mesh_inst.material_override = beam_material
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# We use global coordinates for drawing to simplify connecting two moving objects
	mesh_inst.top_level = true 
	
	get_tree().current_scene.add_child(mesh_inst)
	tether_lines[other] = mesh_inst

func remove_tether_visual(other: AngelFlechette):
	if tether_lines.has(other):
		var line = tether_lines[other]
		if is_instance_valid(line):
			line.queue_free()
		tether_lines.erase(other)

func update_beam_visuals():
	var cam = get_viewport().get_camera_3d()
	if not cam: return
	
	var cam_pos = cam.global_position
	var width = 0.15
	
	for other in tether_lines.keys():
		if not is_instance_valid(other):
			continue
			
		var mesh_inst = tether_lines[other]
		if not is_instance_valid(mesh_inst):
			continue
			
		var start = global_position
		var end = other.global_position
		
		# Calculate billboard vector
		var dir = (end - start).normalized()
		var view_vec = (cam_pos - start).normalized()
		var normal = dir.cross(view_vec).normalized()
		
		# If looking directly down the line, normal might be zero
		if normal.length_squared() < 0.001:
			normal = Vector3.UP.cross(dir).normalized()
			
		var offset = normal * (width * 0.5)
		
		# Update mesh
		var imm = mesh_inst.mesh as ImmediateMesh
		imm.clear_surfaces()
		imm.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		
		# Add simple quad
		# We can add segments for "sag" or texture repeat if needed
		# For a straight beam:
		
		# Vertices
		imm.surface_set_uv(Vector2(0, 0))
		imm.surface_add_vertex(start - offset)
		
		imm.surface_set_uv(Vector2(0, 1))
		imm.surface_add_vertex(start + offset)
		
		imm.surface_set_uv(Vector2(1, 0))
		imm.surface_add_vertex(end - offset)
		
		imm.surface_set_uv(Vector2(1, 1))
		imm.surface_add_vertex(end + offset)
		
		imm.surface_end()

func _on_proximity_enter(body):
	if current_state != State.STUCK: return
	if body == owner_node: return
	if is_visual_only: return
		
	if connected_flechettes.is_empty():
		stun_target(body)

func stun_target(body):
	print("Stun triggered on ", body.name)
	if body.has_method("apply_status"):
		body.apply_status("stun", 2.0)
	destroy()

func detonate():
	print("Detonating flechette")
	# Only play sound if we're the first in the network (to avoid multiple sounds)
	# The weapon will handle playing the sound on the first flechette
	# Don't play destroy sound when detonating
	destroy(false)

func play_detonation_sound():
	if detonation_sound:
		_play_sound_3d_detonation(detonation_sound, global_position)

func play_destroy_sound():
	if destroy_sound:
		_play_sound_3d(destroy_sound, global_position)

func destroy(play_destroy_sound_on_removal: bool = true):
	# Play destroy sound only when manually removed (not when detonating)
	# This is player feedback to confirm they properly removed their flechette
	if play_destroy_sound_on_removal and destroy_sound:
		play_destroy_sound()
	
	destroyed.emit(self)
	for neighbor in connected_flechettes:
		if is_instance_valid(neighbor):
			neighbor.disconnect_from(self)
	
	# Clean up visuals
	for other in tether_lines.keys():
		var line = tether_lines[other]
		if is_instance_valid(line):
			line.queue_free()
	tether_lines.clear()
	
	if is_in_group("angel_flechettes"):
		remove_from_group("angel_flechettes")
		
	super.destroy()

func _play_sound_3d(sound: AudioStream, position: Vector3) -> void:
	if not sound or is_visual_only:
		return
		
	var player = AudioStreamPlayer3D.new()
	player.stream = sound
	player.bus = audio_bus
	player.global_position = position
	player.max_distance = 50.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	
	get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())

func _play_sound_3d_detonation(sound: AudioStream, position: Vector3) -> void:
	if not sound or is_visual_only:
		return
		
	var player = AudioStreamPlayer3D.new()
	player.stream = sound
	player.bus = audio_bus
	player.global_position = position
	player.max_distance = 200.0  # Much larger radius for detonation
	player.volume_db = 6.0  # Louder (6dB increase = roughly 2x perceived volume)
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	
	get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(func(): player.queue_free())
