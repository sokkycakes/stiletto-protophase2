extends Control
class_name CharacterSelect

signal character_selected(character_id: String)

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var character_list: VBoxContainer = $Panel/VBoxContainer/CharacterList
@onready var confirm_button: Button = $Panel/VBoxContainer/Buttons/ConfirmButton
@onready var skip_button: Button = $Panel/VBoxContainer/Buttons/SkipButton

var characters: Array = []
var selected_character_id: String = ""

func _ready():
	# Make sure we're on top of everything
	move_child(panel, -1)
	
	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Connect buttons
	confirm_button.pressed.connect(_on_confirm_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	
	# Create character buttons
	if characters.size() > 0:
		_create_character_buttons()
	
	# Set initial focus
	if character_list.get_child_count() > 0:
		var first_button = character_list.get_child(0) as Button
		if first_button:
			first_button.grab_focus()
	
	# Enable/disable confirm button based on selection
	confirm_button.disabled = selected_character_id.is_empty()

func set_characters(new_characters: Array):
	characters = new_characters
	
	# If UI already created, recreate buttons
	if is_inside_tree():
		_create_character_buttons()

func _create_character_buttons():
	# Clear existing buttons
	for child in character_list.get_children():
		child.queue_free()
	
	# Create a button for each character
	for char_def in characters:
		var button = Button.new()
		
		# Get display name and id from the character
		var display_name = ""
		var char_id = ""
		
		# Check if it's a CharacterDefinition resource
		if char_def.has_method("is_valid"):
			# It's a proper CharacterDefinition resource
			display_name = char_def.display_name
			char_id = char_def.id
		else:
			# It might be a Dictionary or other structure
			print("[CharacterSelect] Warning: Invalid character definition format")
			continue
		
		button.text = display_name
		button.custom_minimum_size = Vector2(0, 50)
		button.pressed.connect(_on_character_button_pressed.bind(char_id))
		
		# Add description if available
		if char_def.description and not char_def.description.is_empty():
			button.tooltip_text = char_def.description
		
		character_list.add_child(button)

func _on_character_button_pressed(character_id: String):
	selected_character_id = character_id
	confirm_button.disabled = false
	
	# Visual feedback - highlight selected button
	for child in character_list.get_children():
		if child is Button:
			var btn = child as Button
			# Simple selection - just brighten the pressed button
			btn.modulate = Color(1.2, 1.2, 1.0)  # Slightly brighter

func _on_confirm_pressed():
	if not selected_character_id.is_empty():
		character_selected.emit(selected_character_id)
		_close_ui()
	else:
		print("[CharacterSelect] No character selected!")

func _on_skip_pressed():
	# Auto-select first character if available
	if characters.size() > 0:
		var first_char = characters[0]
		if first_char.has_method("id"):
			selected_character_id = first_char.id
		character_selected.emit(selected_character_id)
	_close_ui()

func _close_ui():
	queue_free()
	# Return to game mouse mode
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# If window is closed without selection, use first character
		_on_skip_pressed()
