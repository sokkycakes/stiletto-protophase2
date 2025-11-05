## NextBot Manager - Global manager for all NextBot entities
## Based on Source SDK NextBotManager.h
extends Node

# This should be added as an autoload singleton in project settings
# Project -> Project Settings -> Autoload -> Add this script as "NextBotManager"

# Bot management
var registered_bots = []
var bot_id_counter = 0

# Update management
var update_tickrate = 60
var bots_per_frame = 5
var current_update_index = 0

# Debug system
var debug_types = 0
var debug_filter = []
var selected_bot = null

# Debug flags
enum DebugType {
	NONE = 0,
	BEHAVIOR = 1,
	LOOK_AT = 2,
	PATH = 4,
	ANIMATION = 8,
	LOCOMOTION = 16,
	VISION = 32,
	ALL = 63
}

func _ready():
	set_process(true)
	print("NextBotManager initialized as autoload singleton")

# Bot registration
func register_bot(bot):
	if bot in registered_bots:
		return bot.bot_id if bot.has_method("get_bot_id") else -1

	if bot.has_method("set_bot_id"):
		bot.bot_id = bot_id_counter
		bot_id_counter += 1
		registered_bots.append(bot)

		var debug_name = bot.get_debug_name() if bot.has_method("get_debug_name") else str(bot)
		print("NextBot registered: ", debug_name, " (ID: ", bot.bot_id, ")")
		return bot.bot_id

	return -1

func unregister_bot(bot):
	if bot in registered_bots:
		registered_bots.erase(bot)
		var debug_name = bot.get_debug_name() if bot.has_method("get_debug_name") else str(bot)
		var bot_id = bot.bot_id if "bot_id" in bot else -1
		print("NextBot unregistered: ", debug_name, " (ID: ", bot_id, ")")

# Update management
func _process(delta):
	update_bots(delta)

func update_bots(delta):
	if registered_bots.is_empty():
		return
	
	# Update a subset of bots each frame for performance
	var bots_to_update = min(bots_per_frame, registered_bots.size())
	
	for i in range(bots_to_update):
		var bot_index = (current_update_index + i) % registered_bots.size()
		var bot = registered_bots[bot_index]
		
		if is_instance_valid(bot):
			# Bot will handle its own update cycle
			pass
		else:
			# Remove invalid bot
			registered_bots.remove_at(bot_index)
			if current_update_index >= registered_bots.size():
				current_update_index = 0
	
	current_update_index = (current_update_index + bots_to_update) % max(1, registered_bots.size())

func should_update(bot):
	# Simple update policy - can be enhanced with distance checks, etc.
	return is_instance_valid(bot)

func notify_begin_update(bot):
	# Called when bot begins its update cycle
	pass

func notify_end_update(bot):
	# Called when bot ends its update cycle
	pass

# Bot queries
func get_nextbot_count():
	return registered_bots.size()

func collect_all_bots(output_array):
	output_array.clear()
	for bot in registered_bots:
		if is_instance_valid(bot):
			output_array.append(bot)

func for_each_bot(functor):
	for bot in registered_bots:
		if is_instance_valid(bot):
			if not functor.call(bot):
				return false
	return true

func get_closest_bot(pos, filter = null):
	var closest_bot = null
	var closest_distance = INF

	for bot in registered_bots:
		if not is_instance_valid(bot):
			continue

		if filter and not filter.call(bot):
			continue

		var bot_pos = bot.global_position
		var distance = pos.distance_to(bot_pos)
		if distance < closest_distance:
			closest_distance = distance
			closest_bot = bot

	return closest_bot

# Event propagation
func on_map_loaded():
	for bot in registered_bots:
		if is_instance_valid(bot):
			# Reset bot state for new map
			if "locomotion_interface" in bot and bot.locomotion_interface:
				if bot.locomotion_interface.has_method("reset"):
					bot.locomotion_interface.reset()
			if "vision_interface" in bot and bot.vision_interface:
				if bot.vision_interface.has_method("reset"):
					bot.vision_interface.reset()
			if "intention_interface" in bot and bot.intention_interface:
				if bot.intention_interface.has_method("reset"):
					bot.intention_interface.reset()

func on_round_restart():
	for bot in registered_bots:
		if is_instance_valid(bot):
			# Reset bot state for new round
			if "locomotion_interface" in bot and bot.locomotion_interface:
				if bot.locomotion_interface.has_method("reset"):
					bot.locomotion_interface.reset()
			if "vision_interface" in bot and bot.vision_interface:
				if bot.vision_interface.has_method("reset"):
					bot.vision_interface.reset()
			if "intention_interface" in bot and bot.intention_interface:
				if bot.intention_interface.has_method("reset"):
					bot.intention_interface.reset()

func on_killed(victim, damage_info):
	for bot in registered_bots:
		if is_instance_valid(bot):
			if bot.has_method("on_other_killed"):
				bot.on_other_killed(victim, damage_info)

func on_sound(source, pos, sound_data):
	for bot in registered_bots:
		if is_instance_valid(bot):
			if bot.has_method("on_sound"):
				bot.on_sound(source, pos, sound_data)

func on_weapon_fired(who_fired, weapon):
	for bot in registered_bots:
		if is_instance_valid(bot):
			if bot.has_method("on_weapon_fired"):
				bot.on_weapon_fired(who_fired, weapon)

# Debug system
func is_debugging(type):
	return (debug_types & type) != 0

func set_debug_types(types):
	debug_types = types
	print("NextBot debug types set to: ", types)

func debug_filter_add(filter):
	if filter not in debug_filter:
		debug_filter.append(filter)
		print("Added debug filter: ", filter)

func debug_filter_remove(filter):
	if filter in debug_filter:
		debug_filter.erase(filter)
		print("Removed debug filter: ", filter)

func debug_filter_clear():
	debug_filter.clear()
	print("Cleared debug filters")

func is_debug_filter_match(bot):
	if debug_filter.is_empty():
		return true

	for filter in debug_filter:
		if bot.has_method("is_debug_filter_match") and bot.is_debug_filter_match(filter):
			return true

	return false

func select_bot(bot):
	selected_bot = bot
	if bot:
		var debug_name = bot.get_debug_name() if bot.has_method("get_debug_name") else str(bot)
		print("Selected bot: ", debug_name)

func deselect_all():
	selected_bot = null
	print("Deselected all bots")

func get_selected_bot():
	return selected_bot

func get_bot_under_crosshair(_picker):
	# Implementation would depend on your camera/input system
	# This is a placeholder
	return null

# Utility functions
func reset():
	for bot in registered_bots:
		if is_instance_valid(bot):
			if "locomotion_interface" in bot and bot.locomotion_interface:
				if bot.locomotion_interface.has_method("reset"):
					bot.locomotion_interface.reset()
			if "vision_interface" in bot and bot.vision_interface:
				if bot.vision_interface.has_method("reset"):
					bot.vision_interface.reset()
			if "intention_interface" in bot and bot.intention_interface:
				if bot.intention_interface.has_method("reset"):
					bot.intention_interface.reset()

# Console commands (for debugging)
func _input(event):
	if not OS.is_debug_build():
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				if event.ctrl_pressed:
					toggle_debug(DebugType.BEHAVIOR)
			KEY_F2:
				if event.ctrl_pressed:
					toggle_debug(DebugType.PATH)
			KEY_F3:
				if event.ctrl_pressed:
					toggle_debug(DebugType.VISION)

func toggle_debug(type):
	if is_debugging(type):
		debug_types &= ~type
		print("Disabled debug type: ", type)
	else:
		debug_types |= type
		print("Enabled debug type: ", type)
