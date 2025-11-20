extends Node
class_name DuelGameMode

var game_world: GameWorld
var mode_definition: GameModeDefinition

# Store selected characters per player
var player_character_selections: Dictionary = {}  # peer_id -> character_id

func initialize(world: GameWorld, definition: GameModeDefinition) -> void:
	game_world = world
	mode_definition = definition
	
	if MultiplayerManager:
		if not MultiplayerManager.player_connected.is_connected(_on_player_connected):
			MultiplayerManager.player_connected.connect(_on_player_connected)
		if not MultiplayerManager.player_disconnected.is_connected(_on_player_disconnected):
			MultiplayerManager.player_disconnected.connect(_on_player_disconnected)
	
	# Show character select for local player (deferred to ensure we're in tree)
	call_deferred("_show_character_select_for_local_player")
	
	_enforce_player_limit()

func _exit_tree() -> void:
	if MultiplayerManager:
		if MultiplayerManager.player_connected.is_connected(_on_player_connected):
			MultiplayerManager.player_connected.disconnect(_on_player_connected)
		if MultiplayerManager.player_disconnected.is_connected(_on_player_disconnected):
			MultiplayerManager.player_disconnected.disconnect(_on_player_disconnected)

func _on_player_connected(_peer_id: int, _info: Dictionary) -> void:
	_enforce_player_limit()

func _on_player_disconnected(_peer_id: int) -> void:
	_enforce_player_limit()

func _enforce_player_limit() -> void:
	if not MultiplayerManager or not MultiplayerManager.is_server():
		return
	
	var players := MultiplayerManager.get_connected_players()
	if players.size() <= mode_definition.max_players:
		return
	
	var peer_ids: Array = players.keys()
	peer_ids.sort()
	
	for i in range(mode_definition.max_players, peer_ids.size()):
		var peer_id: int = peer_ids[i]
		if MultiplayerManager.has_method("_remove_player_from_game"):
			MultiplayerManager._remove_player_from_game(peer_id)

func _show_character_select_for_local_player() -> void:
	print("[DuelGameMode] _show_character_select_for_local_player called")
	
	# Only show character select for the local player
	if not MultiplayerManager:
		print("[DuelGameMode] No MultiplayerManager")
		return
	if not game_world:
		print("[DuelGameMode] No game_world")
		return
	if not mode_definition:
		print("[DuelGameMode] No mode_definition")
		return
	
	var local_peer_id = MultiplayerManager.get_local_peer_id()
	print("[DuelGameMode] Local peer ID: ", local_peer_id)
	
	# If this peer already has a character selected, skip showing character select again
	if player_character_selections.has(local_peer_id):
		print("[DuelGameMode] Local player already has a character selection, skipping character select UI.")
		return
	
	if MultiplayerManager.connected_players.has(local_peer_id):
		var info = MultiplayerManager.connected_players[local_peer_id]
		if info.has("character_path") and str(info["character_path"]) != "":
			print("[DuelGameMode] Local player already has character_path set (", info["character_path"], "), skipping character select UI.")
			return
	
	# Get available characters from mode definition
	var character_definitions = mode_definition.available_characters
	print("[DuelGameMode] Available characters: ", character_definitions.size())
	
	if character_definitions.is_empty():
		print("[DuelGameMode] WARNING: No characters available in mode definition!")
		return
	
	# Instantiate character select UI using mode definition's scene
	var char_select_scene = mode_definition.character_select_ui_scene
	if not char_select_scene:
		print("[DuelGameMode] Failed to load character select scene from mode definition")
		return
	
	var char_select = char_select_scene.instantiate() as CharacterSelect
	if not char_select:
		print("[DuelGameMode] Failed to instantiate character select")
		return
	
	print("[DuelGameMode] Character select UI instantiated successfully")
	
	# Set available characters
	char_select.set_characters(character_definitions)
	
	# Connect to selection signal
	if not char_select.character_selected.is_connected(_on_character_selected):
		char_select.character_selected.connect(_on_character_selected.bind(local_peer_id))
	
	# Add to scene tree (on top)
	game_world.add_child(char_select)
	char_select.z_index = 1000
	
	print("[DuelGameMode] Character select UI added to scene tree")

func _on_character_selected(character_id: String, peer_id: int) -> void:
	if not mode_definition or not MultiplayerManager:
		return
	
	var scene_path := _get_character_scene_path(character_id)
	if scene_path.is_empty():
		push_warning("[DuelGameMode] Character '%s' not found in definition" % character_id)
		return
	
	if MultiplayerManager.is_server():
		_process_character_selection(peer_id, character_id, scene_path)
	else:
		# Send selection to host for validation/spawn
		request_spawn_with_character.rpc_id(1, peer_id, character_id)

func _process_character_selection(peer_id: int, character_id: String, scene_path: String) -> void:
	player_character_selections[peer_id] = character_id
	_update_player_character_path(peer_id, scene_path)
	_spawn_player_with_character.rpc(peer_id, scene_path)

func _update_player_character_path(peer_id: int, scene_path: String) -> void:
	if not MultiplayerManager:
		return
	
	# Update authoritative list
	if MultiplayerManager.connected_players.has(peer_id):
		MultiplayerManager.connected_players[peer_id]["character_path"] = scene_path
	else:
		MultiplayerManager.connected_players[peer_id] = {
			"peer_id": peer_id,
			"name": "Player %s" % peer_id,
			"team": 0,
			"score": 0,
			"character_path": scene_path
		}
	
	# Sync to clients if we are the host
	if MultiplayerManager.is_server():
		MultiplayerManager.sync_player_list.rpc(MultiplayerManager.connected_players)

func _get_character_scene_path(character_id: String) -> String:
	if not mode_definition:
		return ""
	for char_def in mode_definition.available_characters:
		if char_def.id == character_id:
			return char_def.scene_path
	return ""

@rpc("any_peer", "call_remote", "reliable")
func request_spawn_with_character(peer_id: int, character_id: String) -> void:
	if not MultiplayerManager.is_server():
		return
	
	var scene_path := _get_character_scene_path(character_id)
	if scene_path.is_empty():
		push_warning("[DuelGameMode] Server: character '%s' not found" % character_id)
		return
	
	_process_character_selection(peer_id, character_id, scene_path)

@rpc("authority", "call_local", "reliable")
func _spawn_player_with_character(peer_id: int, scene_path: String) -> void:
	if not MultiplayerManager:
		return
	
	# Ensure local player info reflects the chosen character
	if MultiplayerManager.connected_players.has(peer_id):
		MultiplayerManager.connected_players[peer_id]["character_path"] = scene_path
	else:
		MultiplayerManager.connected_players[peer_id] = {
			"peer_id": peer_id,
			"name": "Player %s" % peer_id,
			"team": 0,
			"score": 0,
			"character_path": scene_path
		}
	
	if game_world:
		game_world._spawn_player(peer_id)

