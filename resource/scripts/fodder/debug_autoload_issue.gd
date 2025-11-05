## Debug Autoload Issue
## Use this to find out why NextBotManager won't load as autoload
extends Node

func _ready():
	print("=== Debugging NextBot Autoload Issue ===")
	test_manager_scripts()

func test_manager_scripts():
	print("\n1. Testing NextBotManager script loading...")
	
	# Test original manager
	var original_path = "res://scripts/enemy/nextbot_manager.gd"
	print("Testing original manager: ", original_path)
	
	if ResourceLoader.exists(original_path):
		print("  ✓ File exists")
		
		var script = load(original_path)
		if script:
			print("  ✓ Script loads successfully")
			
			# Try to create instance
			var instance = script.new()
			if instance:
				print("  ✓ Instance created successfully")
				print("  ✓ Original NextBotManager should work as autoload")
				
				# Test some methods
				print("  Testing methods...")
				print("    get_nextbot_count(): ", instance.get_nextbot_count())
				print("    DebugType.ALL: ", instance.DebugType.ALL)
				
				instance.queue_free()
			else:
				print("  ❌ Failed to create instance - this is the problem!")
		else:
			print("  ❌ Failed to load script - parsing error in nextbot_manager.gd")
			print("  This is why autoload fails!")
	else:
		print("  ❌ File doesn't exist")
	
	print("\n2. Testing simple manager...")
	
	# Test simple manager
	var simple_path = "res://scripts/enemy/nextbot_manager_simple.gd"
	print("Testing simple manager: ", simple_path)
	
	if ResourceLoader.exists(simple_path):
		print("  ✓ File exists")
		
		var script = load(simple_path)
		if script:
			print("  ✓ Script loads successfully")
			
			var instance = script.new()
			if instance:
				print("  ✓ Instance created successfully")
				print("  ✓ Simple NextBotManager should work as autoload")
				
				# Test some methods
				print("  Testing methods...")
				print("    get_nextbot_count(): ", instance.get_nextbot_count())
				print("    DebugType.ALL: ", instance.DebugType.ALL)
				
				instance.queue_free()
			else:
				print("  ❌ Failed to create instance")
		else:
			print("  ❌ Failed to load script")
	else:
		print("  ❌ File doesn't exist")
	
	print("\n3. Testing dependencies...")
	test_dependencies()
	
	print("\n=== Recommendations ===")
	print("If original manager failed to load:")
	print("1. Use the simple manager as autoload instead")
	print("2. Path: scripts/enemy/nextbot_manager_simple.gd")
	print("3. Name: NextBotManager")
	print("4. This will get the system working")

func test_dependencies():
	var dependencies = [
		"res://scripts/enemy/nextbot_event_responder.gd",
		"res://scripts/enemy/nextbot_component_interface.gd",
		"res://scripts/enemy/nextbot_interface.gd"
	]
	
	for dep in dependencies:
		print("  Testing dependency: ", dep)
		if ResourceLoader.exists(dep):
			var script = load(dep)
			if script:
				print("    ✓ Loads OK")
			else:
				print("    ❌ Parse error - this could be causing the issue")
		else:
			print("    ❌ File missing")

# Manual test functions
func test_current_autoload():
	print("\n--- Testing Current Autoload ---")
	
	# Check if NextBotManager exists in autoload
	var autoloads = ProjectSettings.get_setting("autoload", {})
	print("Current autoloads: ", autoloads)
	
	# Try to access NextBotManager
	if has_node("/root/NextBotManager"):
		print("✓ NextBotManager found in scene tree")
		var manager = get_node("/root/NextBotManager")
		print("  Type: ", manager.get_class())
		print("  Script: ", manager.get_script())
	else:
		print("❌ NextBotManager not found in scene tree")
	
	# Try global access
	var globals = Engine.get_singleton_list()
	print("Available singletons: ", globals)

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				test_current_autoload()
			KEY_2:
				test_manager_scripts()

func _on_tree_exiting():
	print("Debug complete. Check console output for issues.")
