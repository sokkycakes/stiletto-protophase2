## NextBot Component Interface - Base class for all NextBot components
## Based on Source SDK NextBotComponentInterface.h
class_name INextBotComponent
extends INextBotEventResponder

# Component properties
var bot
var component_name: String = ""
var is_initialized: bool = false
var last_update_time: float = 0.0

# Component lifecycle
func initialize(bot_ref) -> void:
	bot = bot_ref
	is_initialized = true
	on_initialize()

func reset() -> void:
	on_reset()

func update(delta: float) -> void:
	if not is_initialized:
		return
		
	last_update_time = Time.get_unix_time_from_system()
	on_update(delta)

func upkeep() -> void:
	on_upkeep()

# Virtual methods - override in derived classes
func on_initialize() -> void:
	pass

func on_reset() -> void:
	pass

func on_update(_delta: float) -> void:
	pass

func on_upkeep() -> void:
	pass

# Utility methods
func get_bot():
	return bot

func get_component_name() -> String:
	return component_name

func set_component_name(name: String) -> void:
	component_name = name

func is_valid() -> bool:
	return is_initialized and bot != null

# Event propagation override - components don't contain other responders by default
func get_first_contained_responder() -> INextBotEventResponder:
	return null

func get_next_contained_responder(_current: INextBotEventResponder) -> INextBotEventResponder:
	return null
