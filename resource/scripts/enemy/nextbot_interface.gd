## NextBot Interface - Core interface for all NextBot entities
## Based on Source SDK NextBotInterface.h
class_name INextBot
extends CharacterBody3D

# Core component interfaces - must be implemented by derived classes
var locomotion_interface
var body_interface
var vision_interface
var intention_interface

# Bot properties
var bot_id: int = -1
var debug_name: String = ""
var is_debug_enabled: bool = false

# Entity references
var last_known_area: NavigationRegion3D
var current_path

# Initialization
func _ready() -> void:
	# Register with NextBot manager
	NextBotManager.register_bot(self)
	
	# Initialize components
	_initialize_components()
	
	# Connect to navigation signals if NavigationAgent3D exists
	var nav_agent = get_navigation_agent()
	if nav_agent:
		nav_agent.velocity_computed.connect(_on_velocity_computed)

func _exit_tree() -> void:
	# Unregister from manager
	NextBotManager.unregister_bot(self)

# Abstract methods - must be implemented by derived classes
func get_locomotion_interface():
	assert(false, "get_locomotion_interface() must be implemented by derived class")
	return null

func get_body_interface():
	assert(false, "get_body_interface() must be implemented by derived class")
	return null

func get_vision_interface():
	assert(false, "get_vision_interface() must be implemented by derived class")
	return null

func get_intention_interface():
	assert(false, "get_intention_interface() must be implemented by derived class")
	return null

# Component initialization
func _initialize_components() -> void:
	locomotion_interface = get_locomotion_interface()
	body_interface = get_body_interface()
	vision_interface = get_vision_interface()
	intention_interface = get_intention_interface()
	
	# Initialize each component
	if locomotion_interface:
		locomotion_interface.initialize(self)
	if body_interface:
		body_interface.initialize(self)
	if vision_interface:
		vision_interface.initialize(self)
	if intention_interface:
		intention_interface.initialize(self)

# Update cycle
func _physics_process(delta: float) -> void:
	if not NextBotManager.should_update(self):
		return
		
	NextBotManager.notify_begin_update(self)
	
	# Update components in order
	if vision_interface:
		vision_interface.update(delta)
	if intention_interface:
		intention_interface.update(delta)
	if locomotion_interface:
		locomotion_interface.update(delta)
	if body_interface:
		body_interface.update(delta)
	
	NextBotManager.notify_end_update(self)

# Utility methods
# Note: get_position() is inherited from Node3D, use global_position directly

func get_entity() -> Node:
	return self

func get_navigation_agent() -> NavigationAgent3D:
	# Try to find NavigationAgent3D in children
	for child in get_children():
		if child is NavigationAgent3D:
			return child
	return null

func is_debug_filter_match(filter_name: String) -> bool:
	return debug_name == filter_name or str(bot_id) == filter_name

# Navigation callback
func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()

# Debug
func get_debug_name() -> String:
	if debug_name.is_empty():
		return "NextBot_%d" % bot_id
	return debug_name

func set_debug_name(name: String) -> void:
	debug_name = name
