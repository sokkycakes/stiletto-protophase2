extends Control

## Loading screen with shader compilation progress tracking
## Compatible with SceneLoader's shader prewarming system

@onready var progress_bar: ProgressBar = $MarginContainer/VBoxContainer/ProgressBar
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel
@onready var item_label: Label = $MarginContainer/VBoxContainer/ItemLabel
@onready var percentage_label: Label = $MarginContainer/VBoxContainer/PercentageLabel

func _ready():
	# Ensure we're on top and visible
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func update_progress(value: float) -> void:
	if progress_bar:
		progress_bar.value = value * 100.0
	if percentage_label:
		percentage_label.text = "%d%%" % int(value * 100.0)

func set_status_text(text: String) -> void:
	if status_label:
		status_label.text = text

func set_item_text(text: String) -> void:
	if item_label:
		item_label.text = text

