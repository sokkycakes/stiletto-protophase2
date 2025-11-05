class_name AdvancedGrapplingHook3D
extends Node3D # Or CharacterBody3D if your player uses physics movement

# --- Exports ---
@export var grappling_hook_scene: PackedScene # The scene for the hook object
@export var hook_spawn_marker: Node3D # A child Node3D on the player where the hook visually originates
@export var max_distance: float = 30.0
@export var hook_speed: float = 40.0
@export var pull_speed: float = 20.0
@export var retraction_speed_multiplier: float = 1.5 # How much faster it retracts
@export var jump_pull_height_threshold: float = 2.0 # Units. If target is higher by less than this, or lower, it's a jump-pull.
@export var player_body: CharacterBody3D # Reference to the player body for movement
@export var grapple_velocity_decay: float = 0.96 # Decay factor for momentum
@export var crosshair_tex: TextureRect # Assign your crosshair TextureRect here
@export var crosshair_grapple: Texture2D # Texture when grapple is possible
@export var crosshair_no_grapple: Texture2D # Texture when grapple is not possible
@export var grapple_min_velocity: float = 2.0 # Minimum velocity for grapple momentum
@export var charge_indicator: Control # Reference to the charge indicator HUD
@export var spark_scene: PackedScene # Scene for the spark effect when hook bounces
@export var snap_offset: float = 0.8 # How far from the surface to keep the player when snapped
@export var goldgdt_view: NodePath # New export variable for GoldGdt_View
@export var goldgdt_controls: NodePath # New export variable for GoldGdt_Controls

@export_group("Speed-Based Distance")
@export var enable_speed_based_distance: bool = true # Enable dynamic distance based on speed
@export var speed_distance_curve: Curve # Curve mapping speed to distance multiplier (0-1 input, 1-2 output recommended)
@export var min_speed_threshold: float = 5.0 # Speed below which no distance bonus is applied
@export var max_speed_threshold: float = 20.0 # Speed above which maximum distance bonus is applied
@export var max_distance_multiplier: float = 2.0 # Maximum distance multiplier at high speeds
@export var use_air_speed_only: bool = true # Only apply speed bonus when not grounded

@export_group("Speed-Based Hook Speed")
@export var enable_speed_based_hook_speed: bool = true # Enable dynamic hook speed based on speed
@export var speed_hook_speed_curve: Curve # Curve mapping speed to hook speed multiplier (0-1 input, 1-2 output recommended)
@export var max_hook_speed_multiplier: float = 1.5 # Maximum hook speed multiplier at high speeds

@export_group("Sound Settings")
@export var hook_fire_sound: AudioStream
@export var hook_hit_sound: AudioStream
@export var hook_retract_sound: AudioStream
@export var hook_pull_sound: AudioStream
@export var hook_bounce_sound: AudioStream
@export var audio_bus: String = "Master" # Audio bus to play sounds through

# --- Charge System Variables ---
const MAX_CHARGES: int = 3
var current_charges: int = MAX_CHARGES
var charge_timers: Array[float] = [0.0, 0.0, 0.0]
var is_grounded: bool = false
var grapple_target_normal: Vector3 = Vector3.ZERO
signal charges_changed(charges: int)

# --- State Machine ---
enum GrappleState {
	IDLE,
	HOOK_FLYING,
	HOOK_CONTACT_EVAL,
	HOOK_CONTACT_ENEMY,
	GRAPPLE_PULLING_PLAYER,
	GRAPPLE_PULLING_ENEMY,
	HOOK_RETRACTING
}
var current_state: GrappleState = GrappleState.IDLE

# --- Internal Variables ---
var current_hook_instance: Node3D = null
var grapple_target_point: Vector3
var hit_collider: Object = null
var is_grapple_button_held: bool = false
var is_player_stuck_to_wall: bool = false
var audio_players: Array[AudioStreamPlayer] = []
var locked_enemy_center: Vector3 = Vector3.ZERO
# Reference to the enemy currently hooked so that we can lock the camera onto it.
var locked_enemy: Node3D = null

# --- Enemy hook charge cooldown flags ---
# True once we've latched onto an enemy; we will start the 3-second full recharge only after retraction.
var _enemy_hook_pending_cooldown: bool = false
# True while the special 3-second recharge is running.
var _enemy_cooldown_active: bool = false
var _recharge_suspended: bool = false

