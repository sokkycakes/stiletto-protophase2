extends BaseWeapon
class_name AngelSniper

# References
@export var flechette_scene: PackedScene
@export var max_active_flechettes: int = 3
@export var connection_distance: float = 15.0

# Audio
@export var fire_sound: AudioStream
@export var airblast_sound: AudioStream

# Airblast properties
@export var airblast_range: float = 15.0
@export var airblast_cone_angle: float = 45.0  # Degrees
@export var airblast_force: float = 500.0
@export var airblast_cooldown: float = 0.5
@export var airblast_ammo_cost: int = 0  # 0 = no ammo cost

# State
var active_flechettes: Array[AngelFlechette] = []
# Map ID -> Flechette for networking
var networked_flechettes: Dictionary = {} # ID (int) -> AngelFlechette
var next_flechette_id: int = 0

# Airblast state
var _can_airblast: bool = true
var _airblast_timer: Timer

func _ready():
	super._ready()
	
	# Setup airblast timer
	_airblast_timer = Timer.new()
	_airblast_timer.one_shot = true
	_airblast_timer.timeout.connect(_on_airblast_timeout)
	add_child(_airblast_timer)

func shoot():
	if not _can_fire:
		return
		
	super.shoot() 
	
	# Play fire sound
	if fire_sound:
		_play_sound(fire_sound)
	
	spawn_flechette()

func spawn_flechette():
	if not flechette_scene:
		push_warning("AngelSniper: No flechette scene assigned")
		return
		
	var muzzle = get_node_or_null(muzzle_path)
	if not muzzle: muzzle = self 
		
	var spawn_pos = muzzle.global_position
	var spawn_rot = muzzle.global_transform.basis
	var dir = -spawn_rot.z 
	
	if spread_degrees > 0:
		var spread_rad = deg_to_rad(spread_degrees)
		dir = dir.rotated(spawn_rot.x, randf_range(-spread_rad, spread_rad))
		dir = dir.rotated(spawn_rot.y, randf_range(-spread_rad, spread_rad))
	dir = dir.normalized()
	
	var owner_id = -1
	if multiplayer.has_multiplayer_peer():
		owner_id = multiplayer.get_unique_id()
	
	# Generate ID
	var fid = next_flechette_id
	next_flechette_id += 1
	
	# Spawn locally (Authority)
	_spawn_flechette_instance(spawn_pos, dir, owner_id, fid, false)
	
	# RPC Clients
	client_spawn_flechette.rpc(spawn_pos, dir, owner_id, fid)

@rpc("authority", "call_remote", "reliable")
func client_spawn_flechette(pos: Vector3, dir: Vector3, owner_id: int, fid: int):
	_spawn_flechette_instance(pos, dir, owner_id, fid, true)

func _spawn_flechette_instance(pos: Vector3, dir: Vector3, owner_id: int, fid: int, is_visual: bool):
	var proj = flechette_scene.instantiate() as AngelFlechette
	get_tree().current_scene.add_child(proj)
	
	proj.initialize(pos, dir, self, owner_id)
	proj.spawner_weapon = self
	proj.is_visual_only = is_visual
	
	# Store reference
	networked_flechettes[fid] = proj
	
	# If Authority, manage active list
	if not is_visual:
		register_flechette(proj, fid)
	else:
		# Clients just track it for destruction via ID
		pass
		
	# Cleanup on destroy (remove from map)
	proj.destroyed.connect(func(_f): 
		networked_flechettes.erase(fid)
	)

func register_flechette(f: AngelFlechette, fid: int):
	active_flechettes = active_flechettes.filter(func(x): return is_instance_valid(x))
	
	if active_flechettes.size() >= max_active_flechettes:
		var old = active_flechettes.pop_front()
		if is_instance_valid(old):
			# Find ID of old
			var old_id = networked_flechettes.find_key(old)
			if old_id != null:
				destroy_flechette_networked(old_id)
			else:
				old.destroy()
			
	active_flechettes.append(f)

