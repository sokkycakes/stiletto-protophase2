	  
# respawn_handler.gd
extends Node

func _unhandled_input(event):
	# Check if the defined "respawn_key" action was just pressed.
	if event.is_action_pressed("respawn"):
		# Reset timescale before respawning (fixes bug where death timescale effect gets stuck)
		Engine.time_scale = 1.0
		# Prefer BaseGameMaster respawn if available
		if has_node("/root/BaseGameMaster"):
			var gm = get_node("/root/BaseGameMaster")
			if gm and gm.has_method("respawn_player"):
				gm.respawn_player()
				return
		# Fallback: reload current scene
		get_tree().reload_current_scene()
		# Optional: If you want to mark the input as handled so other nodes don't process it for this key press:
		# get_tree().get_root().set_input_as_handled()

# If you prefer to check in _process (less ideal for single key presses but works):
# func _process(delta):
#     if Input.is_action_just_pressed("respawn_key"):
#         get_tree().reload_current_scene()

	
