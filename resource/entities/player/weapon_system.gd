extends Node3D
class_name WeaponSystemV1

# Weapon properties
@export var max_ammo: int = 6  # 6 bullet mag
@export var current_ammo: int = 6
@export var shot_damage: int = 1  # Light damage for raycast shot (matches 4 HP system)
@export var bigshot_damage: int = 2  # Heavy damage for physical projectile (matches 4 HP system)
@export var normal_reload_time: float = 1.5  # Faster reload for normal shots
@export var bigshot_reload_time: float = 3.0  # Slower reload for bigshot
@export var shot_fire_rate: float = 0.2  # Faster fire rate for shots
@export var bigshot_fire_rate: float = 0.5  # Slower fire rate for bigshots
@export var projectile_speed: float = 80.0  # High speed for bigshot projectiles

# Reload timing
@export var reload_start_time: float = 0.8  # Time for reload_start animation
@export var reload_bullet_time: float = 0.4  # Time per bullet during reload_loop
@export var reload_end_time: float = 0.6  # Time for reload_end animation

# Projectile scene
@export var projectile_scene: PackedScene

# Raycast for shots - you can assign any raycast you want
@export var shot_raycast: RayCast3D

# Animation player reference
@export var animation_player: AnimationPlayer
# HUD ammo indicator (optional)
@export var ammo_indicator_path: NodePath

var _ammo_indicator: Node = null

# HUD reload timer label (optional)
@export var reload_timer_label_path: NodePath

var _reload_timer_label: Label = null

# Sound effects
@export var shot_sound: AudioStream
@export var bigshot_sound: AudioStream
@export var audio_bus: String = "sfx"

# Impact particle effect
@export var impact_particle_scene: PackedScene
# Bullet trail effect
@export var bullet_trail_scene: PackedScene
# Muzzle flash effect
@export var muzzle_flash_scene: PackedScene
# Bullet hole decal
@export var bullet_hole_scene: PackedScene

# Internal variables
var can_fire_shot: bool = true
var can_fire_bigshot: bool = true
var is_reloading: bool = false
var shot_fire_timer: Timer
var bigshot_fire_timer: Timer
var reload_timer: Timer
var reload_loop_timer: Timer
var bullet_holes: Array = []
const MAX_BULLET_HOLES: int = 10

# Reload state tracking
var reload_stage: String = "none"  # "none", "start", "loop", "end"
var bullets_loaded: int = 0
var target_bullets: int = 0

# Node references
@onready var camera: Camera3D = get_node("../Interpolated Camera/Arm/Arm Anchor/Camera")
@onready var player_state: Node = get_node("../Body/PlayerState")

# New export variable
@export var gun_start_marker: Node3D

# Melee attack reference
@export var hook_melee_attack: HookMeleeAttack

# Audio player pool for weapon sounds
var audio_players: Array[AudioStreamPlayer] = []

func _ready():
	# Setup timers
	shot_fire_timer = Timer.new()
	shot_fire_timer.wait_time = shot_fire_rate
	shot_fire_timer.one_shot = true
	shot_fire_timer.timeout.connect(_on_shot_fire_timer_timeout)
	add_child(shot_fire_timer)
	
	bigshot_fire_timer = Timer.new()
	bigshot_fire_timer.wait_time = bigshot_fire_rate
	bigshot_fire_timer.one_shot = true
	bigshot_fire_timer.timeout.connect(_on_bigshot_fire_timer_timeout)
	add_child(bigshot_fire_timer)
	
	reload_timer = Timer.new()
	reload_timer.one_shot = true
	reload_timer.timeout.connect(_on_reload_timer_timeout)
	add_child(reload_timer)
	
	reload_loop_timer = Timer.new()
	reload_loop_timer.one_shot = true
	reload_loop_timer.timeout.connect(_on_reload_loop_timer_timeout)
	add_child(reload_loop_timer)
	
	# Setup audio players pool (similar to hook controller)
	for i in range(8):  # Create 8 audio players
		var player = AudioStreamPlayer.new()
		player.bus = audio_bus
		add_child(player)
		audio_players.append(player)

	if ammo_indicator_path != NodePath("") and has_node(ammo_indicator_path):
		_ammo_indicator = get_node(ammo_indicator_path)
		_update_ammo_indicator()
	
	if reload_timer_label_path != NodePath("") and has_node(reload_timer_label_path):
		_reload_timer_label = get_node(reload_timer_label_path)
		_update_reload_timer_display()

