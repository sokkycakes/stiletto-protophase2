@tool
extends Node

class_name Killbox

@export_group("Killbox Settings")
@export var kill_areas: Array[Area3D] = []  # Array of Area3D nodes to monitor
@export var target_groups: Array[String] = ["player"]  # Groups that will trigger the killbox
@export var kill_action: KillAction = KillAction.RELOAD_SCENE  # What happens when something enters the killbox

@export_group("Scene Settings")
@export var target_scene: String = ""  # Scene to load if using LOAD_SCENE action

enum KillAction {
	RELOAD_SCENE,  # Reload the current scene
	LOAD_SCENE,    # Load a specific scene
	RESPAWN_PLAYER # Respawn the player at a specific point
}

func _ready():
	# Connect to all kill areas
	for area in kill_areas:
		if area:
			area.body_entered.connect(_on_body_entered.bind(area))
			print("Connected to area: ", area.name)

func _on_body_entered(body: Node3D, area: Area3D):
	print("Body entered: ", body.name)
	print("Body is in player group: ", body.is_in_group("player"))
	
	# Check if the body is in any of the target groups
	for group in target_groups:
		if body.is_in_group(group):
			print("Triggering kill action for group: ", group)
			_handle_kill_action()
			break

func _handle_kill_action():
	print("Handling kill action: ", kill_action)
	match kill_action:
		KillAction.RELOAD_SCENE:
			get_tree().reload_current_scene()
		KillAction.LOAD_SCENE:
			if target_scene.is_empty():
				push_error("Killbox: target_scene is empty but LOAD_SCENE action is selected")
				return
			get_tree().change_scene_to_file(target_scene)
		KillAction.RESPAWN_PLAYER:
			# Find the respawn node in the scene
			var respawn = get_tree().get_first_node_in_group("respawn")
			if respawn and respawn.has_method("respawn_player"):
				respawn.respawn_player()
			else:
				push_error("Killbox: No respawn node found or respawn_player method not available")

# Editor-only function to help with setup
func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	
	if kill_areas.is_empty():
		warnings.append("No kill areas assigned. Add Area3D nodes to monitor.")
	
	if target_groups.is_empty():
		warnings.append("No target groups specified. Nothing will trigger the killbox.")
	
	if kill_action == KillAction.LOAD_SCENE and target_scene.is_empty():
		warnings.append("LOAD_SCENE action selected but no target scene specified.")
	
	return warnings 