var _goldgdt_view_node: Node = null # Reference to the GoldGdt_View node
var _goldgdt_controls_node: Node = null # Reference to the GoldGdt_Controls node

# Utility ------------------------------------------------------------------
# Recursively checks whether a collider or any of its parents is in the "enemy" group.
func _is_part_of_enemy(node: Node) -> bool:
	var n := node
	while n:
		if n.is_in_group("enemy"):
			return true
		n = n.get_parent()
	return false

# --- Enemy Hook Interaction Helper Vars ---
# Time (seconds) the grapple button must be held to be considered a "hold" rather than a "tap".
const HOLD_THRESHOLD: float = 0.25
# Tracks how long the grapple button has been held while deciding between pull-player vs pull-enemy.
var _grapple_press_timer: float = 0.0
# True when we are waiting to determine if the player is tapping or holding the grapple button.
var _awaiting_hold_decision: bool = false

# --- Signals (Optional) ---
# signal hook_fired
# signal hook_hit_static
# signal hook_hit_enemy
# signal player_started_pull
# signal enemy_started_pull
# signal hook_retracted

func _ready():
	if not grappling_hook_scene:
		printerr("AdvancedGrapplingHook3D: grappling_hook_scene not set!")
		set_process(false)
		set_physics_process(false)
	if not hook_spawn_marker:
		printerr("AdvancedGrapplingHook3D: hook_spawn_marker not set! Using player position as fallback.")
	
	# Register globally so GameMaster can access
	add_to_group("hook_controller")

	# Initialize charge timers
	charge_timers.resize(MAX_CHARGES)
	for i in range(MAX_CHARGES):
		charge_timers[i] = 0.0
	
	# Connect to charge indicator if available
	if charge_indicator and charge_indicator.has_method("update_charges"):
		charges_changed.connect(charge_indicator.update_charges)
		# Initialize the charge indicator with current charges
		charge_indicator.update_charges(current_charges)
	else:
		push_warning("AdvancedGrapplingHook3D: No charge indicator assigned or invalid charge indicator!")

	# Setup audio players
	for i in range(8):  # Create 8 audio players
		var player = AudioStreamPlayer.new()
		player.bus = audio_bus
		add_child(player)
		audio_players.append(player)

	# Get GoldGdt_View node
	if goldgdt_view != NodePath("") and has_node(goldgdt_view):
		_goldgdt_view_node = get_node(goldgdt_view)
	else:
		push_warning("AdvancedGrapplingHook3D: goldgdt_view not assigned or invalid!")

	# Get GoldGdt_Controls node
	if goldgdt_controls != NodePath("") and has_node(goldgdt_controls):
		_goldgdt_controls_node = get_node(goldgdt_controls)
	else:
		push_warning("AdvancedGrapplingHook3D: goldgdt_controls not assigned or invalid!")

func play_sound(sound: AudioStream, pitch_scale: float = 1.0) -> void:
	if sound:
		# Ensure pitch scale stays within a reasonable range
		pitch_scale = clamp(pitch_scale, 0.5, 2.0)
		# Find an available audio player
		for player in audio_players:
			if not player.playing:
				player.stream = sound
				player.pitch_scale = pitch_scale
				player.play()
				break

func get_spawn_position() -> Vector3:
	return hook_spawn_marker.global_position if hook_spawn_marker else global_position

func get_dynamic_distance() -> float:
	if not enable_speed_based_distance or not player_body:
		return max_distance
	
	# Get player's horizontal velocity
	var velocity = player_body.velocity
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	# Check if we should apply speed bonus (only when in air if use_air_speed_only is true)
	if use_air_speed_only and player_body.is_on_floor():
		return max_distance
	
	# Clamp speed to our threshold range
	var clamped_speed = clamp(horizontal_speed, min_speed_threshold, max_speed_threshold)
	
	# Normalize speed to 0-1 range
	var normalized_speed = (clamped_speed - min_speed_threshold) / (max_speed_threshold - min_speed_threshold)
	
	# Apply curve if available, otherwise use linear interpolation
	var distance_multiplier = 1.0
	if speed_distance_curve:
		distance_multiplier = speed_distance_curve.sample(normalized_speed)
	else:
		# Linear interpolation from 1.0 to max_distance_multiplier
		distance_multiplier = lerp(1.0, max_distance_multiplier, normalized_speed)
	
	return max_distance * distance_multiplier

