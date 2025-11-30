extends Node

# Health component that can be plugged into any Node/Character.
# Implements 2 HP system with invulnerability and healing mechanics

# Exported properties
@export var max_health: int = 4 : set = _set_max_health
@export var start_health: int = 4
@export var invulnerability_duration: float = 1.3  # Seconds of invulnerability after taking damage
@export var healing_delay: float = 12.0  # Seconds before healing starts when not taking damage

# Signals
signal health_changed(current_health: int, max_health: int)
signal damage_taken(amount: int, current_health: int, max_health: int, skip_stun: bool)
signal died
signal invulnerability_started
signal invulnerability_ended
signal healing_started
signal healing_completed

var _current_health: int
var _is_invulnerable: bool = false
var _invulnerability_timer: float = 0.0
var _healing_timer: float = 0.0
var _is_healing: bool = false
var _last_damage_time: float = 0.0

func _ready() -> void:
	# Clamp starting health to be within bounds
	max_health = max(1, max_health)
	_current_health = clamp(start_health, 0, max_health)
	emit_signal("health_changed", _current_health, max_health)

func _set_max_health(value: int) -> void:
	max_health = max(1, value)
	_current_health = clamp(_current_health, 0, max_health)
	emit_signal("health_changed", _current_health, max_health)

func _process(delta: float) -> void:
	# Handle invulnerability timer
	if _is_invulnerable:
		_invulnerability_timer -= delta
		if _invulnerability_timer <= 0.0:
			_is_invulnerable = false
			emit_signal("invulnerability_ended")
			print("Health: Invulnerability ended")
	
	# Handle healing timer
	if not _is_invulnerable and _current_health < max_health:
		var time_since_damage = Time.get_unix_time_from_system() - _last_damage_time
		if time_since_damage >= healing_delay:
			if not _is_healing:
				_is_healing = true
				emit_signal("healing_started")
				print("Health: Healing started")
			_healing_timer += delta
			if _healing_timer >= 0.1:  # Heal every 0.1 seconds for smooth healing
				_healing_timer = 0.0
				heal(1)
		else:
			# Reset healing if damage was taken recently
			if _is_healing:
				_is_healing = false
				_healing_timer = 0.0
				print("Health: Healing interrupted by recent damage")

func take_damage(amount: int = 1, skip_invulnerability: bool = false) -> void:
	if amount <= 0 or is_dead() or (_is_invulnerable and not skip_invulnerability):
		print("Health: Damage blocked - dead: ", is_dead(), ", invulnerable: ", _is_invulnerable)
		return
	
	_current_health = max(_current_health - amount, 0)
	_last_damage_time = Time.get_unix_time_from_system()
	
	# Start invulnerability only if not skipping (for PvP damage)
	if not skip_invulnerability:
		_is_invulnerable = true
		_invulnerability_timer = invulnerability_duration
		emit_signal("invulnerability_started")
	
	# Reset healing
	_is_healing = false
	_healing_timer = 0.0
	
	# Determine if stun should be skipped (same condition as invulnerability)
	var skip_stun = skip_invulnerability
	emit_signal("damage_taken", amount, _current_health, max_health, skip_stun)
	emit_signal("health_changed", _current_health, max_health)
	
	if skip_invulnerability:
		print("Health: Damage taken (PvP) - amount: ", amount, ", new health: ", _current_health, ", invulnerability skipped")
	else:
		print("Health: Damage taken - amount: ", amount, ", new health: ", _current_health, ", invulnerable for: ", invulnerability_duration, "s")
	
	if _current_health == 0:
		emit_signal("died")

func heal(amount: int = 1) -> void:
	if amount <= 0 or is_dead():
		return
	
	var old_health = _current_health
	_current_health = min(_current_health + amount, max_health)
	
	if _current_health != old_health:
		emit_signal("health_changed", _current_health, max_health)
		print("Health: Healed - new health: ", _current_health)
		
		if _current_health >= max_health:
			_is_healing = false
			_healing_timer = 0.0
			emit_signal("healing_completed")
			print("Health: Healing completed")

func is_dead() -> bool:
	return _current_health <= 0

func is_invulnerable() -> bool:
	return _is_invulnerable

func is_healing() -> bool:
	return _is_healing

func get_current_health() -> int:
	return _current_health

func get_invulnerability_time_remaining() -> float:
	return max(0.0, _invulnerability_timer)

func get_healing_time_remaining() -> float:
	if _current_health >= max_health:
		return 0.0
	var time_since_damage = Time.get_unix_time_from_system() - _last_damage_time
	return max(0.0, healing_delay - time_since_damage)

func restore_full_health() -> void:
	## Fully restore health to max (used on respawn)
	## Bypasses dead check and resets all timers
	var old_health = _current_health
	_current_health = max_health
	_is_invulnerable = false
	_invulnerability_timer = 0.0
	_is_healing = false
	_healing_timer = 0.0
	_last_damage_time = 0.0
	
	print("[Health Component] restore_full_health - old: ", old_health, " -> new: ", _current_health, "/", max_health)
	print("[Health Component] Emitting health_changed signal: (", _current_health, ", ", max_health, ")")
	emit_signal("health_changed", _current_health, max_health) 
