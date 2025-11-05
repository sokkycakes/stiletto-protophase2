## Enhanced Body Component Implementation

class_name EnhancedBodyComponent
extends IBody

# Animation state
var animation_queue: Array[String] = []
var current_activity_name: String = ""

func on_initialize() -> void:
	# Find AnimationPlayer in bot hierarchy
	animation_player = _find_animation_player(bot)
	
	# Set default hull properties
	hull_width = 0.8
	hull_height = 1.8
	crouch_hull_height = 1.0
	
	# Set default posture
	current_posture = PostureType.STAND
	desired_posture = PostureType.STAND

func on_update(delta: float) -> void:
	super.on_update(delta)
	
	# Update animation state
	_update_animations(delta)
	
	# Process animation queue
	_process_animation_queue()

# Enhanced activity control
func start_activity(activity: ActivityType, flags: int = 0) -> bool:
	var old_activity = current_activity
	current_activity = activity
	
	# Map activity to animation with enhanced logic
	var anim_name = _get_animation_for_activity(activity)
	if not anim_name.is_empty():
		play_animation(anim_name)
		current_activity_name = anim_name
		
		# Trigger activity change events
		if old_activity != activity:
			_on_activity_changed(old_activity, activity)
		
		return true
	
	return false

# Enhanced animation control
func play_animation(anim_name: String, rate: float = 1.0) -> void:
	if current_animation == anim_name and is_animation_playing():
		return
	
	if animation_player and animation_player.has_animation(anim_name):
		# Stop current animation
		if is_animation_playing():
			var old_anim = current_animation
			animation_player.stop()
			on_animation_activity_interrupted(old_anim)
		
		# Play new animation
		animation_player.play(anim_name, -1, rate)
		current_animation = anim_name
		animation_rate = rate
		
		# Connect to animation finished signal if not already connected
		if not animation_player.animation_finished.is_connected(_on_animation_finished):
			animation_player.animation_finished.connect(_on_animation_finished)

func queue_animation(anim_name: String) -> void:
	animation_queue.append(anim_name)

func stop_animation() -> void:
	if animation_player and is_animation_playing():
		var old_anim = current_animation
		animation_player.stop()
		current_animation = ""
		on_animation_activity_interrupted(old_anim)

# Enhanced posture control
func set_desired_posture(posture: PostureType) -> void:
	if desired_posture != posture:
		desired_posture = posture
		_update_posture_animation()

# Enhanced looking and aiming
func aim_head_towards(subject: Node, look_at_duration: float = 0.0) -> void:
	super.aim_head_towards(subject, look_at_duration)
	
	# Enhanced head tracking with smooth interpolation
	if subject and is_instance_valid(subject):
		_start_head_tracking(subject.global_position, look_at_duration)

func aim_head_towards_pos(pos: Vector3, look_at_duration: float = 0.0) -> void:
	super.aim_head_towards_pos(pos, look_at_duration)
	_start_head_tracking(pos, look_at_duration)

# Enhanced eye position calculation
func get_eye_position() -> Vector3:
	# Try to find a specific eye bone or node
	var eye_node = _find_eye_node()
	if eye_node:
		return eye_node.global_position
	
	# Fallback to calculated position
	var height_offset = hull_height * 0.9
	match current_posture:
		PostureType.CROUCH:
			height_offset = crouch_hull_height * 0.9
		PostureType.CRAWL:
			height_offset = crouch_hull_height * 0.5
		PostureType.LIE:
			height_offset = 0.2
	
	return bot.get_position() + Vector3(0, height_offset, 0)

# Enhanced view vector calculation
func get_view_vector() -> Vector3:
	# Try to get view direction from head bone or camera
	var head_node = _find_head_node()
	if head_node:
		return -head_node.global_transform.basis.z
	
	# Fallback to bot's forward direction
	return -bot.global_transform.basis.z

# Animation event handling
func _on_animation_finished(anim_name: String) -> void:
	on_animation_activity_complete(anim_name)
	
	# Process next animation in queue
	if not animation_queue.is_empty():
		var next_anim = animation_queue.pop_front()
		play_animation(next_anim)

