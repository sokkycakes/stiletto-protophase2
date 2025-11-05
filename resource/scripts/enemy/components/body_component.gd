## Concrete Body Component Implementation
class_name BodyComponent
extends IBody

# Legacy compatibility
var anim_player: AnimationPlayer

func on_initialize() -> void:
    # Try to find AnimationPlayer
    anim_player = bot.get_node_or_null("AnimationPlayer")
    if not anim_player:
        anim_player = _find_animation_player(bot)

    animation_player = anim_player

    # Set default hull properties
    hull_width = 0.8
    hull_height = 1.8
    crouch_hull_height = 1.0

    # Set default posture
    current_posture = PostureType.STAND
    desired_posture = PostureType.STAND

func on_update(delta: float) -> void:
    super.on_update(delta)

    # Update animations based on state
    if anim_player and not anim_player.is_playing():
        play_default_animation()

# Activity control
func start_activity(activity: ActivityType, flags: int = 0) -> bool:
    var old_activity = current_activity
    current_activity = activity

    # Map activity to animation
    var anim_name = _get_animation_for_activity(activity)
    if not anim_name.is_empty():
        play_animation(anim_name)
        return true

    return false

# Enhanced animation control
func play_animation(anim_name: String, rate: float = 1.0) -> void:
    if current_animation == anim_name:
        return

    if anim_player and anim_player.has_animation(anim_name):
        anim_player.play(anim_name, -1, rate)
        current_animation = anim_name
        super.play_animation(anim_name, rate)

func play_default_animation() -> void:
    # Play idle or movement animation based on velocity
    if bot.velocity.length() > 0.1:
        play_animation("walk")
    else:
        play_animation("idle")

# Enhanced facing with interface compliance
func face_towards(pos: Vector3) -> void:
    face_toward(pos)

func face_toward(target_pos: Vector3) -> void:
    var direction = (target_pos - bot.global_position).normalized()
    if direction != Vector3.ZERO:
        # Only rotate around Y axis (up)
        direction.y = 0
        direction = direction.normalized()

        # Create rotation that looks in the direction
        var look_rotation = Transform3D().looking_at(direction, Vector3.UP)

        # Smoothly interpolate current rotation to target rotation
        bot.rotation.y = lerp_angle(bot.rotation.y, look_rotation.basis.get_euler().y, 0.1)

# Posture control with interface compliance
func set_posture(posture: String) -> void:
    match posture:
        "crouch":
            set_desired_posture(PostureType.CROUCH)
        "stand":
            set_desired_posture(PostureType.STAND)
        "crawl":
            set_desired_posture(PostureType.CRAWL)

# Helper methods
func _get_animation_for_activity(activity: ActivityType) -> String:
    match activity:
        ActivityType.IDLE:
            return "idle"
        ActivityType.WALK:
            return "walk"
        ActivityType.RUN:
            return "run"
        ActivityType.ATTACK:
            return "attack"
        ActivityType.DEATH:
            return "death"
        ActivityType.JUMP:
            return "jump"
        _:
            return "idle"

func _update_posture_collision() -> void:
    var collision_shape = bot.get_node_or_null("CollisionShape3D")
    if not collision_shape or not collision_shape.shape:
        return

    match current_posture:
        PostureType.CROUCH:
            collision_shape.shape.height = crouch_hull_height
            collision_shape.position.y = crouch_hull_height * 0.5
        PostureType.STAND:
            collision_shape.shape.height = hull_height
            collision_shape.position.y = hull_height * 0.5
        PostureType.CRAWL:
            collision_shape.shape.height = crouch_hull_height * 0.5
            collision_shape.position.y = crouch_hull_height * 0.25

# Override posture update to handle collision changes
func _update_posture(delta: float) -> void:
    if current_posture != desired_posture:
        current_posture = desired_posture
        _update_posture_collision()
        on_posture_changed()