func destroy_flechette_networked(fid: int):
	if networked_flechettes.has(fid):
		var f = networked_flechettes[fid]
		if is_instance_valid(f):
			f.destroy()
	
	client_destroy_flechette.rpc(fid)

@rpc("authority", "call_remote", "reliable")
func client_destroy_flechette(fid: int, is_detonation: bool = false):
	if networked_flechettes.has(fid):
		var f = networked_flechettes[fid]
		if is_instance_valid(f):
			f.destroy(not is_detonation)  # Play sound only if not a detonation
		networked_flechettes.erase(fid)

func on_flechette_stuck(_f: AngelFlechette):
	# Authority logic if needed
	pass

func _input(event):
	if not is_multiplayer_authority():
		return
		
	if Input.is_action_just_pressed("reload"):
		if check_reload_interaction():
			pass # Suppress default reload?
	
	# Handle altfire (airblast)
	if Input.is_action_just_pressed("altfire"):
		perform_airblast()

func check_reload_interaction() -> bool:
	var camera = get_viewport().get_camera_3d()
	if not camera: return false
		
	var origin = camera.global_position
	var dir = -camera.global_transform.basis.z
	var dist = 100.0 
	
	# First check if looking at fence area (3 connected flechettes)
	# This takes priority - detonate the network without destroying flechettes
	if check_aim_at_fence(origin, dir, dist):
		detonate_network()
		return true
	
	# Then check if looking at individual flechette
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(origin, origin + dir * dist)
	query.collide_with_areas = true
	query.collision_mask = 0xFFFFFFFF 
	
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		var flechette = _resolve_flechette(collider)
		if flechette and flechette in active_flechettes:
			# Always allow destroying individual flechettes, even if connected
			# (2 connected can be removed individually, only 3 connected fence area triggers detonation)
			var fid = networked_flechettes.find_key(flechette)
			if fid != null:
				destroy_flechette_networked(fid)
			else:
				flechette.destroy()
			return true 

	return false

func _resolve_flechette(node: Node) -> AngelFlechette:
	var p = node
	while p:
		if p is AngelFlechette:
			return p
		p = p.get_parent()
	return null

func check_aim_at_fence(origin: Vector3, dir: Vector3, max_dist: float) -> bool:
	# Only check for 3 connected flechettes forming a fence
	var stuck = active_flechettes.filter(func(f): return is_instance_valid(f) and f.current_state == AngelFlechette.State.STUCK)
	if stuck.size() < 3: return false
	
	# Check if all 3 are connected to each other (forming a complete network)
	# For simplicity, if we have exactly 3 stuck flechettes, check if they form a triangle
	var f1 = stuck[0]
	var f2 = stuck[1]
	var f3 = stuck[2]
	
	# Check if they're all connected (each should be connected to the other two)
	var f1_connected = f1.connected_flechettes
	var f2_connected = f2.connected_flechettes
	var f3_connected = f3.connected_flechettes
	
	var all_connected = (f2 in f1_connected and f3 in f1_connected) and \
						(f1 in f2_connected and f3 in f2_connected) and \
						(f1 in f3_connected and f2 in f3_connected)
	
	if not all_connected:
		return false
	
	# Check if ray intersects the triangle formed by the 3 flechettes
	var intersect = Geometry3D.ray_intersects_triangle(origin, dir, f1.global_position, f2.global_position, f3.global_position)
	if intersect and origin.distance_to(intersect) <= max_dist:
		return true
				
	return false

func get_segment_distance_to_ray(seg_a: Vector3, seg_b: Vector3, ray_o: Vector3, ray_d: Vector3) -> float:
	var ray_end = ray_o + ray_d * 1000.0
	var pts = Geometry3D.get_closest_points_between_segments(seg_a, seg_b, ray_o, ray_end)
	return pts[0].distance_to(pts[1])

