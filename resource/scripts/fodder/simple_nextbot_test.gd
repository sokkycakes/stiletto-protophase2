## Simple NextBot Test
## Attach this script to any Node3D to create a test NextBot
extends Node3D

var test_bot: Node = null

func _ready():
	print("=== NextBot System Test ===")
	
	# Check if NextBotManager is available
	if not _check_nextbot_manager():
		return
	
	# Create a simple test bot
	create_simple_test_bot()
	
	# Run basic tests
	await get_tree().create_timer(1.0).timeout
	run_basic_tests()

func _check_nextbot_manager() -> bool:
	if NextBotManager:
		print("✓ NextBotManager found and loaded")
		return true
	else:
		print("✗ NextBotManager not found!")
		print("  Please add scripts/enemy/nextbot_manager.gd as autoload named 'NextBotManager'")
		print("  Go to Project → Project Settings → Autoload")
		return false

func create_simple_test_bot():
	print("\n=== Creating Test Bot ===")
	
	# Create basic CharacterBody3D
	test_bot = CharacterBody3D.new()
	test_bot.name = "SimpleTestBot"
	add_child(test_bot)
	
	# Add basic collision
	var collision = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	collision.shape = shape
	collision.position = Vector3(0, 0.9, 0)
	test_bot.add_child(collision)
	
	# Add visual representation
	var mesh_instance = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.4
	mesh.height = 1.8
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0, 0.9, 0)
	test_bot.add_child(mesh_instance)
	
	# Add NavigationAgent3D
	var nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	test_bot.add_child(nav_agent)
	
	# Try to add the NextBot script
	var nextbot_script = load("res://scripts/enemy/nextbot_interface.gd")
	if nextbot_script:
		# Create a simple implementation
		var simple_bot_script = GDScript.new()
		simple_bot_script.source_code = """
extends INextBot

func get_locomotion_interface():
	return null  # Simplified for testing

func get_body_interface():
	return null  # Simplified for testing

func get_vision_interface():
	return null  # Simplified for testing

func get_intention_interface():
	return null  # Simplified for testing

func _ready():
	super._ready()
	debug_name = "SimpleTestBot"

	# Register with NextBotManager
	if NextBotManager:
		NextBotManager.register_bot(self)
		print("Simple test bot registered with manager")

	print("Simple test bot initialized: ", debug_name)
"""
		test_bot.set_script(simple_bot_script)
		print("✓ NextBot script applied")
	else:
		print("✗ Could not load NextBot interface script")
	
	print("✓ Simple test bot created at position: ", test_bot.global_position)

func run_basic_tests():
	print("\n=== Running Basic Tests ===")
	
	# Test 1: Check if bot is registered
	if NextBotManager:
		var bot_count = NextBotManager.get_nextbot_count()
		print("Test 1 - Bot Registration: ", bot_count, " bots registered")
		
		if bot_count > 0:
			print("✓ Bot registration working")
		else:
			print("✗ Bot not registered")
	
	# Test 2: Check bot properties
	if test_bot:
		print("Test 2 - Bot Properties:")
		print("  Name: ", test_bot.name)
		print("  Position: ", test_bot.global_position)
		print("  Has NavigationAgent3D: ", test_bot.get_node_or_null("NavigationAgent3D") != null)
		
		if test_bot.has_method("get_debug_name"):
			print("  Debug name: ", test_bot.get_debug_name())
			print("✓ Bot properties accessible")
		else:
			print("✗ Bot methods not available")
	
	# Test 3: Test action system
	test_action_system()
	
	# Test 4: Test manager functions
	test_manager_functions()

func test_action_system():
	print("\nTest 3 - Action System:")
	
	# Try to create a basic action
	var idle_action_script = load("res://scripts/enemy/actions/idle_action.gd")
	if idle_action_script:
		var idle_action = idle_action_script.new()
		if idle_action:
			print("✓ IdleAction created successfully")
			print("  Action name: ", idle_action.get_action_name())
		else:
			print("✗ Failed to create IdleAction")
	else:
		print("✗ IdleAction script not found")

func test_manager_functions():
	print("\nTest 4 - Manager Functions:")
	
	if NextBotManager:
		# Test debug functions
		NextBotManager.set_debug_types(NextBotManager.DebugType.BEHAVIOR)
		print("✓ Debug types set")
		
		# Test bot collection
		var bots = []
		NextBotManager.collect_all_bots(bots)
		print("✓ Bot collection: ", bots.size(), " bots found")
		
		# Test closest bot
		var closest = NextBotManager.get_closest_bot(Vector3.ZERO)
		if closest:
			print("✓ Closest bot found: ", closest.name)
		else:
			print("- No closest bot (expected if only one bot)")
	
	print("\n=== Test Complete ===")
	print("If you see checkmarks (✓) above, the NextBot system is working!")
	print("If you see X marks (✗), check the setup guide for troubleshooting.")

# Input handling for manual testing
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				print("\n--- Manual Test: Bot Status ---")
				get_bot_status()
			KEY_2:
				print("\n--- Manual Test: Move Bot ---")
				test_bot_movement()
			KEY_3:
				print("\n--- Manual Test: Manager Info ---")
				print_manager_info()

func get_bot_status():
	if test_bot:
		print("Bot Name: ", test_bot.name)
		print("Bot Position: ", test_bot.global_position)
		print("Bot Script: ", test_bot.get_script())
		
		if test_bot.has_method("get_debug_name"):
			print("Debug Name: ", test_bot.get_debug_name())
		
		var nav_agent = test_bot.get_node_or_null("NavigationAgent3D")
		if nav_agent:
			print("Navigation Agent: Available")
		else:
			print("Navigation Agent: Missing")
	else:
		print("No test bot found")

func test_bot_movement():
	if test_bot:
		var target = Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		print("Moving bot to: ", target)
		
		var nav_agent = test_bot.get_node_or_null("NavigationAgent3D")
		if nav_agent:
			nav_agent.target_position = target
			print("Navigation target set")
		else:
			print("No NavigationAgent3D found")
	else:
		print("No test bot to move")

func print_manager_info():
	if NextBotManager:
		print("NextBot Manager Status:")
		print("  Bot Count: ", NextBotManager.get_nextbot_count())
		print("  Debug Types: ", NextBotManager.debug_types)
		print("  Update Tickrate: ", NextBotManager.update_tickrate)
		print("  Bots Per Frame: ", NextBotManager.bots_per_frame)
	else:
		print("NextBotManager not available")

func _on_tree_exiting():
	print("Test scene exiting...")
	if test_bot:
		print("Cleaning up test bot")
