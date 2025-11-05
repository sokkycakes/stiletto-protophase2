extends Window

@onready var map_list: ItemList = $MarginContainer/VBoxContainer/MapList
@onready var load_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/LoadButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/HBoxContainer/CancelButton

var maps: Array = []
var selected_map_path: String = ""

func _ready() -> void:
	# Connections
	load_button.pressed.connect(_on_load_button_pressed)
	cancel_button.pressed.connect(queue_free)
	map_list.item_selected.connect(_on_map_item_selected)

	populate_map_list()
	load_button.disabled = true

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		queue_free()

func populate_map_list() -> void:
	map_list.clear()
	maps.clear()
	
	# Dynamically scan the maps folder at runtime
	var dir := DirAccess.open("res://maps")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			# Check if it's a .tscn file (not a directory)
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				var map_name: String = file_name.get_basename()
				var map_path: String = "res://maps/" + file_name
				maps.append({"name": map_name, "path": map_path})
				map_list.add_item(map_name)
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		printerr("Could not open 'res://maps' directory at runtime.")

func _on_map_item_selected(index: int) -> void:
	if index >= 0 and index < maps.size():
		selected_map_path = maps[index]["path"]
		load_button.disabled = false

func _on_load_button_pressed() -> void:
	if not selected_map_path.is_empty():
		get_tree().change_scene_to_file(selected_map_path) 