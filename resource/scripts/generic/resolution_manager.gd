extends Node

signal settings_changed(settings: Dictionary)
signal resolution_changed(index: int)
signal fullscreen_changed(enabled: bool)
signal gui_margin_changed(margin: float)

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

const RESOLUTIONS = [
	Vector2i(640, 480),
	Vector2i(800, 600),
	Vector2i(1280, 720),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]

var config: ConfigFile
var current_settings: Dictionary
var config_path: String = "user://resolution_settings.cfg"

func _ready():
	# Initialize config
	config = ConfigFile.new()
	load_settings()

	# For web exports, don't apply settings immediately - let HTML shell control resolution
	if OS.has_feature("web"):
		print("🌐 Web export detected - skipping initial apply_settings() to allow HTML shell control")
		setup_web_communication()
	else:
		# For desktop, apply settings normally
		apply_settings()

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
		save_settings()  # Save default settings
	
	settings_changed.emit(current_settings)

func save_settings():
	# Save all settings to config file
	for key in current_settings:
		config.set_value("display", key, current_settings[key])
	config.save(config_path)

func apply_settings():
	# Apply window size or display mode resolution
	var selected_resolution = RESOLUTIONS[current_settings.window_resolution]

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

func set_resolution(index: int):
	if index >= 0 and index < RESOLUTIONS.size():
		current_settings.window_resolution = index
		apply_settings()
		save_settings()
		resolution_changed.emit(index)
		settings_changed.emit(current_settings)

func set_fullscreen(enabled: bool):
	current_settings.fullscreen = enabled
	apply_settings()
	save_settings()
	fullscreen_changed.emit(enabled)
	settings_changed.emit(current_settings)

func set_gui_margin(margin: float):
	current_settings.gui_margin = margin
	save_settings()
	apply_gui_margin()
	gui_margin_changed.emit(margin)
	settings_changed.emit(current_settings)

func apply_gui_margin():
	# Find all panels in the scene tree and apply margins
	var panels = get_tree().get_nodes_in_group("gui_panel")
	for panel in panels:
		if panel is Panel:
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

func get_current_settings() -> Dictionary:
	return current_settings.duplicate()

func get_resolutions() -> Array:
	return RESOLUTIONS

# Web communication functions for dynamic resolution updates
func setup_web_communication():
	print("🌐 Setting up web communication for dynamic resolution updates")

	# For web exports, we'll receive calls directly from JavaScript via godot_js_eval

func update_viewport_resolution(width: int, height: int):
	"""Dynamically update Godot's internal rendering resolution to exactly match HTML canvas dimensions"""
	print("🔄 Setting Godot viewport resolution to exactly: ", width, "x", height)

	# Update the main viewport's content scale size (internal rendering resolution)
	var main_viewport = get_viewport()
	if main_viewport:
		# Set the internal rendering resolution to exactly match the reported canvas dimensions
		main_viewport.content_scale_size = Vector2i(width, height)

		# Use DISABLED mode for 1:1 pixel mapping (no scaling)
		main_viewport.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		main_viewport.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE

		# No scale factor needed - direct 1:1 mapping
		main_viewport.content_scale_factor = 1.0

		print("✅ Viewport set to exact dimensions: ", main_viewport.content_scale_size)
		print("✅ Scale mode: DISABLED (1:1 pixel mapping)")
		print("✅ Canvas size matches internal resolution: ", width, "x", height)

		# Update current settings to reflect the actual dimensions
		current_settings.window_base_width = width
		current_settings.window_base_height = height
		current_settings.scale_factor = 1.0

		# Emit signal for other systems that might need to know about resolution changes
		settings_changed.emit({
			"viewport_width": width,
			"viewport_height": height,
			"internal_width": width,
			"internal_height": height,
			"scale_factor": 1.0
		})

		# Force a viewport update
		main_viewport.size_changed.emit()

		return true
	else:
		print("❌ Failed to get main viewport for resolution update")
		return false
