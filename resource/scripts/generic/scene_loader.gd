extends Node

## SceneLoader is a singleton that replaces get_tree().change_scene* helpers so that we can display
## a loading screen while the next scene is streamed in using ResourceLoader.load_interactive().
## Add this script to the Autoload list (Project Settings ▶ Autoload) with the name `SceneLoader`
## to make it globally accessible via `SceneLoader.change_scene(path)`.

# A user-designed loading screen to be instantiated. Configure this in the Inspector (autoload)
# or override it from code with `SceneLoader.loading_screen_scene = preload("res://path.tscn")`
@export var loading_screen_scene: PackedScene

# Enable shader prewarming on web exports (prevents stuttering)
@export var enable_shader_prewarming: bool = true

# Instance of the active loading screen.
var _loading_instance: Node = null
# If the instance (or a child) has a ProgressBar named "ProgressBar", we update it automatically.
var _loading_progress_bar: ProgressBar = null
var _loading_status_label: Label = null

# Internal state for the interactive loader.
var _loading_path: String = ""
var _progress_array: Array = []

# Shader prewarming
var _prewarmer: ShaderPrewarmer = null
var _scene_to_prewarm: PackedScene = null
var _is_prewarming: bool = false

func _ready():
	# The SceneLoader should not be visible in-game. It only exists to manage loading.
	set_process(false)
	
	# Create prewarmer
	_prewarmer = ShaderPrewarmer.new()
	add_child(_prewarmer)
	_prewarmer.prewarming_progress.connect(_on_prewarming_progress)
	_prewarmer.prewarming_complete.connect(_on_prewarming_complete)

# Public API -----------------------------------------------------------------

## Call this instead of `get_tree().change_scene_to_file(path)`.
## The method takes care of opening a loading screen, streaming in the scene
## in small chunks each frame and finally switching to it.
func change_scene(path: String) -> void:
	# Bail out if a load is already running – you can expand this to queue requests.
	if _loading_path != "":
		push_error("SceneLoader: A scene is already being loaded!")
		return

	_show_loading_ui()

	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		push_error("SceneLoader: Could not start loading %s (error %d)" % [path, err])
		_hide_loading_ui()
		return

	_loading_path = path

	# Start polling in _process.
	set_process(true)

# Internal helpers ------------------------------------------------------------

func _process(_delta: float) -> void:
	if _loading_path == "":
		return

	var status := ResourceLoader.load_threaded_get_status(_loading_path, _progress_array)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var p: float = 0.0
		if _progress_array.size() > 0:
			p = float(_progress_array[0])
		# Automatic update if our instance exposes interface.
		if _loading_progress_bar:
			_loading_progress_bar.value = p
		if _loading_instance and _loading_instance.has_method("update_progress"):
			_loading_instance.call("update_progress", p)
		if _loading_instance and _loading_instance.has_method("set_status_text"):
			_loading_instance.call("set_status_text", "Loading scene...")
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		var next_scene_packed := ResourceLoader.load_threaded_get(_loading_path)
		_finish_loading(next_scene_packed)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("SceneLoader: Loading failed")
		_hide_loading_ui()
		_loading_path = ""
		set_process(false)
	# else: Unknown status – ignore

func _finish_loading(packed_scene: PackedScene) -> void:
	_loading_path = ""
	set_process(false)
	
	# On web, prewarm shaders before switching scene
	if OS.get_name() == "Web" and enable_shader_prewarming:
		_scene_to_prewarm = packed_scene
		_is_prewarming = true
		
		# Update loading UI text
		if _loading_instance and _loading_instance.has_method("set_status_text"):
			_loading_instance.call("set_status_text", "Compiling shaders...")
		
		# Instantiate scene temporarily to collect materials
		var temp_instance = packed_scene.instantiate()
		var materials: Array[Material] = []
		_collect_scene_materials(temp_instance, materials)
		temp_instance.queue_free()
		
		print("ShaderPrewarmer: Found %d materials to prewarm" % materials.size())
		
		# Start prewarming
		_prewarmer.start_prewarming([], materials)
	else:
		# Desktop: switch immediately
		_hide_loading_ui()
		get_tree().change_scene_to_packed(packed_scene)