func get_dynamic_hook_speed() -> float:
	if not enable_speed_based_hook_speed or not player_body:
		return hook_speed
	
	# Get player's horizontal velocity
	var velocity = player_body.velocity
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	
	# Check if we should apply speed bonus (only when in air if use_air_speed_only is true)
	if use_air_speed_only and player_body.is_on_floor():
		return hook_speed
	
	# Clamp speed to our threshold range
	var clamped_speed = clamp(horizontal_speed, min_speed_threshold, max_speed_threshold)
	
	# Normalize speed to 0-1 range
	var normalized_speed = (clamped_speed - min_speed_threshold) / (max_speed_threshold - min_speed_threshold)
	
	# Apply curve if available, otherwise use linear interpolation
	var speed_multiplier = 1.0
	if speed_hook_speed_curve:
		speed_multiplier = speed_hook_speed_curve.sample(normalized_speed)
	else:
		# Linear interpolation from 1.0 to max_hook_speed_multiplier
		speed_multiplier = lerp(1.0, max_hook_speed_multiplier, normalized_speed)
	
	return hook_speed * speed_multiplier

func get_speed_pitch_multiplier() -> float:
	# Returns a pitch multiplier between 1.0 and 1.05 based on player speed.
	if not enable_speed_based_hook_speed or not player_body:
		return 1.0
	if use_air_speed_only and player_body.is_on_floor():
		return 1.0
	var velocity: Vector3 = player_body.velocity
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed <= min_speed_threshold:
		return 1.0
	var clamped_speed: float = clamp(horizontal_speed, min_speed_threshold, max_speed_threshold)
	var normalized_speed: float = (clamped_speed - min_speed_threshold) / (max_speed_threshold - min_speed_threshold)
	# Linearly interpolate pitch from 1.0 to 1.05
	return lerp(1.0, 1.05, normalized_speed)

func _unhandled_input(event: InputEvent):
	# Allow limited control while stunned: only unhook/cancel when a hook is active.
	# Completely ignore input when dead.
	var player_state = get_node_or_null("../Body/PlayerState")
	if player_state:
		if player_state.is_in_dead_state():
			return
		if player_state.is_in_stunned_state():
			# Only permit unhooking if there's an active hook; block firing while stunned.
			if current_state != GrappleState.IDLE:
				if event.is_action_pressed("melee") or event.is_action_released("grapple"):
					is_grapple_button_held = false
					initiate_retraction()
			return
		
	match current_state:
		GrappleState.IDLE:
			if event.is_action_pressed("grapple"):
				is_grapple_button_held = true
				fire_hook()
		GrappleState.HOOK_CONTACT_ENEMY:
			# Determine whether the player taps or holds the grapple key.
			if event.is_action_pressed("grapple"):
				print("Enemy hook: grapple button pressed (awaiting tap/hold decision)")
				_awaiting_hold_decision = true
				_grapple_press_timer = 0.0
				is_grapple_button_held = true
			elif event.is_action_released("grapple"):
				is_grapple_button_held = false
				if _awaiting_hold_decision and _grapple_press_timer < HOLD_THRESHOLD and current_state == GrappleState.HOOK_CONTACT_ENEMY:
					print("Enemy hook: tap detected – pulling enemy to player")
					set_state(GrappleState.GRAPPLE_PULLING_ENEMY)
					_awaiting_hold_decision = false
			elif event.is_action_pressed("melee"):
				print("Input: Retract from Enemy (melee)")
				initiate_retraction()
		GrappleState.GRAPPLE_PULLING_PLAYER:
			if event.is_action_released("grapple"):
				is_grapple_button_held = false
				initiate_retraction()
				is_player_stuck_to_wall = false
			elif event.is_action_pressed("grapple"):
				is_grapple_button_held = true
		GrappleState.GRAPPLE_PULLING_ENEMY:
			pass
		_:
			pass
	if event.is_action_released("grapple"):
		is_grapple_button_held = false

func _physics_process(delta: float):
	update_crosshair()
	match current_state:
		GrappleState.HOOK_FLYING:
			process_hook_flying(delta)
		GrappleState.GRAPPLE_PULLING_PLAYER:
			process_player_pull(delta)
		GrappleState.HOOK_RETRACTING:
			process_hook_retracting(delta)

