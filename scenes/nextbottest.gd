extends Node3D

func _ready():
	print("=== NextBot Autoload Test ===")
	if NextBotManager:
		print("✅ SUCCESS: NextBotManager is working!")
		print("Available debug types: ", NextBotManager.DebugType.ALL)
		print("Current bot count: ", NextBotManager.get_nextbot_count())
	else:
		print("❌ FAILED: NextBotManager not found")
		print("Check autoload setup!")
