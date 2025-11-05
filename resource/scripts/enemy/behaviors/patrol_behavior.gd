extends Behavior
class_name PatrolBehavior

var current_point: int = 0
var patrol_points: Array[Vector3] = []
var wait_timer: float = 0.0
var wait_duration: float = 2.0
var is_waiting: bool = false

func _init() -> void:
    name = "patrol"

func on_start() -> void:
    wait_timer = 0.0
    is_waiting = false
    setup_patrol_points()
    move_to_next_point()
    bot.play_animation("walk")

func update(delta: float) -> Dictionary:
    if is_waiting:
        wait_timer += delta
        if wait_timer >= wait_duration:
            is_waiting = false
            move_to_next_point()
            bot.play_animation("walk")
    else:
        # Check if we've reached the current point
        var distance = bot.global_position.distance_to(patrol_points[current_point])
        if distance < 0.5: # Close enough
            is_waiting = true
            wait_timer = 0.0
            bot.play_animation("idle")
            
    return continue_behavior()

func move_to_next_point() -> void:
    current_point = (current_point + 1) % patrol_points.size()
    bot.move_toward(patrol_points[current_point])

func setup_patrol_points() -> void:
    # In a real implementation, these would be loaded from the level
    # or dynamically generated based on the environment
    if patrol_points.is_empty():
        var center = bot.global_position
        patrol_points = [
            center + Vector3(10, 0, 0),
            center + Vector3(10, 0, 10),
            center + Vector3(0, 0, 10),
            center + Vector3(0, 0, 0)
        ]
        
        # Randomize starting point
        current_point = randi() % patrol_points.size()

# Override event handlers
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

func on_stuck() -> Dictionary:
    # Try next patrol point
    move_to_next_point()
    return continue_behavior() 