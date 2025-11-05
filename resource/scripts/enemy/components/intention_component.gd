extends Node
class_name IntentionComponent

var bot: EnemyNextBot
var current_behavior: Behavior = null
var behaviors: Dictionary = {}

func initialize(bot_ref: EnemyNextBot) -> void:
    bot = bot_ref
    setup_behaviors()

func setup_behaviors() -> void:
    # Create and register behaviors
    behaviors = {
        "idle": IdleBehavior.new(),
        "patrol": PatrolBehavior.new(),
        "seek_and_destroy": SeekAndDestroyBehavior.new(),
        "attack": AttackBehavior.new(),
        "retreat": RetreatBehavior.new(),
        "get_health": GetHealthBehavior.new(),
        "get_ammo": GetAmmoBehavior.new(),
        "dead": DeadBehavior.new()
    }
    
    # Initialize behaviors
    for behavior in behaviors.values():
        behavior.initialize(bot)

func update(delta: float) -> void:
    if current_behavior == null:
        change_behavior("idle")
        
    if current_behavior:
        var result = current_behavior.update(delta)
        handle_behavior_result(result)

func handle_behavior_result(result: Dictionary) -> void:
    match result.type:
        "CONTINUE":
            pass # Keep current behavior
        "CHANGE_TO":
            change_behavior(result.behavior)
        "SUSPEND_FOR":
            suspend_for_behavior(result.behavior)
        "DONE":
            # Return to previous behavior or select new one
            if result.has("next_behavior"):
                change_behavior(result.next_behavior)
            else:
                select_next_behavior()

func change_behavior(behavior_name: String) -> void:
    if not behaviors.has(behavior_name):
        push_error("Invalid behavior name: " + behavior_name)
        return
        
    var new_behavior = behaviors[behavior_name]
    
    if current_behavior:
        current_behavior.on_end()
        
    current_behavior = new_behavior
    current_behavior.on_start()

func suspend_for_behavior(behavior_name: String) -> void:
    if not behaviors.has(behavior_name):
        push_error("Invalid behavior name: " + behavior_name)
        return
        
    var new_behavior = behaviors[behavior_name]
    
    if current_behavior:
        current_behavior.on_suspend()
        new_behavior.previous_behavior = current_behavior
        
    current_behavior = new_behavior
    current_behavior.on_start()

func select_next_behavior() -> void:
    # Priority-based behavior selection
    if bot.is_dead:
        change_behavior("dead")
    elif bot.is_health_low():
        change_behavior("get_health")
    elif bot.has_threats():
        var threat = bot.get_nearest_threat()
        if threat and bot.can_see(threat):
            change_behavior("attack")
        else:
            change_behavior("seek_and_destroy")
    else:
        change_behavior("patrol")

func evaluate_threat(entity: Node) -> void:
    if current_behavior.name != "attack" and current_behavior.name != "retreat":
        if should_attack(entity):
            change_behavior("attack")
        elif should_retreat(entity):
            change_behavior("retreat")

func evaluate_threat_lost(entity: Node) -> void:
    if current_behavior.name == "attack":
        if not bot.has_threats():
            change_behavior("seek_and_destroy")

func evaluate_retreat_need() -> void:
    if should_retreat_from_damage():
        change_behavior("retreat")

func evaluate_stuck_state() -> void:
    if current_behavior.name == "attack" or current_behavior.name == "seek_and_destroy":
        # Try to find alternative path or retreat
        if should_retreat_from_stuck():
            change_behavior("retreat")

func should_attack(entity: Node) -> bool:
    # Implement attack decision logic
    if not bot.can_see(entity):
        return false
        
    var distance = bot.global_position.distance_to(entity.global_position)
    return distance < 10.0 # Attack range

func should_retreat(entity: Node) -> bool:
    # Implement retreat decision logic
    if bot.is_health_low():
        return true
        
    var distance = bot.global_position.distance_to(entity.global_position)
    return distance < 2.0 # Too close

func should_retreat_from_damage() -> bool:
    return bot.is_health_low()

func should_retreat_from_stuck() -> bool:
    # Implement stuck retreat logic
    # For example, if stuck for too long or in dangerous situation
    return false 