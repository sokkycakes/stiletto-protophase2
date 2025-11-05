extends Area3D

@export var target_scene: String = "res://scenes/level1.tscn"  # Set this in the editor to specify which scene to load

func _ready():
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if body.is_in_group("player"):
		SceneLoader.change_scene(target_scene)
