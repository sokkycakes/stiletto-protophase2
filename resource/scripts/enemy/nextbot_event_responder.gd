## NextBot Event Responder Interface
## Based on Source SDK NextBotEventResponderInterface.h
class_name INextBotEventResponder
extends Node

# Event propagation methods - override in derived classes
func get_first_contained_responder() -> INextBotEventResponder:
	return null

func get_next_contained_responder(current: INextBotEventResponder) -> INextBotEventResponder:
	return null

# Movement Events
func on_leave_ground(ground: Node3D) -> void:
	_propagate_event("on_leave_ground", [ground])

func on_land_on_ground(ground: Node3D) -> void:
	_propagate_event("on_land_on_ground", [ground])

func on_contact(other: Node3D, collision_info: Dictionary = {}) -> void:
	_propagate_event("on_contact", [other, collision_info])

# Path Events
func on_move_to_success(path) -> void:
	_propagate_event("on_move_to_success", [path])

func on_move_to_failure(path, reason) -> void:
	_propagate_event("on_move_to_failure", [path, reason])

func on_stuck() -> void:
	_propagate_event("on_stuck", [])

func on_unstuck() -> void:
	_propagate_event("on_unstuck", [])

# Animation Events
func on_posture_changed() -> void:
	_propagate_event("on_posture_changed", [])

func on_animation_activity_complete(activity: String) -> void:
	_propagate_event("on_animation_activity_complete", [activity])

func on_animation_activity_interrupted(activity: String) -> void:
	_propagate_event("on_animation_activity_interrupted", [activity])

func on_animation_event(event_data: Dictionary) -> void:
	_propagate_event("on_animation_event", [event_data])

# Combat Events
func on_ignite() -> void:
	_propagate_event("on_ignite", [])

func on_injured(damage_info: Dictionary) -> void:
	_propagate_event("on_injured", [damage_info])

func on_killed(damage_info: Dictionary) -> void:
	_propagate_event("on_killed", [damage_info])

func on_other_killed(victim: Node, damage_info: Dictionary) -> void:
	_propagate_event("on_other_killed", [victim, damage_info])

# Perception Events
func on_sight(subject: Node) -> void:
	_propagate_event("on_sight", [subject])

func on_lost_sight(subject: Node) -> void:
	_propagate_event("on_lost_sight", [subject])

func on_sound(source: Node, pos: Vector3, sound_data: Dictionary) -> void:
	_propagate_event("on_sound", [source, pos, sound_data])

func on_spoke_concept(who: Node, concept: String, response_data: Dictionary) -> void:
	_propagate_event("on_spoke_concept", [who, concept, response_data])

func on_weapon_fired(who_fired: Node, weapon: Node) -> void:
	_propagate_event("on_weapon_fired", [who_fired, weapon])

# Navigation Events
func on_nav_area_changed(new_area: NavigationRegion3D, old_area: NavigationRegion3D) -> void:
	_propagate_event("on_nav_area_changed", [new_area, old_area])

# Model Events
func on_model_changed() -> void:
	_propagate_event("on_model_changed", [])

# Inventory Events
func on_pick_up(item: Node, giver: Node = null) -> void:
	_propagate_event("on_pick_up", [item, giver])

func on_drop(item: Node) -> void:
	_propagate_event("on_drop", [item])

func on_actor_emoted(emoter: Node, emote: String) -> void:
	_propagate_event("on_actor_emoted", [emoter, emote])

# Command Events
func on_command_attack(victim: Node) -> void:
	_propagate_event("on_command_attack", [victim])

func on_command_approach(pos: Vector3, range: float = 0.0) -> void:
	_propagate_event("on_command_approach", [pos, range])

func on_command_approach_entity(goal: Node) -> void:
	_propagate_event("on_command_approach_entity", [goal])

func on_command_retreat(threat: Node, range: float = 0.0) -> void:
	_propagate_event("on_command_retreat", [threat, range])

func on_command_pause(duration: float = 0.0) -> void:
	_propagate_event("on_command_pause", [duration])

func on_command_resume() -> void:
	_propagate_event("on_command_resume", [])

func on_command_string(command: String) -> void:
	_propagate_event("on_command_string", [command])

# Physical Events
func on_shoved(pusher: Node) -> void:
	_propagate_event("on_shoved", [pusher])

func on_blinded(blinder: Node) -> void:
	_propagate_event("on_blinded", [blinder])

# Territory Events
func on_territory_contested(territory_id: int) -> void:
	_propagate_event("on_territory_contested", [territory_id])

func on_territory_captured(territory_id: int) -> void:
	_propagate_event("on_territory_captured", [territory_id])

func on_territory_lost(territory_id: int) -> void:
	_propagate_event("on_territory_lost", [territory_id])

# Game State Events
func on_win() -> void:
	_propagate_event("on_win", [])

func on_lose() -> void:
	_propagate_event("on_lose", [])

# Event propagation helper
func _propagate_event(method_name: String, args: Array) -> void:
	var responder = get_first_contained_responder()
	while responder != null:
		if responder.has_method(method_name):
			responder.callv(method_name, args)
		responder = get_next_contained_responder(responder)
