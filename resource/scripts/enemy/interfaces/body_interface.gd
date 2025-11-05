## NextBot Body Interface
## Based on Source SDK NextBotBodyInterface.h
class_name IBody
extends INextBotComponent

# Body postures
enum PostureType {
	STAND,
	CROUCH,
	SIT,
	CRAWL,
	LIE
}

# Activity states
enum ActivityType {
	INVALID = -1,
	IDLE,
	WALK,
	RUN,
	ATTACK,
	RELOAD,
	JUMP,
	CLIMB,
	DEATH,
	CUSTOM
}

# Body properties
var current_posture: PostureType = PostureType.STAND
var desired_posture: PostureType = PostureType.STAND
var current_activity: ActivityType = ActivityType.IDLE
var hull_width: float = 0.8
var hull_height: float = 1.8
var crouch_hull_height: float = 1.0
var solid_mask: int = 1

# Animation system
var animation_player: AnimationPlayer
var current_animation: String = ""
var animation_rate: float = 1.0

# Looking/aiming
var look_at_target: Vector3
var look_at_subject: Node
var head_aim_subject: Node
var is_head_aiming: bool = false
var max_head_angle_horizontal: float = 90.0
var max_head_angle_vertical: float = 60.0

# Body state
var is_arousal: bool = false

# Abstract methods - must be implemented by derived classes
func start_activity(activity: ActivityType, flags: int = 0) -> bool:
	assert(false, "start_activity() must be implemented by derived class")
	return false

func get_activity() -> ActivityType:
	return current_activity

func is_activity(activity: ActivityType) -> bool:
	return current_activity == activity

# Posture control
func set_desired_posture(posture: PostureType) -> void:
	desired_posture = posture

func get_desired_posture() -> PostureType:
	return desired_posture

func is_desired_posture(posture: PostureType) -> bool:
	return desired_posture == posture

func get_actual_posture() -> PostureType:
	return current_posture

func is_actual_posture(posture: PostureType) -> bool:
	return current_posture == posture

func is_posture_changing() -> bool:
	return current_posture != desired_posture

# Hull properties
func get_hull_width() -> float:
	return hull_width

func get_hull_height() -> float:
	if current_posture == PostureType.CROUCH:
		return crouch_hull_height
	return hull_height

func get_stand_hull_height() -> float:
	return hull_height

func get_crouch_hull_height() -> float:
	return crouch_hull_height

func get_hull_mins() -> Vector3:
	var width_half = hull_width * 0.5
	return Vector3(-width_half, 0, -width_half)

func get_hull_maxs() -> Vector3:
	var width_half = hull_width * 0.5
	var height = get_hull_height()
	return Vector3(width_half, height, width_half)

func get_solid_mask() -> int:
	return solid_mask

func set_solid_mask(mask: int) -> void:
	solid_mask = mask

# Looking and aiming
func aim_head_towards(subject: Node, look_at_duration: float = 0.0) -> void:
	head_aim_subject = subject
	is_head_aiming = true

func aim_head_towards_pos(pos: Vector3, look_at_duration: float = 0.0) -> void:
	look_at_target = pos
	head_aim_subject = null
	is_head_aiming = true

func is_head_aiming_on_target() -> bool:
	return is_head_aiming

func is_head_steady() -> bool:
	return not is_head_aiming

func get_head_aim_subject() -> Node:
	return head_aim_subject

func get_head_aim_subject_lead_time() -> float:
	return 0.0  # Default implementation

func get_max_head_angle_horizontal() -> float:
	return max_head_angle_horizontal

func get_max_head_angle_vertical() -> float:
	return max_head_angle_vertical

# Eye position
func get_eye_position() -> Vector3:
	# Default implementation - should be overridden
	return bot.get_position() + Vector3(0, hull_height * 0.9, 0)

func get_view_vector() -> Vector3:
	# Default implementation - forward direction
	return -bot.global_transform.basis.z

# Arousal
func is_arousal_query() -> bool:
	return is_arousal

func set_arousal(arousal: bool) -> void:
	is_arousal = arousal

# Animation helpers
func set_animation_player(player: AnimationPlayer) -> void:
	animation_player = player

func play_animation(anim_name: String, rate: float = 1.0) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		current_animation = anim_name
		animation_rate = rate
		animation_player.play(anim_name, -1, rate)

func stop_animation() -> void:
	if animation_player:
		animation_player.stop()
	current_animation = ""

func get_current_animation() -> String:
	return current_animation

func is_animation_playing(anim_name: String = "") -> bool:
	if not animation_player:
		return false
	if anim_name.is_empty():
		return animation_player.is_playing()
	return animation_player.current_animation == anim_name and animation_player.is_playing()

# Component initialization
func _init() -> void:
	component_name = "Body"

func on_initialize() -> void:
	# Try to find AnimationPlayer in bot
	animation_player = _find_animation_player(bot)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null

# Update posture
func on_update(delta: float) -> void:
	_update_posture(delta)
	_update_head_aim(delta)

func _update_posture(delta: float) -> void:
	if current_posture != desired_posture:
		# Simple immediate posture change - can be enhanced with transitions
		current_posture = desired_posture
		on_posture_changed()

func _update_head_aim(delta: float) -> void:
	if not is_head_aiming:
		return
		
	var target_pos: Vector3
	if head_aim_subject:
		target_pos = head_aim_subject.global_position
	else:
		target_pos = look_at_target
	
	# Simple look-at implementation - can be enhanced
	var look_direction = (target_pos - get_eye_position()).normalized()
	# Apply look direction to bot (simplified)
	# In a full implementation, this would control head bones/nodes
