extends Control

@export var intro_scene_path: String = "res://maps/intro00.tscn"
@export var tower_scene_path: String = "res://maps/obby00.tscn"
@export var obby_scene_path: String = "res://maps/sandbox-night.tscn"
@export var options_scene_path: String = "res://resource/system/config/resolution_settings.tscn"

@onready var options_button = $Panel/VBoxContainerSub/OptionsButton
var map_browser_scene = preload("res://resource/system/map_browser.tscn")

func _ready():
	# Ensure mouse is visible for menu navigation
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	$Panel/VBoxContainer/IntroButton.pressed.connect(_on_intro_button_pressed)
	$Panel/VBoxContainerSub/TowerButton.pressed.connect(_on_tower_button_pressed)
	$Panel/VBoxContainerSub/ObbyButton.pressed.connect(_on_obby_button_pressed)
	$Panel/VBoxContainerSub/MapsButton.pressed.connect(_on_maps_button_pressed)
	options_button.pressed.connect(_on_options_button_pressed)

func _on_intro_button_pressed():
	get_tree().change_scene_to_file(intro_scene_path)

func _on_tower_button_pressed():
	get_tree().change_scene_to_file(tower_scene_path)

func _on_obby_button_pressed():
	get_tree().change_scene_to_file(obby_scene_path)

func _on_maps_button_pressed():
	var map_browser_instance = map_browser_scene.instantiate()
	add_child(map_browser_instance)
	map_browser_instance.popup_centered()

func _on_options_button_pressed():
	get_tree().change_scene_to_file(options_scene_path) 