func _input(event):
	# Safety check: only handle input if properly initialized
	if not is_inside_tree():
		return
	
	# Don't handle input if player is stunned or dead
	if player_state and (player_state.is_in_stunned_state() or player_state.is_in_dead_state()):
		return
		
	# Handle input for shooting and reloading
	if event.is_action_pressed("fire"):
		shoot()
	elif event.is_action_pressed("altfire"):
		bigshot()
	elif event.is_action_pressed("reload"):
		reload()
	elif event.is_action_pressed("melee"):
		perform_melee_attack()

func shoot():
	# Raycast/hitscan shot - uses 1 bullet
	if can_fire_shot and current_ammo > 0 and not is_reloading:
		print("Shot fired! Ammo: ", current_ammo)
		current_ammo -= 1
		can_fire_shot = false
		shot_fire_timer.start()
		
		_update_ammo_indicator()
		# Play fire animation
		if animation_player and animation_player.has_animation("fire"):
			if animation_player.is_playing() and animation_player.current_animation == "fire":
				# Restart the current fire animation from the beginning
				animation_player.seek(0.0, true)
			else:
				animation_player.play("fire")
		
		# Play shot sound
		play_sound(shot_sound)
		
		# Create muzzle flash
		print("Creating muzzle flash...")
		create_muzzle_flash()
		
		# Perform raycast shot
		print("Performing raycast shot...")
		perform_raycast_shot()
	else:
		# Handle empty weapon firing attempt
		handle_empty_weapon_fire()

func bigshot():
	# Physical projectile shot - uses all remaining bullets
	if can_fire_bigshot and current_ammo > 0 and not is_reloading:
		print("Bigshot fired! Ammo: ", current_ammo)
		current_ammo = 0  # Use all remaining ammo
		can_fire_bigshot = false
		bigshot_fire_timer.start()
		
		_update_ammo_indicator()
		# Play bigshot animation
		if animation_player and animation_player.has_animation("bigshot"):
			animation_player.play("bigshot")
		
		# Play bigshot sound
		play_sound(bigshot_sound)
		
		# Create physical projectile
		create_bigshot_projectile()
		
		# Alert nearby enemies to the player's position
		alert_nearby_enemies()
	else:
		# Handle empty weapon firing attempt
		handle_empty_weapon_fire()

# Handle empty weapon firing attempts
func handle_empty_weapon_fire():
	if current_ammo <= 0 and not is_reloading:
		print("Empty weapon fire attempt!")
		# Trigger empty weapon pulse effect
		if _ammo_indicator and _ammo_indicator.has_method("trigger_empty_pulse"):
			_ammo_indicator.trigger_empty_pulse()

func play_sound(sound: AudioStream) -> void:
	if sound:
		# Find an available audio player
		for player in audio_players:
			if not player.playing:
				player.stream = sound
				player.play()
				break

func perform_raycast_shot():
	# Perform raycast/hitscan shot using physics query (ignore any RayCast3D node, which may have its own rotation)
	if camera and is_inside_tree() and camera.is_inside_tree():
		var from: Vector3
		if gun_start_marker and gun_start_marker.is_inside_tree():
			from = gun_start_marker.global_position
		else:
			from = camera.global_position
		
		var forward_dir: Vector3 = -camera.global_transform.basis.z
		var to = from + forward_dir * 1000.0  # Shoot forward 1000 units
		
		# Set up query
		var world := get_world_3d()
		if world == null:
			printerr("WeaponSystemV1: World3D is null. Aborting raycast.")
			return
		var space_state = world.direct_space_state
		var query = PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = 0xFFFFFFFF
		query.hit_from_inside = true
		
		# Build an exclusion list so the ray never collides with the player (or any of its sub-colliders)
		var exclude_list: Array = [self]

		var player_node := get_parent()
		if player_node:
			exclude_list.append(player_node)

			# Recursively gather every CollisionObject3D within the player hierarchy
			var nodes_to_process: Array = [player_node]
			while nodes_to_process.size() > 0:
				var n: Node = nodes_to_process.pop_back()
				for child in n.get_children():
					nodes_to_process.append(child)
					if child is CollisionObject3D:
						exclude_list.append(child)

		query.exclude = exclude_list
		query.collide_with_areas = true
		query.collide_with_bodies = true
		
		var result = space_state.intersect_ray(query)
		var hit_point = to
		var hit_normal = Vector3.UP
		if result:
			var hit_object = result.collider
			hit_point = result.position
			hit_normal = result.normal
			print("Raycast hit: ", hit_object.name)
			apply_damage_to_target(hit_object, shot_damage)
		
		# Create bullet trail and impact effect
		create_bullet_trail(from, hit_point)
		spawn_impact_particle(hit_point, hit_normal)
		spawn_bullet_hole(hit_point, hit_normal)
	else:
		print("Camera not available for raycast shot")

