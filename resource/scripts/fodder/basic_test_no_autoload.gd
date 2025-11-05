## Basic NextBot Test - No Autoload Required
## Use this to test if the basic scripts are working before setting up autoload
extends Node

func _ready():
	print("=== Basic NextBot Script Test (No Autoload) ===")
	test_script_loading()

func test_script_loading():
	print("\n--- Testing Script Loading ---")
	
	# Test 1: Core interface scripts
	print("1. Testing core interfaces...")
	var tests = [
		["Event Responder", "res://scripts/enemy/nextbot_event_responder.gd"],
		["Component Interface", "res://scripts/enemy/nextbot_component_interface.gd"],
		["NextBot Interface", "res://scripts/enemy/nextbot_interface.gd"],
		["NextBot Action", "res://scripts/enemy/nextbot_action.gd"]
	]
	
	for test in tests:
		test_script_load(test[0], test[1])
	
	# Test 2: Component interfaces
	print("\n2. Testing component interfaces...")
	var component_tests = [
		["Locomotion Interface", "res://scripts/enemy/interfaces/locomotion_interface.gd"],
		["Body Interface", "res://scripts/enemy/interfaces/body_interface.gd"],
		["Vision Interface", "res://scripts/enemy/interfaces/vision_interface.gd"],
		["Intention Interface", "res://scripts/enemy/interfaces/intention_interface.gd"]
	]
	
	for test in component_tests:
		test_script_load(test[0], test[1])
	
	# Test 3: Action scripts
	print("\n3. Testing action scripts...")
	var action_tests = [
		["Idle Action", "res://scripts/enemy/actions/idle_action.gd"],
		["Attack Action", "res://scripts/enemy/actions/attack_action.gd"],
		["Patrol Action", "res://scripts/enemy/actions/patrol_action.gd"]
	]
	
	for test in action_tests:
		test_script_load(test[0], test[1])
	
	# Test 4: Path system
	print("\n4. Testing path system...")
	var path_tests = [
		["NextBot Path", "res://scripts/enemy/path/nextbot_path.gd"],
		["Path Follower", "res://scripts/enemy/path/nextbot_path_follower.gd"]
	]
	
	for test in path_tests:
		test_script_load(test[0], test[1])
	
	# Test 5: Manager (without autoload)
	print("\n5. Testing manager script...")
	test_script_load("NextBot Manager", "res://scripts/enemy/nextbot_manager.gd")
	
	# Test 6: Try creating basic objects
	print("\n6. Testing object creation...")
	test_object_creation()
	
	print("\n=== Test Summary ===")
	print("If you see ✓ marks above, the scripts are loading correctly.")
	print("If you see ❌ marks, check the file paths and script syntax.")
	print("\nNext step: Set up NextBotManager as autoload (see CRITICAL_SETUP_FIX.md)")

func test_script_load(name: String, path: String) -> bool:
	if ResourceLoader.exists(path):
		var script = load(path)
		if script:
			print("  ✓ ", name, " - Loaded successfully")
			return true
		else:
			print("  ❌ ", name, " - File exists but failed to load")
			return false
	else:
		print("  ❌ ", name, " - File not found: ", path)
		return false

func test_object_creation():
	# Test creating basic action without autoload
	print("  Testing ActionResult creation...")
	var action_script = load("res://scripts/enemy/nextbot_action.gd")
	if action_script:
		# Try to access the ActionResult inner class
		var action_result = action_script.ActionResult.new(action_script.ActionResultType.CONTINUE)
		if action_result:
			print("    ✓ ActionResult created successfully")
		else:
			print("    ❌ ActionResult creation failed")
	else:
		print("    ❌ Could not load NextBotAction script")
	
	# Test creating event responder
	print("  Testing EventResponder creation...")
	var responder_script = load("res://scripts/enemy/nextbot_event_responder.gd")
	if responder_script:
		var responder = responder_script.new()
		if responder:
			print("    ✓ EventResponder created successfully")
		else:
			print("    ❌ EventResponder creation failed")
	else:
		print("    ❌ Could not load EventResponder script")
	
	# Test creating path
	print("  Testing Path creation...")
	var path_script = load("res://scripts/enemy/path/nextbot_path.gd")
	if path_script:
		var path = path_script.new()
		if path:
			print("    ✓ NextBotPath created successfully")
		else:
			print("    ❌ NextBotPath creation failed")
	else:
		print("    ❌ Could not load NextBotPath script")

# Manual test functions you can call from debugger
func manual_test_manager():
	print("\n--- Manual Manager Test ---")
	var manager_script = load("res://scripts/enemy/nextbot_manager.gd")
	if manager_script:
		var manager = manager_script.new()
		if manager:
			print("✓ Manager instance created")
			print("  Debug types enum: ", manager.DebugType.ALL)
			print("  Bot count: ", manager.get_nextbot_count())
		else:
			print("❌ Manager creation failed")
	else:
		print("❌ Manager script not found")

func manual_test_action():
	print("\n--- Manual Action Test ---")
	var idle_script = load("res://scripts/enemy/actions/idle_action.gd")
	if idle_script:
		var idle_action = idle_script.new()
		if idle_action:
			print("✓ IdleAction created")
			print("  Action name: ", idle_action.get_action_name())
		else:
			print("❌ IdleAction creation failed")
	else:
		print("❌ IdleAction script not found")

# Input handling for manual tests
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				manual_test_manager()
			KEY_2:
				manual_test_action()
			KEY_3:
				test_object_creation()

func _on_tree_exiting():
	print("Basic test complete. Check CRITICAL_SETUP_FIX.md for next steps.")