# --- State Logic Functions ---

func set_state(new_state: GrappleState):
	if current_state == new_state:
		return
	current_state = new_state
	match current_state:
		GrappleState.HOOK_CONTACT_EVAL:
			evaluate_hook_contact()
		GrappleState.GRAPPLE_PULLING_PLAYER:
			is_player_stuck_to_wall = false
			locked_enemy = null # stop camera lock when player pulling
			if player_body and player_body is CharacterBody3D:
				var direction_to_hook = (grapple_target_point - player_body.global_position).normalized()
				var anchor_pos_init = grapple_target_point - (grapple_target_normal * snap_offset) if grapple_target_normal != Vector3.ZERO else grapple_target_point
				player_body.velocity = direction_to_hook * pull_speed
				# Play hook pull sound when starting to pull
				play_sound(hook_pull_sound)
		GrappleState.GRAPPLE_PULLING_ENEMY:
			locked_enemy = null
			_launch_enemy()
			# Immediately retract after launching enemy
			initiate_retraction()
			return # no further processing for this transitional state
		_:
			pass

func fire_hook():
	if current_charges <= 0:
		return
	var _world := get_world_3d()
	if _world == null:
		printerr("HookController: World3D is null. Aborting raycast.")
		return
	var space_state = _world.direct_space_state
	var camera = get_viewport().get_camera_3d()
	if not camera:
		printerr("No Camera3D found in viewport for screen center raycast.")
		return
	
	# Get dynamic distance based on player speed
	var current_max_distance = get_dynamic_distance()
	
	# Use camera's forward direction instead of viewport coordinates
	var ray_origin = camera.global_position
	var ray_dir = -camera.global_transform.basis.z
	var ray_end = ray_origin + ray_dir * current_max_distance
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Set collision mask to include all layers except layer 1 (player)
	# Layer 1 is typically 0x2 (2^1), so we use 0xFFFFFFFD to exclude it
	query.collision_mask = 0xFFFFFFFD
	
	# Debug: Print the collision mask
	print("Hook raycast collision mask: ", query.collision_mask)
	
	if current_hook_instance:
		query.exclude.append(current_hook_instance.get_rid())
	
	var result = space_state.intersect_ray(query)
	if result:
		print("Hook hit object on layer: ", result.collider.collision_layer)
		# Store the surface normal so we can offset the player when we arrive
		grapple_target_normal = result.normal
		# Use a charge: find the first available timer slot
		for i in range(MAX_CHARGES):
			if charge_timers[i] == 0:
				charge_timers[i] = 0.6 if is_grounded else 1.3
				break
		current_charges -= 1
		charges_changed.emit(current_charges)
		grapple_target_point = result.position
		hit_collider = result.collider
		current_hook_instance = grappling_hook_scene.instantiate()
		get_parent().add_child(current_hook_instance)
		current_hook_instance.global_position = get_spawn_position()
		current_hook_instance.look_at(grapple_target_point)
		set_state(GrappleState.HOOK_FLYING)
		
		# Play hook fire sound
		play_sound(hook_fire_sound)
	else:
		print("Grapple: No target found at screen center. Ray from ", ray_origin, " to ", ray_end)

func process_hook_flying(delta: float):
	if not current_hook_instance:
		return
	var hook_pos = current_hook_instance.global_position
	var distance_to_target = hook_pos.distance_to(grapple_target_point)
	var distance_from_player = hook_pos.distance_to(get_spawn_position())
	var current_max_distance = get_dynamic_distance()
	if distance_from_player > current_max_distance:
		print("Hook flew too far.")
		initiate_retraction()
		return
	var direction = (grapple_target_point - hook_pos).normalized()
	var current_hook_speed = get_dynamic_hook_speed()
	var travel = current_hook_speed * delta
	current_hook_instance.global_position = hook_pos.move_toward(grapple_target_point, travel)
	# Short raycast from hook tip
	var _world := get_world_3d()
	if _world == null:
		printerr("HookController: World3D is null. Aborting raycast.")
		return
	var space_state = _world.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		hook_pos,
		hook_pos + direction * 0.5 # 0.5 units in 3D
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [self, current_hook_instance]
	var collision_result = space_state.intersect_ray(query)
	if hook_pos.is_equal_approx(grapple_target_point) or collision_result:
		if collision_result:
			print("Hook hit intermediate object.")
			grapple_target_point = collision_result.position
			# Update the stored surface normal from the collision
			grapple_target_normal = collision_result.normal
			hit_collider = collision_result.collider
		current_hook_instance.global_position = grapple_target_point
		print("Hook reached target or hit something.")
		set_state(GrappleState.HOOK_CONTACT_EVAL)

