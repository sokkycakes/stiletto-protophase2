class_name ShaderPrewarmer
extends Node

## Prewarms shaders by rendering all materials in a hidden viewport
## This prevents stuttering on web exports due to just-in-time shader compilation

signal prewarming_started(total_items: int)
signal prewarming_progress(current: int, total: int, item_name: String)
signal prewarming_complete

# Configuration
@export var items_per_frame: int = 1  ## How many items to render per frame (1-3 recommended for web)
@export var warmup_frames_per_item: int = 2  ## Frames to keep each item visible for shader compilation

# Internal state
var _items_to_prewarm: Array[Dictionary] = []
var _current_index: int = 0
var _warmup_counter: int = 0
var _is_prewarming: bool = false
var _viewport: SubViewport
var _camera: Camera3D
var _current_node: Node3D

func _ready():
	# Create hidden viewport for rendering
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(64, 64)  # Small resolution is fine for shader compilation
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)
	
	# Add camera to viewport
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_camera.position = Vector3(0, 0, 5)
	
	set_process(false)

## Start prewarming with a list of scenes/resources to render
func start_prewarming(scenes: Array[PackedScene], materials: Array[Material] = []) -> void:
	if _is_prewarming:
		push_warning("ShaderPrewarmer: Already prewarming!")
		return
	
	_items_to_prewarm.clear()
	_current_index = 0
	_warmup_counter = 0
	
	# Add scenes to prewarm list
	for scene in scenes:
		if scene:
			_items_to_prewarm.append({
				"type": "scene",
				"resource": scene,
				"name": scene.resource_path.get_file()
			})
	
	# Add standalone materials
	for mat in materials:
		if mat:
			_items_to_prewarm.append({
				"type": "material",
				"resource": mat,
				"name": mat.resource_path.get_file() if mat.resource_path else "Material"
			})
	
	if _items_to_prewarm.is_empty():
		push_warning("ShaderPrewarmer: No items to prewarm!")
		prewarming_complete.emit()
		return
	
	_is_prewarming = true
	prewarming_started.emit(_items_to_prewarm.size())
	set_process(true)

func _process(_delta: float) -> void:
	if not _is_prewarming:
		return
	
	# Keep current item rendered for multiple frames to ensure compilation
	if _warmup_counter < warmup_frames_per_item:
		_warmup_counter += 1
		return
	
	# Clean up previous item
	if _current_node:
		_current_node.queue_free()
		_current_node = null
	
	# Process next batch of items
	var items_processed = 0
	while items_processed < items_per_frame and _current_index < _items_to_prewarm.size():
		var item = _items_to_prewarm[_current_index]
		_prewarm_item(item)
		
		prewarming_progress.emit(_current_index + 1, _items_to_prewarm.size(), item["name"])
		_current_index += 1
		items_processed += 1
	
	# Reset warmup counter for next item
	_warmup_counter = 0
	
	# Check if done
	if _current_index >= _items_to_prewarm.size():
		_finish_prewarming()

func _prewarm_item(item: Dictionary) -> void:
	match item["type"]:
		"scene":
			var packed_scene: PackedScene = item["resource"]
			if packed_scene:
				_current_node = packed_scene.instantiate()
				_viewport.add_child(_current_node)
				
				# Move to camera view
				if _current_node is Node3D:
					_current_node.global_position = Vector3.ZERO
		
		"material":
			var material: Material = item["resource"]
			if material:
				# Create a simple quad to render the material
				var mesh_instance = MeshInstance3D.new()
				var quad_mesh = QuadMesh.new()
				quad_mesh.size = Vector2(2, 2)
				mesh_instance.mesh = quad_mesh
				mesh_instance.material_override = material
				_viewport.add_child(mesh_instance)
				_current_node = mesh_instance

func _finish_prewarming() -> void:
	_is_prewarming = false
	set_process(false)
	
	if _current_node:
		_current_node.queue_free()
		_current_node = null
	
	prewarming_complete.emit()

## Automatically discover and prewarm all materials in a scene
func prewarm_scene_materials(root: Node) -> void:
	var materials: Array[Material] = []
	_collect_materials_recursive(root, materials)
	
	var packed_scenes: Array[PackedScene] = []
	start_prewarming(packed_scenes, materials)

func _collect_materials_recursive(node: Node, materials: Array[Material]) -> void:
	# Check for materials on various node types
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		for i in range(mesh_instance.get_surface_override_material_count()):
			var mat = mesh_instance.get_surface_override_material(i)
			if mat and not mat in materials:
				materials.append(mat)
		
		if mesh_instance.material_override and not mesh_instance.material_override in materials:
			materials.append(mesh_instance.material_override)
		
		# Check mesh materials
		if mesh_instance.mesh:
			for i in range(mesh_instance.mesh.get_surface_count()):
				var mat = mesh_instance.mesh.surface_get_material(i)
				if mat and not mat in materials:
					materials.append(mat)
	
	elif node is GPUParticles3D:
		var particles = node as GPUParticles3D
		if particles.process_material and not particles.process_material in materials:
			materials.append(particles.process_material)
		if particles.draw_pass_1 and particles.draw_pass_1.surface_get_material(0):
			var mat = particles.draw_pass_1.surface_get_material(0)
			if not mat in materials:
				materials.append(mat)
	
	elif node is Sprite3D:
		var sprite = node as Sprite3D
		if sprite.material_override and not sprite.material_override in materials:
			materials.append(sprite.material_override)
	
	# Recurse to children
	for child in node.get_children():
		_collect_materials_recursive(child, materials)

