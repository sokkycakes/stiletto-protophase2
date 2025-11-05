extends Node3D

@export var angular_speed_deg: float = 90.0 # degrees per second

func _process(delta: float) -> void:
    rotate_y(deg_to_rad(angular_speed_deg) * delta) 