func _on_activity_changed(old_activity: ActivityType, new_activity: ActivityType) -> void:
	# Handle activity-specific logic
	match new_activity:
		ActivityType.DEATH:
			# Disable collision when dead
			_set_collision_enabled(false)
		ActivityType.ATTACK:
			# Increase animation rate for attacks
			animation_rate = 1.2
		_:
			# Reset to normal
			animation_rate = 1.0
			if old_activity == ActivityType.DEATH:
				_set_collision_enabled(true)

# Helper methods
func _get_animation_for_activity(activity: ActivityType) -> String:
	match activity:
		ActivityType.IDLE:
			return _get_posture_animation("idle")
		ActivityType.WALK:
			return _get_posture_animation("walk")
		ActivityType.RUN:
			return _get_posture_animation("run")
		ActivityType.ATTACK:
			return "attack"
		ActivityType.DEATH:
			return "death"
		ActivityType.JUMP:
			return "jump"
		ActivityType.CLIMB:
			return "climb"
		ActivityType.RELOAD:
			return "reload"
		_:
			return _get_posture_animation("idle")

func _get_posture_animation(base_anim: String) -> String:
	match current_posture:
		PostureType.CROUCH:
			return "crouch_" + base_anim
		PostureType.CRAWL:
			return "crawl_" + base_anim
		PostureType.LIE:
			return "prone_" + base_anim
		_:
			return base_anim

func _update_posture_animation() -> void:
	# Update animation based on new posture
	if current_activity != ActivityType.INVALID:
		var anim_name = _get_animation_for_activity(current_activity)
		if not anim_name.is_empty():
			play_animation(anim_name)

func _update_animations(delta: float) -> void:
	# Update automatic animations based on movement
	if not is_animation_playing() and current_activity == ActivityType.IDLE:
		var locomotion = bot.get_locomotion_interface()
		if locomotion:
			var speed = locomotion.get_speed()
			if speed > locomotion.get_run_speed() * 0.8:
				start_activity(ActivityType.RUN)
			elif speed > locomotion.get_walk_speed() * 0.5:
				start_activity(ActivityType.WALK)
			else:
				start_activity(ActivityType.IDLE)

func _process_animation_queue() -> void:
	# Process queued animations when current one finishes
	if not is_animation_playing() and not animation_queue.is_empty():
		var next_anim = animation_queue.pop_front()
		play_animation(next_anim)

func _start_head_tracking(target_pos: Vector3, duration: float) -> void:
	# Enhanced head tracking implementation
	look_at_target = target_pos
	is_head_aiming = true
	
	# Create smooth head movement tween if available
	var head_node = _find_head_node()
	if head_node:
		var tween = bot.create_tween()
		var current_rotation = head_node.rotation
		var target_direction = (target_pos - head_node.global_position).normalized()
		var target_rotation = head_node.global_transform.looking_at(head_node.global_position + target_direction).basis.get_euler()
		
		if duration > 0:
			tween.tween_property(head_node, "rotation", target_rotation, duration)
		else:
			head_node.rotation = target_rotation

func _find_eye_node() -> Node3D:
	# Try to find eye bone or marker
	return _find_bone_or_node(["Eye", "eye", "Head", "head"])

func _find_head_node() -> Node3D:
	# Try to find head bone or marker
	return _find_bone_or_node(["Head", "head", "Neck", "neck"])

func _find_bone_or_node(names: Array[String]) -> Node3D:
	# Search for bone or node by name
	for name in names:
		var node = _search_node_recursive(bot, name)
		if node and node is Node3D:
			return node
	return null

func _search_node_recursive(node: Node, search_name: String) -> Node:
	if node.name.to_lower().contains(search_name.to_lower()):
		return node
	
	for child in node.get_children():
		var result = _search_node_recursive(child, search_name)
		if result:
			return result
	
	return null

func _set_collision_enabled(enabled: bool) -> void:
	# Enable/disable collision for the bot
	var collision_shape = bot.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = not enabled
