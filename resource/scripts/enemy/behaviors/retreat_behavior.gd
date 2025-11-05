extends Behavior
class_name RetreatBehavior

var retreat_point: Vector3
var search_radius: float = 20.0
var min_safe_distance: float = 15.0
var cover_found: bool = false
var retreat_timer: float = 0.0
var max_retreat_time: float = 5.0

func _init() -> void:
    name = "retreat"

func on_start() -> void:
    retreat_timer = 0.0
    cover_found = false
    bot.play_animation("run")
    find_retreat_position()

func update(delta: float) -> Dictionary:
    retreat_timer += delta
    
    if not cover_found:
        find_retreat_position()
    
    var distance_to_retreat = bot.global_position.distance_to(retreat_point)
    
    # Check if we've reached cover
    if distance_to_retreat < 1.0:
        if is_position_safe():
            bot.play_animation("idle")
            # If health is still low, look for health
            if bot.is_health_low():
                return change_to("get_health")
            # Otherwise, return to combat if threats exist
            elif bot.has_threats():
                return change_to("seek_and_destroy")
            else:
                return change_to("patrol")
        else:
            # Current position not safe, find new cover
            cover_found = false
    
    # Give up retreating if taking too long
    if retreat_timer > max_retreat_time:
        if bot.has_threats():
            return change_to("seek_and_destroy")
        else:
            return change_to("patrol")
    
    return continue_behavior()

func find_retreat_position() -> void:
    var threats = bot.vision.get_threats()
    if threats.is_empty():
        # No visible threats, retreat to random position
        var angle = randf() * PI * 2
        retreat_point = bot.global_position + Vector3(
            cos(angle) * search_radius,
            0,
            sin(angle) * search_radius
        )
    else:
        # Retreat away from average threat position
        var avg_threat_pos = Vector3.ZERO
        for threat in threats:
            avg_threat_pos += threat.global_position
        avg_threat_pos /= threats.size()
        
        # Calculate retreat direction away from threats
        var retreat_dir = (bot.global_position - avg_threat_pos).normalized()
        retreat_point = bot.global_position + (retreat_dir * search_radius)
    
    # Move toward retreat point
    bot.move_toward(retreat_point)
    cover_found = true

func is_position_safe() -> bool:
    var threats = bot.vision.get_threats()
    for threat in threats:
        # Check distance
        var distance = bot.global_position.distance_to(threat.global_position)
        if distance < min_safe_distance:
            return false
        
        # Check if threat can see us
        if bot.vision.can_see(threat):
            return false
    
    return true

# Override event handlers
func on_injured(damage: float, attacker: Node) -> Dictionary:
    # Find new cover if current position isn't safe
    cover_found = false
    return continue_behavior()

func on_stuck() -> Dictionary:
    # Try to find new retreat position
    cover_found = false
    return continue_behavior()

func on_sight(entity: Node) -> Dictionary:
    if bot.is_threat(entity):
        # Check if current retreat position is still good
        if not is_position_safe():
            cover_found = false
    return continue_behavior() 