func detonate_network():
	# Only detonate if we have exactly 3 connected flechettes
	var stuck = active_flechettes.filter(func(f): return is_instance_valid(f) and f.current_state == AngelFlechette.State.STUCK)
	if stuck.size() < 3:
		return
	
	# Verify all 3 are connected to each other
	var f1 = stuck[0]
	var f2 = stuck[1]
	var f3 = stuck[2]
	
	var f1_connected = f1.connected_flechettes
	var f2_connected = f2.connected_flechettes
	var f3_connected = f3.connected_flechettes
	
	var all_connected = (f2 in f1_connected and f3 in f1_connected) and \
						(f1 in f2_connected and f3 in f2_connected) and \
						(f1 in f3_connected and f2 in f3_connected)
	
	if not all_connected:
		return
	
	# Kill players inside the perimeter (explosion damage)
	kill_inside_perimeter(stuck)
	
	# Play detonation sound on first flechette
	if f1.has_method("play_detonation_sound"):
		f1.play_detonation_sound()
	
	# Destroy all flechettes in the network (like TF2 stickybombs)
	# Copy list to avoid modification during iteration
	var to_destroy = stuck.duplicate()
	for f in to_destroy:
		var fid = networked_flechettes.find_key(f)
		if fid != null:
			# Destroy without playing destroy sound (detonation sound already played)
			if networked_flechettes.has(fid):
				var flechette = networked_flechettes[fid]
				if is_instance_valid(flechette):
					flechette.destroy(false)
				networked_flechettes.erase(fid)
			# Tell clients to destroy without playing destroy sound
			client_destroy_flechette.rpc(fid, true)  # true = is_detonation
		else:
			f.destroy(false)

func kill_inside_perimeter(flechettes: Array):
	var points = flechettes.map(func(f): return f.global_position)
	var victims = get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("enemy")
	
	for entity in victims:
		if entity == self.owner: continue
		if is_inside_triangle_prism(entity.global_position, points[0], points[1], points[2]):
			if entity.has_method("take_damage"):
				entity.take_damage(1000)
			elif entity is NetworkedPlayer:
				# Use NetworkedPlayer damage RPC
				var target_np = entity as NetworkedPlayer
				var attacker_id = multiplayer.get_unique_id()
				target_np.apply_damage.rpc_id(target_np.peer_id, 1000.0, attacker_id, target_np.peer_id)

func is_inside_triangle_prism(pt: Vector3, a: Vector3, b: Vector3, c: Vector3) -> bool:
	var y_min = min(a.y, min(b.y, c.y)) - 1.0
	var y_max = max(a.y, max(b.y, c.y)) + 2.0
	if pt.y < y_min or pt.y > y_max: return false
	return is_point_in_triangle_2d(Vector2(pt.x, pt.z), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))

