@tool
extends Node

@export var generate_map_list: bool = false:
	set(value):
		if value:
			_generate_map_list()

func _generate_map_list() -> void:
	var maps: Array = []
	var dir := DirAccess.open("res://maps")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".tscn"):
				var map_name: String = file_name.get_basename()
				var map_path: String = "res://maps/%s" % file_name
				maps.append({"name": map_name, "path": map_path})
			file_name = dir.get_next()
	else:
		printerr("Could not open 'res://maps' directory.")
		return

	var file := FileAccess.open("res://maps/map_list.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(maps, "\t"))
		print("Successfully generated map list at res://maps/map_list.json")
	else:
		printerr("Failed to write to res://maps/map_list.json") 