func _show_loading_ui() -> void:
	if loading_screen_scene:
		_loading_instance = loading_screen_scene.instantiate()
	else:
		# Fallback to simple overlay if no custom scene provided.
		_loading_instance = _create_fallback_overlay()

	get_tree().get_root().add_child(_loading_instance)
	get_tree().get_root().move_child(_loading_instance, 0) # Ensure on top

	# Try to locate a ProgressBar to update automatically.
	_loading_progress_bar = _loading_instance.get_node_or_null("**/ProgressBar")
	_loading_status_label = _loading_instance.get_node_or_null("**/StatusLabel")

func _hide_loading_ui() -> void:
	if _loading_instance and _loading_instance.is_inside_tree():
		_loading_instance.queue_free()
	_loading_instance = null
	_loading_progress_bar = null
	_loading_status_label = null

func _create_fallback_overlay() -> Control:
	var overlay := ColorRect.new()
	overlay.name = "__SceneLoaderOverlay"
	overlay.color = Color.BLACK
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_FILL
	overlay.size_flags_vertical = Control.SIZE_EXPAND | Control.SIZE_FILL
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0

	var bar := ProgressBar.new()
	bar.name = "ProgressBar"
	bar.anchor_left = 0.25
	bar.anchor_right = 0.75
	bar.anchor_top = 0.45
	bar.anchor_bottom = 0.55
	bar.max_value = 1.0
	bar.value = 0.0
	overlay.add_child(bar)

	var label := Label.new()
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.6
	label.anchor_bottom = 0.6
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "Loading…"
	overlay.add_child(label)

	return overlay

# Shader prewarming callbacks -------------------------------------------------

func _on_prewarming_progress(current: int, total: int, item_name: String) -> void:
	var progress = float(current) / float(total)
	if _loading_progress_bar:
		_loading_progress_bar.value = progress
	if _loading_instance and _loading_instance.has_method("update_progress"):
		_loading_instance.call("update_progress", progress)
	if _loading_instance and _loading_instance.has_method("set_item_text"):
		_loading_instance.call("set_item_text", "Compiling: %s" % item_name)

func _on_prewarming_complete() -> void:
	print("ShaderPrewarmer: Prewarming complete!")
	_is_prewarming = false
	_hide_loading_ui()
	if _scene_to_prewarm:
		get_tree().change_scene_to_packed(_scene_to_prewarm)
		_scene_to_prewarm = null

# Material collection helper --------------------------------------------------

func _collect_scene_materials(node: Node, materials: Array[Material]) -> void:
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		for i in range(mesh_instance.get_surface_override_material_count()):
			var mat = mesh_instance.get_surface_override_material(i)
			if mat and not mat in materials:
				materials.append(mat)
		if mesh_instance.material_override and not mesh_instance.material_override in materials:
			materials.append(mesh_instance.material_override)
		if mesh_instance.mesh:
			for i in range(mesh_instance.mesh.get_surface_count()):
				var mat = mesh_instance.mesh.surface_get_material(i)
				if mat and not mat in materials:
					materials.append(mat)
	
	elif node is GPUParticles3D:
		var particles = node as GPUParticles3D
		if particles.process_material:
			if particles.process_material is ShaderMaterial:
				var shader_mat = particles.process_material as ShaderMaterial
				if not shader_mat in materials:
					materials.append(shader_mat)
	
	elif node is Sprite3D:
		var sprite = node as Sprite3D
		if sprite.material_override and not sprite.material_override in materials:
			materials.append(sprite.material_override)
	
	for child in node.get_children():
		_collect_scene_materials(child, materials)