func is_point_in_triangle_2d(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var det = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
	if is_zero_approx(det): return false
	var factor_alpha = (b.y - c.y) * (p.x - c.x) + (c.x - b.x) * (p.y - c.y)
	var factor_beta = (c.y - a.y) * (p.x - c.x) + (a.x - c.x) * (p.y - c.y)
	var alpha = factor_alpha / det
	var beta = factor_beta / det
	var gamma = 1.0 - alpha - beta
	return alpha >= 0 and beta >= 0 and gamma >= 0

# ===== AIRBLAST SYSTEM =====

func perform_airblast():
	if not _can_airblast:
		return
	
	# Check ammo cost
	if airblast_ammo_cost > 0 and ammo_in_clip < airblast_ammo_cost:
		return
	
	# Consume ammo if needed
	if airblast_ammo_cost > 0:
		ammo_in_clip -= airblast_ammo_cost
		emit_signal("ammo_changed", ammo_in_clip, clip_size)
	
	# Play sound
	if airblast_sound:
		_play_sound(airblast_sound)
	
	# Get camera/aim direction
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	var origin = camera.global_position
	var forward = -camera.global_transform.basis.z
	
	# Find projectiles and players in cone
	_airblast_affect_objects(origin, forward)
	
	# Start cooldown
	_can_airblast = false
	_airblast_timer.start(airblast_cooldown)

func _on_airblast_timeout():
	_can_airblast = true

func _airblast_affect_objects(origin: Vector3, forward: Vector3):
	var cone_angle_rad = deg_to_rad(airblast_cone_angle)
	
	# Find all projectiles in scene
	var projectiles = get_tree().get_nodes_in_group("projectiles")
	if projectiles.is_empty():
		# Try finding Projectile class instances
		projectiles = _find_all_projectiles()
	
	# Find all players
	var players = get_tree().get_nodes_in_group("player")
	
	# Check projectiles
	for proj in projectiles:
		if not is_instance_valid(proj):
			continue
		if not proj is Projectile:
			continue
		
		var proj_pos = proj.global_position
		var to_proj = (proj_pos - origin)
		var dist = to_proj.length()
		
		if dist > airblast_range:
			continue
		
		# Check if in cone
		var to_proj_norm = to_proj.normalized()
		var dot = forward.dot(to_proj_norm)
		var angle = acos(clamp(dot, -1.0, 1.0))
		
		if angle > cone_angle_rad:
			continue
		
		# Reflect projectile
		_reflect_projectile(proj, forward)
	
	# Check players
	var owner_player = _get_owner_player()
	for player in players:
		if not is_instance_valid(player):
			continue
		if player == owner_player:
			continue
		
		var player_pos = player.global_position
		var to_player = (player_pos - origin)
		var dist = to_player.length()
		
		if dist > airblast_range:
			continue
		
		# Check if in cone
		var to_player_norm = to_player.normalized()
		var dot = forward.dot(to_player_norm)
		var angle = acos(clamp(dot, -1.0, 1.0))
		
		if angle > cone_angle_rad:
			continue
		
		# Push player
		_push_player(player, forward, to_player_norm)

func _find_all_projectiles() -> Array:
	var projectiles = []
	var scene = get_tree().current_scene
	_find_projectiles_recursive(scene, projectiles)
	return projectiles

func _find_projectiles_recursive(node: Node, projectiles: Array):
	if node is Projectile:
		projectiles.append(node)
	
	for child in node.get_children():
		_find_projectiles_recursive(child, projectiles)

func _reflect_projectile(proj: Projectile, airblast_dir: Vector3):
	var old_owner_id = proj.owner_peer_id
	var new_owner_id = multiplayer.get_unique_id()
	
	# Don't reflect own projectiles
	if old_owner_id == new_owner_id:
		return
	
	# Calculate reflection direction (reflect off airblast direction)
	var proj_vel = proj.direction * proj.speed
	var reflect_dir = proj_vel.bounce(airblast_dir).normalized()
	
	# If bounce doesn't work well, just reverse and add forward component
	if reflect_dir.length_squared() < 0.1:
		reflect_dir = -proj.direction + airblast_dir * 0.5
		reflect_dir = reflect_dir.normalized()
	
	# Update projectile direction and owner
	proj.direction = reflect_dir
	proj.owner_node = _get_owner_player()
	proj.owner_peer_id = new_owner_id
	
	# Reset hit flag so it can hit again
	proj.has_hit = false
	
	# Update exclusions to new owner
	if proj.owner_node:
		proj.owner_exclusions = proj._get_owner_collision_bodies(proj.owner_node)
	
	# Rotate projectile to face new direction
	proj.look_at(proj.global_position + reflect_dir)
	
	print("Airblast: Reflected projectile from owner ", old_owner_id, " to owner ", new_owner_id)

func _push_player(player: Node, airblast_dir: Vector3, to_player: Vector3):
	if not player.has_method("apply_impulse") and not player is CharacterBody3D:
		return
	
	# Calculate push force (away from airblast origin, with upward component)
	var push_dir = to_player
	push_dir.y += 0.3  # Add upward component
	push_dir = push_dir.normalized()
	
	var force = push_dir * airblast_force
	
	if player is CharacterBody3D:
		player.velocity += force * 0.016  # Approximate for 60fps
	elif player.has_method("apply_impulse"):
		player.apply_impulse(force)
	
	print("Airblast: Pushed player ", player.name)

func _get_owner_player() -> Node3D:
	# Find the player that owns this weapon
	var node = get_parent()
	while node:
		if node is NetworkedPlayer or node.has_method("take_damage"):
			return node
		node = node.get_parent()
	return null
