extends CanvasLayer
class_name ControllerVisualizer

# Constants for how many axes and buttons we want to visualise.
const AXIS_COUNT := 8  # Standard joysticks expose up to 8 analogue axes.
const BUTTON_COUNT := 20  # Common gamepads expose up to 20 buttons.

# Number of button labels per row inside each device panel.
@export var button_columns := 4
# How often (in seconds) to poll and refresh the UI.
@export var refresh_interval := 0.05

var _time_passed := 0.0
var _device_panels: Dictionary = {}
var _root_container: VBoxContainer

func _ready() -> void:
	name = "ControllerVisualizer"
	# Create the root UI container that will hold individual device panels.
	_root_container = VBoxContainer.new()
	_root_container.name = "RootContainer"
	_root_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root_container.set_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_KEEP_SIZE, 10)
	add_child(_root_container)

	set_process(true)
	_sync_device_list()  # Initial population

func _process(delta: float) -> void:
	_time_passed += delta
	if _time_passed < refresh_interval:
		return
	_time_passed = 0.0

	_sync_device_list()
	_update_device_panels()

func _sync_device_list() -> void:
	# Detect newly connected / disconnected gamepads and update UI accordingly.
	var connected: Array = Input.get_connected_joypads()

	# Add new devices.
	for device_id in connected:
		if not _device_panels.has(device_id):
			var panel := _create_device_panel(device_id)
			_device_panels[device_id] = panel
			_root_container.add_child(panel)

	# Remove disconnected devices.
	for stored_id in _device_panels.keys():
		if stored_id not in connected:
			_device_panels[stored_id].queue_free()
			_device_panels.erase(stored_id)

func _create_device_panel(device_id: int) -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.name = "Device_%d" % device_id
	panel.custom_minimum_size = Vector2(380, 0)
	panel.add_theme_stylebox_override("panel", StyleBoxFlat.new())
	panel.add_theme_color_override("panel_color", Color(0, 0, 0, 0.35))
	panel.add_theme_constant_override("separation", 4)

	# Title label with device name.
	var title := Label.new()
	title.text = "%s (ID %d)" % [Input.get_joy_name(device_id), device_id]
	title.add_theme_font_size_override("font_size", 16)
	panel.add_child(title)

	# Axis readouts.
	var axis_container := GridContainer.new()
	axis_container.columns = 2
	axis_container.name = "AxisContainer"
	panel.add_child(axis_container)

	for axis_index in AXIS_COUNT:
		var axis_label := Label.new()
		axis_label.name = "Axis_%d" % axis_index
		axis_container.add_child(axis_label)

	# Button readouts.
	var btn_container := GridContainer.new()
	btn_container.columns = button_columns
	btn_container.name = "ButtonContainer"
	panel.add_child(btn_container)

	for btn_index in BUTTON_COUNT:
		var btn_label := Label.new()
		btn_label.name = "Btn_%d" % btn_index
		btn_container.add_child(btn_label)

	return panel

func _update_device_panels() -> void:
	for device_id in _device_panels.keys():
		var panel: VBoxContainer = _device_panels[device_id]
		var axis_container: GridContainer = panel.get_node("AxisContainer")
		for axis_index in AXIS_COUNT:
			var axis_label: Label = axis_container.get_node("Axis_%d" % axis_index)
			var axis_val := Input.get_joy_axis(device_id, axis_index)
			axis_label.text = "Axis %-2d: %.3f" % [axis_index, axis_val]

		var btn_container: GridContainer = panel.get_node("ButtonContainer")
		for btn_index in BUTTON_COUNT:
			var btn_label: Label = btn_container.get_node("Btn_%d" % btn_index)
			var pressed := Input.is_joy_button_pressed(device_id, btn_index)
			btn_label.text = "Btn %-2d: %s" % [btn_index, "ON" if pressed else "OFF"]
			btn_label.add_theme_color_override("font_color", Color.YELLOW if pressed else Color.WHITE) 
