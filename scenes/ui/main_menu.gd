extends Control

@onready var single_player_button = $MenuContainer/SinglePlayerButton
@onready var multiplayer_button = $MenuContainer/MultiplayerButton
@onready var map_browser_button = $MenuContainer/MapBrowserButton
@onready var options_button = $MenuContainer/OptionsButton
@onready var quit_button = $MenuContainer/QuitButton

# Exported scene paths - configurable in the editor inspector
@export var single_player_scene_path: String = "res://maps/sandbox.tscn"

# Map browser scene reference
var map_browser_scene = preload("res://resource/system/map_browser.tscn")

func _ready():
	# Connect button signals
	single_player_button.pressed.connect(_on_single_player_pressed)
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	map_browser_button.pressed.connect(_on_map_browser_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Set mouse mode
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_single_player_pressed():
	# Load single player scene using the exported path
	if Engine.has_singleton("SceneLoader"):
		SceneLoader.change_scene(single_player_scene_path)
	else:
		get_tree().change_scene_to_file(single_player_scene_path)

func _on_multiplayer_pressed():
	# Alternative approach: Use scene switching for more reliable UI
	# Store a reference to return to main menu
	var mp_menu_path := "res://scenes/mp_framework/main_menu.tscn"
	if Engine.has_singleton("SceneLoader"):
		SceneLoader.change_scene(mp_menu_path)
	else:
		get_tree().change_scene_to_file(mp_menu_path)

func _on_map_browser_pressed():
	# Open the map browser window
	var map_browser_instance = map_browser_scene.instantiate()
	add_child(map_browser_instance)
	map_browser_instance.popup_centered()

func _on_options_pressed():
	# Show options menu (if you have one)
	print("Options menu not implemented yet")

func _on_quit_pressed():
	get_tree().quit()

# These methods are no longer needed with the standalone approach
