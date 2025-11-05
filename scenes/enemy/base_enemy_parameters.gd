extends Node

signal health_changed(new_health: float, max_health: float)
signal parameter_changed(parameter_name: String, new_value: float)

@export var max_health: float = 100.0
@export var move_speed: float = 5.0
@export var gravity: float = 20.0
@export var jump_velocity: float = 4.5
@export var acceleration: float = 15.0
@export var friction: float = 10.0

var current_health: float

func _ready() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)

func take_damage(amount: float) -> void:
	current_health = max(0.0, current_health - amount)
	health_changed.emit(current_health, max_health)
	
	if current_health <= 0.0:
		die()

func heal(amount: float) -> void:
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

func die() -> void:
	# Signal to parent that enemy has died
	get_parent().queue_free()

func get_health_percentage() -> float:
	return current_health / max_health

func set_parameter(parameter_name: String, value: float) -> void:
	if parameter_name in self:
		set(parameter_name, value)
		parameter_changed.emit(parameter_name, value) 