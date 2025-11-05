extends Behavior
class_name SeekAndDestroyBehavior

var search_timer: float = 0.0
var search_update_interval: float = 1.0
var last_known_position: Vector3
var search_radius: float = 20.0

func _init() -> void:
    name = "seek_and_destroy"

func on_start() -> void:
    search_timer = 0.0
    var threat = bot.get_nearest_threat()
    if threat:
        last_known_position = threat.global_position
        move_to_target()
    bot.play_animation("run")

func update(delta: float) -> Dictionary:
    search_timer += delta
    
    if search_timer >= search_update_interval:
        search_timer = 0.0
        update_search()
    
    # Check if we've reached the last known position
    var distance = bot.global_position.distance_to(last_known_position)
    if distance < 1.0:
        # Search complete at this point, expand search or switch behavior
        if not bot.has_threats():
            return change_to("patrol")
    
    return continue_behavior()

func update_search() -> void:
    var threat = bot.get_nearest_threat()
    if threat and bot.can_see(threat):
        # If we can see the threat and it's close enough, switch to attack
        var distance = bot.global_position.distance_to(threat.global_position)
        if distance < 10.0: # Attack range
            change_to("attack")
        else:
            # Update position and keep pursuing
            last_known_position = threat.global_position
            move_to_target()
    else:
        # No visible threat, search around last known position
        search_around_position()

func move_to_target() -> void:
    bot.move_toward(last_known_position)
    bot.face_toward(last_known_position)

func search_around_position() -> void:
    # Generate search points around last known position
    var angle = randf() * PI * 2
    var radius = randf() * search_radius
    var search_point = last_known_position + Vector3(
        cos(angle) * radius,
        0,
        sin(angle) * radius
    )
    
    bot.move_toward(search_point)

# Override event handlers
func on_sight(entity: Node) -> Dictionary:
    if bot.is_threat(entity):
        last_known_position = entity.global_position
        var distance = bot.global_position.distance_to(entity.global_position)
        if distance < 10.0: # Attack range
            return change_to("attack")
        else:
            move_to_target()
    return continue_behavior()

func on_lost_sight(entity: Node) -> Dictionary:
    # Keep moving to last known position
    return continue_behavior()

func on_injured(damage: float, attacker: Node) -> Dictionary:
    if bot.is_health_low():
        return change_to("retreat")
    elif attacker and bot.can_see(attacker):
        last_known_position = attacker.global_position
        return change_to("attack")
    return continue_behavior()

func on_stuck() -> Dictionary:
    # Try searching in a different direction
    search_around_position()
    return continue_behavior() 