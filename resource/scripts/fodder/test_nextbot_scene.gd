## Test NextBot Scene Creator
## Use this script to create a test NextBot programmatically
extends Node3D

func _ready():
	create_test_nextbot()

func create_test_nextbot():
	print("Creating test NextBot...")
	
	# Create the main bot node
	var bot = CharacterBody3D.new()
	bot.name = "TestNextBot"
	bot.set_script(load("res://scripts/enemy/enhanced_nextbot.gd"))
	add_child(bot)
	
	# Add NavigationAgent3D
	var nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	nav_agent.path_max_distance = 3.0
	bot.add_child(nav_agent)
	
	# Add CollisionShape3D
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.position = Vector3(0, 0.9, 0)
	var capsule_shape = CapsuleShape3D.new()
	capsule_shape.radius = 0.4
	capsule_shape.height = 1.8
	collision_shape.shape = capsule_shape
	bot.add_child(collision_shape)
	
	# Add MeshInstance3D for visualization
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	mesh_instance.position = Vector3(0, 0.9, 0)
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.4
	capsule_mesh.height = 1.8
	mesh_instance.mesh = capsule_mesh
	bot.add_child(mesh_instance)
	
	# Add AnimationPlayer
	var anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	bot.add_child(anim_player)
	
	# Create Components container
	var components = Node.new()
	components.name = "Components"
	bot.add_child(components)
	
	# Add Enhanced Components (if they exist)
	_add_component_if_exists(components, "EnhancedLocomotionComponent", "res://scripts/enemy/components/enhanced_locomotion_component.gd")
	_add_component_if_exists(components, "EnhancedBodyComponent", "res://scripts/enemy/components/enhanced_body_component.gd")
	_add_component_if_exists(components, "EnhancedVisionComponent", "res://scripts/enemy/components/enhanced_vision_component.gd")
	_add_component_if_exists(components, "EnhancedIntentionComponent", "res://scripts/enemy/components/enhanced_intention_component.gd")
	
	# Add Legacy Components (for compatibility)
	_add_component_if_exists(components, "LocomotionComponent", "res://scripts/enemy/components/locomotion_component.gd")
	_add_component_if_exists(components, "BodyComponent", "res://scripts/enemy/components/body_component.gd")
	_add_component_if_exists(components, "VisionComponent", "res://scripts/enemy/components/vision_component.gd")
	_add_component_if_exists(components, "IntentionComponent", "res://scripts/enemy/components/intention_component.gd")
	
	# Create RayCasts container
	var raycasts = Node3D.new()
	raycasts.name = "RayCasts"
	bot.add_child(raycasts)
	
	# Add Vision RayCast
	var vision_raycast = RayCast3D.new()
	vision_raycast.name = "VisionRayCast"
	vision_raycast.position = Vector3(0, 1.5, 0)
	vision_raycast.target_position = Vector3(0, 0, -20)
	raycasts.add_child(vision_raycast)
	
	print("Test NextBot created successfully!")
	print("Bot position: ", bot.global_position)
	
	# Set some basic properties if the script loaded correctly
	if bot.has_method("set_team"):
		bot.set_team(1)
	
	# Enable debug output
	if NextBotManager:
		NextBotManager.set_debug_types(NextBotManager.DebugType.ALL)
		print("Debug output enabled")
	else:
		print("WARNING: NextBotManager not found! Make sure it's set up as autoload.")

func _add_component_if_exists(parent: Node, component_name: String, script_path: String):
	if ResourceLoader.exists(script_path):
		var component = Node.new()
		component.name = component_name
		var script = load(script_path)
		if script:
			component.set_script(script)
			parent.add_child(component)
			print("Added component: ", component_name)
		else:
			print("Failed to load script: ", script_path)
	else:
		print("Component script not found: ", script_path)

# Test functions you can call from the console or other scripts
func test_bot_movement():
	var bot = get_node_or_null("TestNextBot")
	if bot and bot.has_method("move_toward"):
		var target_pos = Vector3(5, 0, 5)
		bot.move_toward(target_pos)
		print("Bot moving to: ", target_pos)
	else:
		print("Bot not found or doesn't have move_toward method")

func test_bot_animation():
	var bot = get_node_or_null("TestNextBot")
	if bot and bot.has_method("play_animation"):
		bot.play_animation("idle")
		print("Playing idle animation")
	else:
		print("Bot not found or doesn't have play_animation method")

func get_bot_status():
	var bot = get_node_or_null("TestNextBot")
	if bot:
		print("=== Bot Status ===")
		print("Position: ", bot.global_position)
		print("Has locomotion: ", bot.get_locomotion_interface() != null)
		print("Has body: ", bot.get_body_interface() != null)
		print("Has vision: ", bot.get_vision_interface() != null)
		print("Has intention: ", bot.get_intention_interface() != null)
		
		if NextBotManager:
			print("Registered bots: ", NextBotManager.get_nextbot_count())
		
		return bot
	else:
		print("Bot not found")
		return null
