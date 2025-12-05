tool
extends EditorScript

## Editor script to generate map thumbnails using the editor's preview system
## Run this script from the Script tab to generate thumbnails for all maps in res://maps/mp/

# Where to place thumbnails
const OUT_DIR := "res://assets/map_thumbs"
const MAP_DIR := "res://maps/mp"

# Track pending previews
var pending_count := 0
var completed_count := 0

func _run() -> void:
	print("[Map Thumbnail Generator] Starting...")
	
	var dir := DirAccess.open(MAP_DIR)
	if not dir:
		push_error("[Map Thumbnail Generator] Cannot open directory: %s" % MAP_DIR)
		return
	
	# Ensure output folder exists
	var out_dir_access := DirAccess.open("res://assets")
	if not out_dir_access:
		push_error("[Map Thumbnail Generator] Cannot access res://assets directory")
		return
	
	if not DirAccess.dir_exists_absolute(OUT_DIR):
		var error = DirAccess.make_dir_recursive_absolute(OUT_DIR)
		if error != OK:
			push_error("[Map Thumbnail Generator] Failed to create output directory: %s (error: %d)" % [OUT_DIR, error])
			return
		print("[Map Thumbnail Generator] Created output directory: %s" % OUT_DIR)
	
	# Get preview singleton
	var preview := EditorResourcePreview.get_singleton()
	if not preview:
		push_error("[Map Thumbnail Generator] EditorResourcePreview not available")
		return
	
	# Find all .tscn files
	var files := dir.get_files()
	var scene_files: Array[String] = []
	
	for file in files:
		if file.ends_with(".tscn"):
			scene_files.append(file)
	
	if scene_files.is_empty():
		print("[Map Thumbnail Generator] No .tscn files found in %s" % MAP_DIR)
		return
	
	pending_count = scene_files.size()
	completed_count = 0
	
	print("[Map Thumbnail Generator] Found %d map files. Generating thumbnails..." % pending_count)
	
	# Queue preview generation for each scene
	for file in scene_files:
		var full_path := "%s/%s" % [MAP_DIR, file]
		var scene_resource := load(full_path)
		
		if not scene_resource:
			print("[Map Thumbnail Generator] Warning: Failed to load %s" % full_path)
			completed_count += 1
			continue
		
		# Queue the preview generation
		preview.queue_resource_preview(
			scene_resource,           # resource
			self,                     # callback object
			"_on_preview_ready",      # method name
			[file]                    # userdata (scene filename)
		)
	
	# Wait for all previews to complete
	# Note: This is a simple approach - in practice, previews are async
	# The callbacks will handle saving, but we can't easily wait here
	print("[Map Thumbnail Generator] Queued %d previews. Check output for completion messages." % pending_count)

func _on_preview_ready(res_path: String, tex: Texture2D, userdata: Array) -> void:
	# Called once the thumbnail is generated
	var file := userdata[0] as String
	completed_count += 1
	
	if not tex:
		print("[Map Thumbnail Generator] Warning: No thumbnail generated for %s" % file)
		if completed_count >= pending_count:
			print("[Map Thumbnail Generator] Completed. Generated %d/%d thumbnails." % [completed_count, pending_count])
		return
	
	# Get the image from the texture
	var img := tex.get_image()
	if not img:
		print("[Map Thumbnail Generator] Warning: Failed to get image from texture for %s" % file)
		if completed_count >= pending_count:
			print("[Map Thumbnail Generator] Completed. Generated %d/%d thumbnails." % [completed_count, pending_count])
		return
	
	# Generate output filename (use the scene filename without extension)
	var base_name := file.get_basename()
	var out_path := "%s/%s.png" % [OUT_DIR, base_name]
	
	# Save the image
	var error := img.save_png(out_path)
	if error != OK:
		push_error("[Map Thumbnail Generator] Failed to save thumbnail to %s (error: %d)" % [out_path, error])
	else:
		print("[Map Thumbnail Generator] ✓ Saved thumbnail: %s" % out_path)
	
	# Check if all previews are done
	if completed_count >= pending_count:
		print("[Map Thumbnail Generator] ✓ All thumbnails generated! (%d/%d)" % [completed_count, pending_count])

