@tool
extends EditorScript

# Helper script to create example enemy scenes
# Run this from Editor → Tools → Execute Script to create example scenes

func _run():
	print("=== EnemySceneBuilder Starting ===")
	print("Working directory: ", OS.get_executable_path().get_base_dir())
	
	var success_count = 0
	
	if create_knight_scene():
		success_count += 1
	
	if create_archer_scene():
		success_count += 1
	
	print("=== EnemySceneBuilder Complete ===")
	print("Successfully created ", success_count, "/2 scenes")
	print("Check scenes/enemies/ folder for .tscn files")

func create_knight_scene() -> bool:
	print("--- Creating Knight Scene ---")
	
	var scene = PackedScene.new()
	print("✓ PackedScene created")
	
	# Root node
	var knight = CharacterBody3D.new()
	knight.name = "KnightV2"
	print("✓ CharacterBody3D created: ", knight.name)
	
	# Attach the script
	var script_path = "res://scripts/enemy/KnightV2.gd"
	print("Loading script: ", script_path)
	var script = load(script_path)
	if script == null:
		print("✗ ERROR: Failed to load script at ", script_path)
		return false
	knight.set_script(script)
	print("✓ Script attached")
	
	# Add mesh (using a simple capsule for now)
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.5
	capsule_mesh.height = 1.8
	mesh_instance.mesh = capsule_mesh
	knight.add_child(mesh_instance, true)
	mesh_instance.owner = knight
	print("✓ Mesh added")
	
	# Add collision
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule_shape = CapsuleShape3D.new()
	capsule_shape.radius = 0.5
	capsule_shape.height = 1.8
	collision.shape = capsule_shape
	knight.add_child(collision, true)
	collision.owner = knight
	print("✓ Collision added")
	
	# Add navigation agent
	var nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	knight.add_child(nav_agent, true)
	nav_agent.owner = knight
	print("✓ Navigation agent added")
	
	# Add debug label
	var label = Label3D.new()
	label.name = "StateLabel"
	label.text = "IDLE"
	label.position = Vector3(0, 2.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	knight.add_child(label, true)
	label.owner = knight
	print("✓ Debug label added")
	
	# Add to groups
	knight.add_to_group("enemies")
	print("✓ Added to 'enemies' group")
	
	# Save scene
	var save_path = "res://scenes/enemies/KnightV2.tscn"
	print("Attempting to save to: ", save_path)
	
	ensure_directory_exists("res://scenes/enemies/")
	print("✓ Directory ensured")
	
	var pack_result = scene.pack(knight)
	if pack_result != OK:
		print("✗ ERROR: Failed to pack scene. Error code: ", pack_result)
		return false
	print("✓ Scene packed successfully")
	
	var save_result = ResourceSaver.save(scene, save_path)
	if save_result != OK:
		print("✗ ERROR: Failed to save scene. Error code: ", save_result)
		return false
	
	print("✓ Knight scene created successfully: ", save_path)
	return true

func create_archer_scene() -> bool:
	print("--- Creating Archer Scene ---")
	
	var scene = PackedScene.new()
	print("✓ PackedScene created")
	
	# Root node
	var archer = CharacterBody3D.new()
	archer.name = "ArcherEnemy"
	print("✓ CharacterBody3D created: ", archer.name)
	
	# Attach the script
	var script_path = "res://scripts/enemy/ArcherEnemy.gd"
	print("Loading script: ", script_path)
	var script = load(script_path)
	if script == null:
		print("✗ ERROR: Failed to load script at ", script_path)
		return false
	archer.set_script(script)
	print("✓ Script attached")
	
	# Add mesh (using a cylinder to differentiate from knight)
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.top_radius = 0.3
	cylinder_mesh.bottom_radius = 0.5
	cylinder_mesh.height = 1.8
	mesh_instance.mesh = cylinder_mesh
	archer.add_child(mesh_instance, true)
	mesh_instance.owner = archer
	print("✓ Mesh added")
	
	# Add collision
	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var capsule_shape = CapsuleShape3D.new()
	capsule_shape.radius = 0.4
	capsule_shape.height = 1.8
	collision.shape = capsule_shape
	archer.add_child(collision, true)
	collision.owner = archer
	print("✓ Collision added")
	
	# Add navigation agent
	var nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	archer.add_child(nav_agent, true)
	nav_agent.owner = archer
	print("✓ Navigation agent added")
	
	# Add debug label
	var label = Label3D.new()
	label.name = "StateLabel"
	label.text = "IDLE"
	label.position = Vector3(0, 2.2, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	archer.add_child(label, true)
	label.owner = archer
	print("✓ Debug label added")
	
	# Add to groups
	archer.add_to_group("enemies")
	print("✓ Added to 'enemies' group")
	
	# Save scene
	var save_path = "res://scenes/enemies/ArcherEnemy.tscn"
	print("Attempting to save to: ", save_path)
	
	ensure_directory_exists("res://scenes/enemies/")
	print("✓ Directory ensured")
	
	var pack_result = scene.pack(archer)
	if pack_result != OK:
		print("✗ ERROR: Failed to pack scene. Error code: ", pack_result)
		return false
	print("✓ Scene packed successfully")
	
	var save_result = ResourceSaver.save(scene, save_path)
	if save_result != OK:
		print("✗ ERROR: Failed to save scene. Error code: ", save_result)
		return false
	
	print("✓ Archer scene created successfully: ", save_path)
	return true

func ensure_directory_exists(path: String):
	print("Checking directory: ", path)
	var dir = DirAccess.open("res://")
	if dir == null:
		print("✗ ERROR: Failed to open res:// directory")
		return
	
	if not dir.dir_exists(path):
		print("Directory doesn't exist, creating: ", path)
		var result = dir.make_dir_recursive(path)
		if result != OK:
			print("✗ ERROR: Failed to create directory. Error code: ", result)
		else:
			print("✓ Directory created successfully")
	else:
		print("✓ Directory already exists")