func evaluate_hook_contact():
	# Reset any existing camera lock target until we confirm enemy hit
	locked_enemy = null
	locked_enemy_center = Vector3.ZERO
	if not hit_collider:
		print("Error: Hook in contact eval, but no hit_collider.")
		initiate_retraction()
		return
	if hit_collider is StaticBody3D or hit_collider is GridMap:
		# A static body could still be part of an enemy (e.g., child collision meshes).
		if _is_part_of_enemy(hit_collider):
			print("Hook hit enemy (static child).")
			# Walk up hierarchy until we reach the node that is actually in the "enemy" group.
			var enemy_node := hit_collider
			while enemy_node and not enemy_node.is_in_group("enemy"):
				enemy_node = enemy_node.get_parent()
			locked_enemy = enemy_node
			# Apply brief stun so enemy stops moving while player decides.
			if locked_enemy and locked_enemy.has_method("apply_stun"):
				locked_enemy.apply_stun(0.4)
				locked_enemy.velocity = Vector3.ZERO # Freeze enemy during contact
			elif locked_enemy and locked_enemy.has_method("enter_stun_state"):
				locked_enemy.enter_stun_state(0.4)
				locked_enemy.velocity = Vector3.ZERO # Freeze enemy during contact
			
			_calculate_enemy_center()
			# Play hook hit sound with pitch based on speed
			play_sound(hook_hit_sound, get_speed_pitch_multiplier())
			set_state(GrappleState.HOOK_CONTACT_ENEMY)
			_enemy_hook_pending_cooldown = true
			# Disable roll in GoldGdt_View when lock-on starts
			if _goldgdt_view_node and _goldgdt_view_node.has_method("set_roll_enabled"):
				_goldgdt_view_node.set_roll_enabled(false)
			if _goldgdt_view_node and _goldgdt_view_node.has_method("set_lock_on_target"):
				_goldgdt_view_node.set_lock_on_target(locked_enemy)
			if _goldgdt_controls_node and _goldgdt_controls_node.has_method("set_lock_on_target"):
				_goldgdt_controls_node.set_lock_on_target(locked_enemy)
		else:
			print("Hook hit static object.")
			# Play hook hit sound with pitch based on speed
			play_sound(hook_hit_sound, get_speed_pitch_multiplier())
			# Spawn spark effect at the impact point
			spawn_spark_effect(grapple_target_point, -current_hook_instance.global_transform.basis.z)
			set_state(GrappleState.GRAPPLE_PULLING_PLAYER)
	elif _is_part_of_enemy(hit_collider):
		# Store reference for camera lock-on (find the ancestor with the group)
		var enemy_node := hit_collider
		while enemy_node and not enemy_node.is_in_group("enemy"):
			enemy_node = enemy_node.get_parent()
		locked_enemy = enemy_node
		# Apply brief stun so enemy stops moving during decision window.
		if locked_enemy and locked_enemy.has_method("apply_stun"):
			locked_enemy.apply_stun(0.4)
			locked_enemy.velocity = Vector3.ZERO # Freeze enemy during contact
		elif locked_enemy and locked_enemy.has_method("enter_stun_state"):
			locked_enemy.enter_stun_state(0.4)
			locked_enemy.velocity = Vector3.ZERO # Freeze enemy during contact

		_calculate_enemy_center()
		print("Hook hit enemy.")
		# Play hook hit sound with pitch based on speed
		play_sound(hook_hit_sound, get_speed_pitch_multiplier())
		set_state(GrappleState.HOOK_CONTACT_ENEMY)
		_enemy_hook_pending_cooldown = true
		# Disable roll in GoldGdt_View when lock-on starts
		if _goldgdt_view_node and _goldgdt_view_node.has_method("set_roll_enabled"):
			_goldgdt_view_node.set_roll_enabled(false)
		if _goldgdt_view_node and _goldgdt_view_node.has_method("set_lock_on_target"):
			_goldgdt_view_node.set_lock_on_target(locked_enemy)
		if _goldgdt_controls_node and _goldgdt_controls_node.has_method("set_lock_on_target"):
			_goldgdt_controls_node.set_lock_on_target(locked_enemy)
	else:
		print("Hook hit non-grappleable dynamic object. Bouncing off.")
		# Play hook bounce sound (no pitch scaling)
		play_sound(hook_bounce_sound)
		# Spawn spark effect at the impact point
		spawn_spark_effect(grapple_target_point, -current_hook_instance.global_transform.basis.z)
		initiate_retraction()


