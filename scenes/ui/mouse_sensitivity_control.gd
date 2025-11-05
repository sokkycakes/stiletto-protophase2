extends HBoxContainer

signal value_changed(value: float)

@onready var slider = $HSlider
@onready var line_edit = $LineEdit

var current_value: float = 1.0

func _ready():
	slider.value_changed.connect(_on_slider_value_changed)
	line_edit.text_submitted.connect(_on_text_submitted)
	line_edit.focus_exited.connect(_on_text_focus_exited)

func _on_slider_value_changed(value: float):
	current_value = value
	line_edit.text = "%.1f" % value
	value_changed.emit(value)

func _on_text_submitted(new_text: String):
	_validate_and_set_text(new_text)

func _on_text_focus_exited():
	_validate_and_set_text(line_edit.text)

func _validate_and_set_text(text: String):
	var value = text.to_float()
	if value >= slider.min_value and value <= slider.max_value:
		slider.value = value
	else:
		# Reset to current value if invalid
		line_edit.text = "%.1f" % current_value 
