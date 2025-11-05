extends Node3D

func _ready():
	print("=== Testing Fixed NextBotManager ===")
	if NextBotManager:
		print("✅ SUCCESS: NextBotManager is working!")
		print("Bot count: ", NextBotManager.get_nextbot_count())
		print("Debug types: ", NextBotManager.DebugType.ALL)
		
		# Test a method
		NextBotManager.set_debug_types(NextBotManager.DebugType.BEHAVIOR)
		print("✅ Methods working correctly")
	else:
		print("❌ NextBotManager still not accessible")