func _calculate_enemy_center():
	if not is_instance_valid(locked_enemy):
		return
	if locked_enemy is CharacterBody3D and locked_enemy.get_node_or_null("CollisionShape3D"):
		var shape_node = locked_enemy.get_node("CollisionShape3D")
		var shape = shape_node.shape
		if shape is CapsuleShape3D:
			locked_enemy_center = locked_enemy.global_position + Vector3(0, shape.height / 2, 0)
		elif shape is BoxShape3D:
			locked_enemy_center = locked_enemy.global_position + shape.size / 2
		else:
			locked_enemy_center = locked_enemy.global_position
	else:
		locked_enemy_center = locked_enemy.global_position


func _launch_enemy():
	if not hit_collider or not _is_part_of_enemy(hit_collider):
		return
	var enemy_node := hit_collider
	while enemy_node and not enemy_node.is_in_group("enemy"):
		enemy_node = enemy_node.get_parent()
	# If it's an enemy spawner, simply destroy it and return.
	if enemy_node and enemy_node.get_script() and String(enemy_node.get_script().resource_path).find("enemy_spawner.gd") != -1:
		# Optional: play destruction effects here
		enemy_node.queue_free()
		return
	var target_pos := get_spawn_position()
	if enemy_node and enemy_node is CharacterBody3D:
		var enemy_cb := enemy_node as CharacterBody3D
		var to_player := target_pos - enemy_cb.global_position
		var dist := to_player.length()

		# Separate horizontal and vertical components so we can ensure forward motion.
		var dir_h := to_player
		dir_h.y = 0
		dir_h = dir_h.normalized()
		if dir_h == Vector3.ZERO:
			# If enemy is directly above/below player, push along X axis a bit to avoid straight-up.
			dir_h = Vector3.RIGHT

		# Compute horizontal direction and distance (ignore y)
		var desired_offset := 1.0 # enemy should land 1 m in front of player
		var horizontal_distance := max(0.1, dist - desired_offset)
		var g := ProjectSettings.get_setting("physics/3d/default_gravity")
		# Use 45° launch angle for maximum range at given speed: v = sqrt(R * g)
		var required_speed := sqrt(horizontal_distance * g)
		required_speed = clamp(required_speed, 10.0, 50.0)
		var cos45 := 0.70710678
		var launch_velocity: Vector3 = dir_h * (required_speed * cos45)
		launch_velocity.y = required_speed * cos45 # same as sin45
		enemy_cb.velocity = launch_velocity
		# optional: call stun if method exists
		if enemy_cb.has_method("apply_stun"):
			enemy_cb.apply_stun(1.6)
		elif enemy_cb.has_method("enter_stun_state"):
			enemy_cb.enter_stun_state(1.6)
	else:
		# For non-physics enemies, just move them instantly
		enemy_node.global_position = target_pos

func process_player_pull(delta: float):
	if not current_hook_instance:
		return
	if not is_grapple_button_held:
		initiate_retraction()
		return
	var target_pos = current_hook_instance.global_position
	var anchor_pos = target_pos - (grapple_target_normal * snap_offset) if grapple_target_normal != Vector3.ZERO else target_pos
	if player_body and player_body is CharacterBody3D:
		if is_player_stuck_to_wall:
			var snap_pos = anchor_pos
			player_body.global_position = snap_pos
			return
		var direction_to_hook = (anchor_pos - player_body.global_position).normalized()
		player_body.velocity *= grapple_velocity_decay
		# Clamp velocity to minimum if not stuck to wall
		if player_body.velocity.length() < grapple_min_velocity:
			player_body.velocity = direction_to_hook * grapple_min_velocity
		if player_body.velocity.dot(direction_to_hook) < 0:
			player_body.velocity = Vector3.ZERO
		player_body.move_and_slide()
		if player_body.global_position.distance_to(anchor_pos) < 0.5:
			var snap_pos2 = anchor_pos
			player_body.global_position = snap_pos2
			player_body.velocity = Vector3.ZERO
			is_player_stuck_to_wall = true
	else:
		var snap_pos3 = anchor_pos
		global_position = global_position.move_toward(snap_pos3, pull_speed * delta)
		if global_position.distance_to(snap_pos3) < 0.5:
			global_position = snap_pos3
			is_player_stuck_to_wall = true

