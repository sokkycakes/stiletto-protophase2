extends Control

signal mouse_sensitivity_changed(value: float)

@onready var back_button = $VBoxContainer/BackButton
@onready var mouse_sensitivity_control = $VBoxContainer/MouseSensitivityControl

var current_sensitivity: float = 1.0

func _ready():
	z_index = 128  # Set to same z_index as pause menu
	mouse_filter = Control.MOUSE_FILTER_STOP  # Block mouse input to nodes behind this one
	back_button.pressed.connect(_on_back_pressed)
	
	# Connect to the mouse sensitivity control's signal
	if mouse_sensitivity_control:
		mouse_sensitivity_control.value_changed.connect(_on_mouse_sensitivity_changed)
	
	hide()

func _on_back_pressed():
	hide()
	get_viewport().set_input_as_handled()

func _on_mouse_sensitivity_changed(value: float):
	current_sensitivity = value
	mouse_sensitivity_changed.emit(value) 