func create_bigshot_projectile():
	# Create and spawn bigshot projectile
	if projectile_scene and camera and is_inside_tree() and camera.is_inside_tree():
		var projectile = projectile_scene.instantiate()
		get_tree().current_scene.add_child(projectile)
		
		# Set projectile position and direction (reverted to camera basis)
		var spawn_position = camera.global_position
		var shoot_direction = -camera.global_transform.basis.z
		
		# Set bigshot damage
		projectile.damage = bigshot_damage
		projectile.speed = projectile_speed
		projectile.impact_particle_scene = impact_particle_scene
		
		projectile.initialize(spawn_position, shoot_direction)
		print("Bigshot projectile created at: ", spawn_position)
	else:
		print("Camera or projectile scene not available for bigshot")

func apply_damage_to_target(target, damage_amount):
	# PLACEHOLDER: Apply damage to target
	print("Damage applied to ", target.name, ": ", damage_amount)
	if target.has_method("take_damage"):
		target.take_damage(damage_amount)

func reload():
	# Handle reloading logic
	if not is_reloading and current_ammo < max_ammo:
		print("Reloading...")
		is_reloading = true
		reload_stage = "start"
		bullets_loaded = 0
		target_bullets = max_ammo - current_ammo
		
		# Play reload_start animation
		if animation_player and animation_player.has_animation("reload_start"):
			animation_player.play("reload_start")
		
		# Use fixed reload start time
		reload_timer.wait_time = reload_start_time
		reload_timer.start()
		_update_reload_timer_display()

func start_reload_loop():
	reload_stage = "loop"
	bullets_loaded = 0
	
	# Play reload_loop animation
	if animation_player and animation_player.has_animation("reload_loop"):
		animation_player.play("reload_loop")
	
	# Use fixed time per bullet
	reload_loop_timer.wait_time = reload_bullet_time
	reload_loop_timer.start()

func load_bullet():
	bullets_loaded += 1
	current_ammo += 1
	print("Bullet loaded: ", bullets_loaded, "/", target_bullets)
	_update_ammo_indicator()
	
	if bullets_loaded >= target_bullets:
		# All bullets loaded, finish reload
		finish_reload()
	else:
		# Replay reload_loop animation for the next bullet
		if animation_player and animation_player.has_animation("reload_loop"):
			animation_player.play("reload_loop")
		# Continue loading bullets
		reload_loop_timer.start()

func finish_reload():
	reload_stage = "end"
	
	# Play reload_end animation
	if animation_player and animation_player.has_animation("reload_end"):
		animation_player.play("reload_end")
	
	# Use fixed reload end time
	reload_timer.wait_time = reload_end_time
	reload_timer.start()

func complete_reload():
	current_ammo = max_ammo
	is_reloading = false
	reload_stage = "none"
	bullets_loaded = 0
	target_bullets = 0
	print("Reload complete! Ammo: ", current_ammo)
	_update_ammo_indicator()
	_update_reload_timer_display()

func _on_shot_fire_timer_timeout():
	can_fire_shot = true

func _on_bigshot_fire_timer_timeout():
	can_fire_bigshot = true

func _on_reload_timer_timeout():
	if reload_stage == "start":
		start_reload_loop()
	elif reload_stage == "end":
		complete_reload()

func _on_reload_loop_timer_timeout():
	load_bullet()

func _process(_delta: float) -> void:
	# Update reload timer display during reload
	if is_reloading and _reload_timer_label:
		_update_reload_timer_display()