func process_enemy_pull(delta: float):
	if not is_instance_valid(hit_collider) or not _is_part_of_enemy(hit_collider):
		initiate_retraction()
		return
	if not current_hook_instance:
		return
	var enemy_node = hit_collider as Node3D
	if not enemy_node:
		initiate_retraction()
		return
	var target_pos = get_spawn_position()
	if enemy_node is CharacterBody3D:
		var enemy_cb = enemy_node as CharacterBody3D
		var direction_to_player = (target_pos - enemy_cb.global_position).normalized()
		enemy_cb.velocity = direction_to_player * pull_speed
		enemy_cb.move_and_slide()
	else:
		enemy_node.global_position = enemy_node.global_position.move_toward(target_pos, pull_speed * delta)
	if enemy_node.global_position.distance_to(target_pos) < 1.0:
		initiate_retraction()

func process_hook_retracting(delta: float):
	if not current_hook_instance:
		set_state(GrappleState.IDLE)
		return
	var retraction_target_pos = get_spawn_position()
	var current_hook_speed = get_dynamic_hook_speed()
	current_hook_instance.global_position = current_hook_instance.global_position.move_toward(
		retraction_target_pos,
		current_hook_speed * retraction_speed_multiplier * delta
	)
	if current_hook_instance.global_position.distance_to(retraction_target_pos) < 0.2:
		destroy_hook()

func initiate_retraction():
	if current_state == GrappleState.HOOK_RETRACTING or current_state == GrappleState.IDLE:
		return
	print("Hook retraction initiated.")
	set_state(GrappleState.HOOK_RETRACTING)
	is_player_stuck_to_wall = false
	if player_body and player_body is CharacterBody3D:
		pass
	if current_state == GrappleState.GRAPPLE_PULLING_ENEMY and hit_collider and hit_collider is CharacterBody3D:
		var enemy_cb = hit_collider as CharacterBody3D
		enemy_cb.velocity = Vector3.ZERO
	
	# Play hook retract sound
	play_sound(hook_retract_sound)

	# Clear camera lock target
	locked_enemy = null
	# If we had hooked an enemy, consume all charges and start 3-second refill.
	if _enemy_hook_pending_cooldown:
		_enemy_hook_pending_cooldown = false
		_enemy_cooldown_active = true
		current_charges = 0
		charges_changed.emit(current_charges)
		for i in range(MAX_CHARGES):
			# Charges will come back at 1s, 2s, 3s respectively.
			charge_timers[i] = (i + 1) * 1.0
	else:
		# regular grapple recharge continues
		pass
	_awaiting_hold_decision = false
	_grapple_press_timer = 0.0
	# Re-enable roll in GoldGdt_View when lock-on ends
	if _goldgdt_view_node and _goldgdt_view_node.has_method("set_roll_enabled"):
		_goldgdt_view_node.set_roll_enabled(true)
	if _goldgdt_view_node and _goldgdt_view_node.has_method("set_lock_on_target"):
		_goldgdt_view_node.set_lock_on_target(null)
	if _goldgdt_controls_node and _goldgdt_controls_node.has_method("set_lock_on_target"):
		_goldgdt_controls_node.set_lock_on_target(null)

func destroy_hook():
	if current_hook_instance:
		current_hook_instance.queue_free()
		current_hook_instance = null
	hit_collider = null
	grapple_target_point = Vector3.ZERO
	locked_enemy = null
	_awaiting_hold_decision = false
	_grapple_press_timer = 0.0
	set_state(GrappleState.IDLE)

