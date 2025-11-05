extends Behavior
class_name AttackBehavior

var target: Node = null
var attack_range: float = 10.0
var attack_timer: float = 0.0
var attack_cooldown: float = 1.0
var strafe_direction: float = 1.0
var strafe_timer: float = 0.0
var strafe_duration: float = 2.0

func _init() -> void:
    name = "attack"

func on_start() -> void:
    target = bot.get_nearest_threat()
    attack_timer = attack_cooldown # Allow immediate first attack
    strafe_timer = 0.0
    strafe_direction = 1.0 if randf() > 0.5 else -1.0
    bot.play_animation("combat_ready")

func update(delta: float) -> Dictionary:
    if not is_instance_valid(target):
        return change_to("seek_and_destroy")
    
    var distance = bot.global_position.distance_to(target.global_position)
    
    # Update timers
    attack_timer += delta
    strafe_timer += delta
    
    # Face target
    bot.face_toward(target.global_position)
    
    # Handle movement
    if distance > attack_range:
        # Move closer
        bot.move_toward(target.global_position)
        bot.play_animation("run")
    else:
        # Strafe while in range
        strafe_around_target(delta)
        bot.play_animation("combat_strafe")
        
        # Attack when possible
        if attack_timer >= attack_cooldown:
            perform_attack()
    
    # Switch to retreat if health is low
    if bot.is_health_low():
        return change_to("retreat")
    
    return continue_behavior()

func strafe_around_target(delta: float) -> void:
    if strafe_timer >= strafe_duration:
        strafe_timer = 0.0
        strafe_direction *= -1.0 # Change direction
    
    # Calculate strafe movement
    var to_target = target.global_position - bot.global_position
    var strafe = to_target.cross(Vector3.UP).normalized()
    var strafe_pos = bot.global_position + (strafe * strafe_direction * 5.0)
    
    # Keep distance while strafing
    var ideal_pos = target.global_position - to_target.normalized() * attack_range
    strafe_pos = (strafe_pos + ideal_pos) * 0.5
    
    bot.move_toward(strafe_pos)

func perform_attack() -> void:
    attack_timer = 0.0
    bot.play_animation("attack")
    
    # In a real implementation, this would trigger weapon fire,
    # spawn projectiles, or apply damage based on the bot's weapon type

# Override event handlers
func on_sight(entity: Node) -> Dictionary:
    if not target and bot.is_threat(entity):
        target = entity
    return continue_behavior()

func on_lost_sight(entity: Node) -> Dictionary:
    if entity == target:
        return change_to("seek_and_destroy")
    return continue_behavior()

func on_injured(damage: float, attacker: Node) -> Dictionary:
    if bot.is_health_low():
        return change_to("retreat")
    elif attacker and attacker != target:
        # Switch targets if the new attacker is closer
        var current_distance = bot.global_position.distance_to(target.global_position)
        var new_distance = bot.global_position.distance_to(attacker.global_position)
        if new_distance < current_distance:
            target = attacker
    return continue_behavior()

func on_stuck() -> Dictionary:
    # Try to find a better attack position
    var new_pos = target.global_position + Vector3(randf() * 4.0 - 2.0, 0, randf() * 4.0 - 2.0)
    bot.move_toward(new_pos)
    return continue_behavior() 