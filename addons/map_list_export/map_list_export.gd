@tool
extends EditorPlugin

var export_plugin: EditorExportPlugin

func _enter_tree() -> void:
	export_plugin = MapListExportPlugin.new()
	add_export_plugin(export_plugin)

func _exit_tree() -> void:
	if export_plugin:
		remove_export_plugin(export_plugin)

class MapListExportPlugin:
	extends EditorExportPlugin

	func _export_begin(features:PackedStringArray, is_debug:bool, path:String, flags:int) -> void:
		# Gather map data
		var maps:Array = []
		var dir := DirAccess.open("res://maps")
		if dir and dir.list_dir_begin() == OK:
			var fname := dir.get_next()
			while fname != "":
				if not dir.current_is_dir() and fname.ends_with(".tscn"):
					var map_path := "res://maps/%s" % fname
					maps.append({"name": fname.get_basename(), "path": map_path})
					# Ensure the map scene itself is packaged
					_add_resource_file(map_path)
				fname = dir.get_next()
			dir.list_dir_end()
		else:
			push_error("[MapListExport] Could not open res://maps directory. No maps will be exported.")
			return

		# Serialize JSON
		var json_text := JSON.stringify(maps)
		var json_bytes := json_text.to_utf8_buffer()

		# Add JSON to export package
		add_file("res://maps/map_list.json", json_bytes, false)

	func _add_resource_file(res_path:String) -> void:
		if !FileAccess.file_exists(res_path):
			push_warning("[MapListExport] Resource '%s' does not exist." % res_path)
			return
		var bytes := FileAccess.get_file_as_bytes(res_path)
		if bytes.size() > 0:
			add_file(res_path, bytes, false) 