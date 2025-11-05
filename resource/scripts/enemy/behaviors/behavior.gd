extends RefCounted
class_name Behavior

var bot: EnemyNextBot
var name: String = "behavior"
var previous_behavior: Behavior = null

func initialize(bot_ref: EnemyNextBot) -> void:
    bot = bot_ref

func on_start() -> void:
    pass

func on_end() -> void:
    pass

func on_suspend() -> void:
    pass

func on_resume() -> void:
    pass

func update(delta: float) -> Dictionary:
    return {
        "type": "CONTINUE"
    }

# Event handlers
func on_sight(entity: Node) -> Dictionary:
    return {
        "type": "CONTINUE"
    }

func on_lost_sight(entity: Node) -> Dictionary:
    return {
        "type": "CONTINUE"
    }

func on_injured(damage: float, attacker: Node) -> Dictionary:
    return {
        "type": "CONTINUE"
    }

func on_stuck() -> Dictionary:
    return {
        "type": "CONTINUE"
    }

# Utility functions
func change_to(behavior_name: String) -> Dictionary:
    return {
        "type": "CHANGE_TO",
        "behavior": behavior_name
    }

func suspend_for(behavior_name: String) -> Dictionary:
    return {
        "type": "SUSPEND_FOR",
        "behavior": behavior_name
    }

func done(next_behavior: String = "") -> Dictionary:
    var result = {
        "type": "DONE"
    }
    if next_behavior:
        result["next_behavior"] = next_behavior
    return result

func continue_behavior() -> Dictionary:
    return {
        "type": "CONTINUE"
    } 