func is_grapple_target_available() -> bool:
	var _world := get_world_3d()
	if _world == null:
		printerr("HookController: World3D is null. Aborting raycast.")
		return false
	var space_state = _world.direct_space_state
	var camera = get_viewport().get_camera_3d()
	if not camera:
		return false
	
	# Get dynamic distance based on player speed
	var current_max_distance = get_dynamic_distance()
	
	# Use camera's forward direction instead of viewport coordinates
	var ray_origin = camera.global_position
	var ray_dir = -camera.global_transform.basis.z
	var ray_end = ray_origin + ray_dir * current_max_distance
	
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = []
	if player_body and player_body is CharacterBody3D:
		query.exclude.append(player_body.get_rid())
	var result = space_state.intersect_ray(query)
	if result:
		var collider = result.collider
		if collider is StaticBody3D or collider is GridMap or _is_part_of_enemy(collider):
			return true
	return false

func update_crosshair():
	if not crosshair_tex or not crosshair_grapple or not crosshair_no_grapple:
		return
	if is_grapple_target_available():
		crosshair_tex.texture = crosshair_grapple
	else:
		crosshair_tex.texture = crosshair_no_grapple

func _process(delta: float):
	# Update hold-tap decision timer when waiting for player input.
	if _awaiting_hold_decision:
		_grapple_press_timer += delta
		# If the button has been held beyond the threshold while still in contact with an enemy,
		# treat this as a hold and pull the player towards the enemy.
		if _grapple_press_timer >= HOLD_THRESHOLD and current_state == GrappleState.HOOK_CONTACT_ENEMY:
			print("Enemy hook: hold detected – cancelling grapple / retract")
			initiate_retraction()
			_awaiting_hold_decision = false
	# Lock the camera onto the enemy only while we are evaluating contact (not during pulls)
	if locked_enemy and is_instance_valid(locked_enemy) and current_state == GrappleState.HOOK_CONTACT_ENEMY:
		# Re-compute center each frame in case enemy moves slightly (e.g. physics wobble)
		_calculate_enemy_center()
		# The camera is now handled by GoldGdt_View, so we don't need to do anything here.

	update_charges(delta)

	# Auto retract if enemy dies while hooked
	if current_state == GrappleState.HOOK_CONTACT_ENEMY and (not is_instance_valid(hit_collider) or not _is_part_of_enemy(hit_collider)):
		print("Enemy vanished during hook – retracting.")
		initiate_retraction()

func update_charges(delta: float):
	# Disable automatic recharge during overwhelm phase
	if _is_overwhelm_active() or _recharge_suspended:
		return

	for i in range(MAX_CHARGES):
		if charge_timers[i] > 0:
			var recharge_time: float
			if _enemy_cooldown_active:
				recharge_time = 1.0 # timers were preset, we just count down
			else:
				recharge_time = 0.6 if is_grounded or i == MAX_CHARGES - 1 else 1.3
			charge_timers[i] -= delta
			if charge_timers[i] <= 0:
				charge_timers[i] = 0
				if current_charges < MAX_CHARGES:
					current_charges += 1
					charges_changed.emit(current_charges)
					if _enemy_cooldown_active and current_charges == MAX_CHARGES:
						_enemy_cooldown_active = false

# ---------------- Overwhelm helpers -----------------
func _is_overwhelm_active() -> bool:
	var gm_nodes = get_tree().get_nodes_in_group("gamemaster")
	if gm_nodes.size() > 0:
		var gm = gm_nodes[0]
		if gm.has_method("is_doom_active"):
			return gm.is_doom_active()
	return false

# Refill all hook charges instantly (used when player kills an enemy during overwhelm)
func recharge_charges():
	current_charges = MAX_CHARGES
	for i in range(MAX_CHARGES):
		charge_timers[i] = 0.0
	charges_changed.emit(current_charges)

# Called by GameMaster when overwhelm begins to freeze recharge
func suspend_recharge():
	_recharge_suspended = true
	for i in range(MAX_CHARGES):
		if charge_timers[i] > 0:
			charge_timers[i] = ceil(charge_timers[i]) # freeze at whole seconds so UI stable

# Called when overwhelm ends to restore normal behaviour
func resume_recharge():
	_recharge_suspended = false

func spawn_spark_effect(position: Vector3, normal: Vector3) -> void:
	print("Attempting to spawn spark effect at position: ", position)
	if spark_scene:
		var spark = spark_scene.instantiate()
		get_tree().root.add_child(spark)
		spark.global_position = position
		spark.look_at(position + normal)
		print("Spark effect spawned successfully")
		# Auto-free the spark after it's done playing
		spark.finished.connect(func(): spark.queue_free())
	else:
		print("Warning: spark_scene not assigned to HookController")
