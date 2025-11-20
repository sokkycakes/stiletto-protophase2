extends Control

@export var config_path: String = "user://resolution_settings.cfg"

const DEFAULT_SETTINGS = {
	"window_base_width": 800,
	"window_base_height": 600,
	"stretch_mode": Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
	"stretch_aspect": Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT,
	"scale_factor": 1.0,
	"gui_aspect_ratio": -1.0,  # -1.0 means "Fit to Window"
	"gui_margin": 0.0,
	"window_resolution": 1,  # Default to 800x600
	"fullscreen": false
}

var config: ConfigFile
var current_settings: Dictionary

@onready var gui_margin_slider = $Panel/VBoxContainer/GUIMarginContainer/HSlider
@onready var gui_margin_value = $Panel/VBoxContainer/GUIMarginContainer/ValueContainer/Value
@onready var gui_margin_edit = $Panel/VBoxContainer/GUIMarginContainer/ValueContainer/LineEdit
@onready var resolution_option = $Panel/VBoxContainer/ResolutionContainer/OptionButton
@onready var fullscreen_checkbox = $Panel/VBoxContainer/FullscreenContainer/CheckBox
@onready var panel = $Panel

var resolution_manager: Node

func _ready():
	# Get the resolution manager
	resolution_manager = get_node("/root/ResolutionManager")
	if not resolution_manager:
		push_error("ResolutionManager not found!")
		return
	
	# Connect signals
	gui_margin_slider.value_changed.connect(_on_gui_margin_slider_value_changed)
	gui_margin_edit.text_submitted.connect(_on_gui_margin_edit_text_submitted)
	resolution_option.item_selected.connect(_on_resolution_selected)
	fullscreen_checkbox.toggled.connect(_on_fullscreen_toggled)
	
	# Connect to resolution manager signals
	resolution_manager.settings_changed.connect(_on_settings_changed)
	
	# Initialize UI with current settings
	update_ui_from_settings(resolution_manager.get_current_settings())
	# Add a quick way to return to the main menu.
	# If there is a child Button named "BackButton", connect it automatically.
	var back_btn := get_node_or_null("BackButton")
	if back_btn:
		back_btn.pressed.connect(_return_to_main_menu)

func load_settings():
	var err = config.load(config_path)
	if err == OK:
		# Load saved settings
		current_settings = {
			"window_base_width": config.get_value("display", "window_base_width", DEFAULT_SETTINGS.window_base_width),
			"window_base_height": config.get_value("display", "window_base_height", DEFAULT_SETTINGS.window_base_height),
			"stretch_mode": config.get_value("display", "stretch_mode", DEFAULT_SETTINGS.stretch_mode),
			"stretch_aspect": config.get_value("display", "stretch_aspect", DEFAULT_SETTINGS.stretch_aspect),
			"scale_factor": config.get_value("display", "scale_factor", DEFAULT_SETTINGS.scale_factor),
			"gui_aspect_ratio": config.get_value("display", "gui_aspect_ratio", DEFAULT_SETTINGS.gui_aspect_ratio),
			"gui_margin": config.get_value("display", "gui_margin", DEFAULT_SETTINGS.gui_margin),
			"window_resolution": config.get_value("display", "window_resolution", DEFAULT_SETTINGS.window_resolution),
			"fullscreen": config.get_value("display", "fullscreen", DEFAULT_SETTINGS.fullscreen)
		}
	else:
		# Use default settings
		current_settings = DEFAULT_SETTINGS.duplicate()
	
	# Update UI
	gui_margin_slider.value = current_settings.gui_margin
	gui_margin_value.text = str(current_settings.gui_margin)
	gui_margin_edit.text = str(current_settings.gui_margin)
	resolution_option.selected = current_settings.window_resolution
	fullscreen_checkbox.button_pressed = current_settings.fullscreen

func save_settings():
	# Save all settings to config file
	for key in current_settings:
		config.set_value("display", key, current_settings[key])
	config.save(config_path)

func apply_settings():
	# Apply window size or display mode resolution
	var resolutions = [
		Vector2i(640, 480),
		Vector2i(800, 600),
		Vector2i(1280, 720),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440)
	]
	var selected_resolution = resolutions[current_settings.window_resolution]

	if current_settings.fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.window_set_size(selected_resolution)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().size = selected_resolution

	# Apply viewport settings
	get_viewport().content_scale_size = Vector2(current_settings.window_base_width, current_settings.window_base_height)
	get_viewport().content_scale_mode = current_settings.stretch_mode
	get_viewport().content_scale_aspect = current_settings.stretch_aspect
	get_viewport().content_scale_factor = current_settings.scale_factor

	# Apply GUI margin
	apply_gui_margin()

func apply_gui_margin():
	if panel:
		if is_equal_approx(current_settings.gui_aspect_ratio, -1.0):
			# Fit to Window mode
			panel.offset_top = current_settings.gui_margin
			panel.offset_bottom = -current_settings.gui_margin
		else:
			# Constrained aspect ratio mode
			panel.offset_top = current_settings.gui_margin / current_settings.gui_aspect_ratio
			panel.offset_bottom = -current_settings.gui_margin / current_settings.gui_aspect_ratio
		
		panel.offset_left = current_settings.gui_margin
		panel.offset_right = -current_settings.gui_margin

func _on_resized():
	apply_gui_margin.call_deferred()

func _on_gui_margin_slider_value_changed(value: float):
	resolution_manager.set_gui_margin(value)

func _on_gui_margin_edit_text_submitted(new_text: String):
	var value = float(new_text)
	value = clamp(value, 0, 100)
	gui_margin_slider.value = value
	resolution_manager.set_gui_margin(value)

func _on_resolution_selected(index: int):
	resolution_manager.set_resolution(index)

func _on_fullscreen_toggled(button_pressed: bool):
	resolution_manager.set_fullscreen(button_pressed)

func _on_settings_changed(settings: Dictionary):
	update_ui_from_settings(settings)

func update_ui_from_settings(settings: Dictionary):
	gui_margin_slider.value = settings.get("gui_margin", 0.0)
	gui_margin_value.text = str(settings.get("gui_margin", 0.0))
	gui_margin_edit.text = str(settings.get("gui_margin", 0.0))
	resolution_option.selected = settings.get("window_resolution", 1)
	fullscreen_checkbox.button_pressed = settings.get("fullscreen", false)

func _on_window_size_changed():
	# Prevent window resizing by user
	apply_settings() 

func _unhandled_input(event):
	if visible and get_tree().current_scene == self and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled() # Mark input as handled immediately
		_return_to_main_menu()

func _return_to_main_menu():
	# Go back to the new main menu scene.
	# Use SceneLoader if the singleton exists; otherwise fallback to change_scene_to_file.
	var menu_path := "res://scenes/ui/main_menu.tscn"
	if Engine.has_singleton("SceneLoader"):
		SceneLoader.change_scene(menu_path)
	else:
		get_tree().change_scene_to_file(menu_path) 
