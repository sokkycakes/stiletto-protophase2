extends Behavior
class_name IdleBehavior

var idle_timer: float = 0.0
var idle_duration: float = 3.0
var scan_timer: float = 0.0
var scan_interval: float = 1.0

func _init() -> void:
    name = "idle"

func on_start() -> void:
    idle_timer = 0.0
    scan_timer = 0.0
    bot.play_animation("idle")

func update(delta: float) -> Dictionary:
    idle_timer += delta
    scan_timer += delta
    
    # Periodically scan for threats
    if scan_timer >= scan_interval:
        scan_timer = 0.0
        # Look around by rotating slightly
        var current_rotation = bot.rotation
        current_rotation.y += PI * 0.25 # 45 degrees
        bot.face_toward(bot.global_position + Vector3(cos(current_rotation.y), 0, sin(current_rotation.y)))
    
    # After idle duration, switch to patrol
    if idle_timer >= idle_duration:
        return change_to("patrol")
    
    return continue_behavior()

# Override event handlers for more responsive behavior
func on_sight(entity: Node) -> Dictionary:
    if bot.is_threat(entity):
        return change_to("seek_and_destroy")
    return continue_behavior()

func on_injured(damage: float, attacker: Node) -> Dictionary:
    if bot.is_health_low():
        return change_to("retreat")
    elif attacker:
        return change_to("attack")
    return continue_behavior() 