func get_remaining_reload_time() -> float:
	"""Calculate the total remaining time for the reload process"""
	if not is_reloading:
		return 0.0
	
	match reload_stage:
		"start":
			# Time left in start stage + loop time + end time
			var remaining_start = max(0.0, reload_timer.time_left)
			var loop_time = target_bullets * reload_bullet_time
			var end_time = reload_end_time
			return remaining_start + loop_time + end_time
		
		"loop":
			# Time left in current bullet + remaining bullets + end time
			var remaining_bullet = max(0.0, reload_loop_timer.time_left)
			var remaining_bullets = max(0, target_bullets - bullets_loaded - 1)
			var remaining_loop_time = remaining_bullets * reload_bullet_time
			var end_time = reload_end_time
			return remaining_bullet + remaining_loop_time + end_time
		
		"end":
			# Time left in end stage
			return max(0.0, reload_timer.time_left)
		
		_:
			return 0.0

func _update_reload_timer_display() -> void:
	"""Update the reload timer label with countdown"""
	if not _reload_timer_label:
		return
	
	if is_reloading:
		var remaining_time = get_remaining_reload_time()
		# Format to 1 decimal place, countdown
		_reload_timer_label.text = "%.1f" % remaining_time
		_reload_timer_label.visible = true
	else:
		_reload_timer_label.visible = false
		_reload_timer_label.text = "0.0"

func perform_melee_attack() -> void:
	"""Perform the hook melee attack"""
	if hook_melee_attack and hook_melee_attack.has_method("perform_attack"):
		hook_melee_attack.perform_attack()
	else:
		print("WeaponSystem: Hook melee attack not available")

# Getter functions for UI
func get_current_ammo() -> int:
	return current_ammo

func get_max_ammo() -> int:
	return max_ammo

func is_weapon_reloading() -> bool:
	return is_reloading

func can_fire_shot_type() -> bool:
	return can_fire_shot and current_ammo > 0 and not is_reloading

func can_fire_bigshot_type() -> bool:
	return can_fire_bigshot and current_ammo > 0 and not is_reloading

func get_reload_stage() -> String:
	return reload_stage

func get_bullets_loaded() -> int:
	return bullets_loaded

func get_target_bullets() -> int:
	return target_bullets

func create_muzzle_flash():
	# Create muzzle flash effect at camera position
	if muzzle_flash_scene and camera and is_inside_tree() and camera.is_inside_tree():
		var flash_node = muzzle_flash_scene.instantiate()
		get_tree().current_scene.add_child(flash_node)
		
		# Position the muzzle flash slightly in front of the camera
		var flash_position: Vector3
		if gun_start_marker and gun_start_marker.is_inside_tree():
			flash_position = gun_start_marker.global_position
		else:
			flash_position = camera.global_position - camera.global_transform.basis.z * 0.5
		flash_node.global_position = flash_position
		
		# Orient the muzzle flash so it points straight ahead from the camera
		var flash_xform: Transform3D = flash_node.global_transform
		flash_xform.basis = camera.global_transform.basis
		flash_node.global_transform = flash_xform
		
		# Start the particle emission
		var particles = flash_node.get_node("CPUParticles3D")
		if particles:
			particles.emitting = true
			print("Muzzle flash created at: ", flash_position)
		
		# Auto-cleanup after a short time
		var cleanup_timer = Timer.new()
		cleanup_timer.wait_time = 0.1
		cleanup_timer.one_shot = true
		flash_node.add_child(cleanup_timer)
		cleanup_timer.timeout.connect(flash_node.queue_free)
		cleanup_timer.start()
	else:
		print("Muzzle flash scene not assigned or camera not available")

func create_bullet_trail(from_position: Vector3, to_position: Vector3):
	# Create bullet trail effect
	if bullet_trail_scene:
		var trail_node = bullet_trail_scene.instantiate()
		get_tree().current_scene.add_child(trail_node)
		
		# If it's a BulletTrail class, use its create_trail method
		if trail_node.has_method("create_trail"):
			trail_node.create_trail(from_position, to_position)
			print("Bullet trail created from: ", from_position, " to: ", to_position)
		else:
			# Fallback: just position it
			trail_node.global_position = from_position
			trail_node.look_at(to_position)
			print("Bullet trail fallback created at: ", from_position)
	else:
		print("Bullet trail scene not assigned")

func spawn_impact_particle(position: Vector3, normal: Vector3 = Vector3.UP):
	if impact_particle_scene:
		var particle_node = impact_particle_scene.instantiate()
		get_tree().current_scene.add_child(particle_node)
		# If the particle node is a Node3D, set its position & orientation
		if particle_node is Node3D:
			particle_node.global_position = position
			# Orient to face the normal if desired (optional)
			particle_node.look_at(position + normal)
			
			# Start the particle emission
			var particles = particle_node.get_node("CPUParticles3D")
			if particles:
				particles.emitting = true
				print("Impact particles created at: ", position)
		
	# Optional: you can add logic to queue_free the particle after a given lifetime if needed
	else:
		print("Impact particle scene not assigned")

func spawn_bullet_hole(position: Vector3, normal: Vector3 = Vector3.UP):
	if bullet_hole_scene:
		var hole = bullet_hole_scene.instantiate()
		get_tree().current_scene.add_child(hole)
		
		# For Decal nodes, let them handle projection automatically
		if hole is Decal:
			# Just set the position - Decal will project onto nearby surfaces
			hole.global_position = position
			# Optional: random rotation around the normal for variety
			var random_rotation = randf() * TAU
			hole.rotate_object_local(normal, random_rotation)
		elif hole is Node3D:
			# Fallback for non-Decal nodes (old behavior)
			hole.global_position = position + normal * 0.01
			hole.look_at(position + normal, Vector3.UP)
		
		bullet_holes.append(hole)
		if bullet_holes.size() > MAX_BULLET_HOLES:
			var old = bullet_holes.pop_front()
			if old and old.is_inside_tree():
				old.queue_free()
	else:
		print("[WeaponSystem] bullet_hole_scene not assigned") 

# Helper
func _update_ammo_indicator():
	if _ammo_indicator and _ammo_indicator.has_method("set_ammo"):
		_ammo_indicator.set_ammo(current_ammo) 

func alert_nearby_enemies():
	"""
	Simple function to alert all enemies within a radius to the player's position.
	Uses composition - doesn't modify enemy scripts, just sets their state.
	"""
	var alert_radius: float = 15.0  # 15 meter radius
	var alert_duration: float = 5.0  # 5 seconds
	
	# Get all enemies in the scene
	var enemies = get_tree().get_nodes_in_group("enemy")
	var player_position = global_position
	
	for enemy in enemies:
		# Check if enemy is within alert radius
		var distance = enemy.global_position.distance_to(player_position)
		if distance <= alert_radius:
			# Make enemy aware of player position
			alert_enemy(enemy, player_position, alert_duration)

func alert_enemy(enemy: Node, target_position: Vector3, duration: float):
	"""
	Alert a single enemy to move towards a position for a duration.
	Uses composition - works with any enemy that has basic movement capabilities.
	"""
	# Create a simple alert behavior component
	var alert_behavior = EnemyAlertBehavior.new()
	alert_behavior.target_position = target_position
	alert_behavior.duration = duration
	alert_behavior.enemy = enemy
	
	# Add the alert behavior to the enemy
	enemy.add_child(alert_behavior)
	
	# Start the alert behavior
	alert_behavior.start_alert()

# Simple alert behavior class
class EnemyAlertBehavior:
	extends Node

	var target_position: Vector3
	var duration: float
	var enemy: Node
	var timer: Timer
	var current_process_func: Callable

	func start_alert():
		# Create timer for duration
		timer = Timer.new()
		timer.wait_time = duration
		timer.one_shot = true
		timer.timeout.connect(_on_alert_timeout)
		add_child(timer)
		timer.start()

		# Start moving towards target
		current_process_func = _alert_movement
	
	func _process(_delta: float):
		if current_process_func.is_valid():
			current_process_func.call(_delta)

	func _alert_movement(_delta: float):
		if not is_instance_valid(enemy):
			queue_free()
			return

		# Simple movement towards target position
		var direction = (target_position - enemy.global_position).normalized()
		direction.y = 0  # Keep movement horizontal

		# Apply movement to enemy (works with CharacterBody3D or any node with velocity)
		if enemy is CharacterBody3D:
			enemy.velocity = direction * 2.0  # Slow movement speed
		elif enemy.has_method("set_velocity"):
			enemy.set_velocity(direction * 2.0)

	func _on_alert_timeout():
		# Stop alert behavior
		current_process_func = Callable()
		queue_free()
