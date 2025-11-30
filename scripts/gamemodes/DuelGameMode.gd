extends Node
class_name DuelGameMode

var game_world: GameWorld
var mode_definition: GameModeDefinition

# Store selected characters per player
var player_character_selections: Dictionary = {}  # peer_id -> character_id

# --- Waiting Phase & Countdown System ---
enum DuelState {
	WAITING_FOR_PLAYERS,  # Waiting for all players to spawn
	COUNTDOWN,            # Countdown timer active
	ACTIVE                # Players can move and fight
}

## Path to the countdown label in the scene. 
## Create a Label node in your map scene and assign it here.
## The label will be updated with countdown values and waiting messages.
@export var countdown_label_path: NodePath = NodePath("")

## Path to the scoreboard node containing localScore and oppScore labels
@export var scoreboard_path: NodePath = NodePath("")

## Path to the clock label that shows the round timer
@export var clock_label_path: NodePath = NodePath("")

var duel_state: DuelState = DuelState.WAITING_FOR_PLAYERS
var spawned_players: Array[int] = []  # Track which peer_ids have spawned
var player_ids: Array[int] = []  # The 2 player IDs in the duel
var countdown_timer: Timer
var countdown_value: int = 3
var countdown_label: Label = null
var scoreboard_node: Node = null
var local_score_label: Label = null
var opp_score_label: Label = null
var clock_label: Label = null
var round_timer: Timer
var round_time_remaining: float = 0.0

# --- Duel Scoring System ---
var player_scores: Dictionary = {}  # peer_id -> score (tracked by gamemode)
var kill_log: Array[Dictionary] = []  # Array of {killer_id, victim_id, timestamp}

func initialize(world: GameWorld, definition: GameModeDefinition) -> void:
	game_world = world
	mode_definition = definition
	
	if MultiplayerManager:
		if not MultiplayerManager.player_connected.is_connected(_on_player_connected):
			MultiplayerManager.player_connected.connect(_on_player_connected)
		if not MultiplayerManager.player_disconnected.is_connected(_on_player_disconnected):
			MultiplayerManager.player_disconnected.connect(_on_player_disconnected)
	
	# Connect to GameRulesManager for kill tracking (it handles server-side kill registration)
	if GameRulesManager:
		if not GameRulesManager.player_scored.is_connected(_on_game_rules_kill):
			GameRulesManager.player_scored.connect(_on_game_rules_kill)
	
	# Initialize waiting phase system (deferred to ensure we're in tree)
	call_deferred("_initialize_waiting_phase")
	
	# Show character select for local player (deferred to ensure we're in tree)
	call_deferred("_show_character_select_for_local_player")
	
	_enforce_player_limit()
	
	# Connect to player spawn events
	if game_world:
		# Check periodically for spawned players (after initialization)
		call_deferred("_start_spawn_checking")

func _exit_tree() -> void:
	if MultiplayerManager:
		if MultiplayerManager.player_connected.is_connected(_on_player_connected):
			MultiplayerManager.player_connected.disconnect(_on_player_connected)
		if MultiplayerManager.player_disconnected.is_connected(_on_player_disconnected):
			MultiplayerManager.player_disconnected.disconnect(_on_player_disconnected)
	
	if GameRulesManager:
		if GameRulesManager.player_scored.is_connected(_on_game_rules_kill):
			GameRulesManager.player_scored.disconnect(_on_game_rules_kill)

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
	
	if not game_world:
		print("[DuelGameMode] No game_world")
		return
	if not mode_definition:
		print("[DuelGameMode] No mode_definition")
		return
	
	# Handle offline mode (no MultiplayerManager) or online mode
	var local_peer_id: int = 1  # Default for offline mode
	var is_offline: bool = not MultiplayerManager
	
	if not is_offline:
		local_peer_id = MultiplayerManager.get_local_peer_id()
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
	else:
		print("[DuelGameMode] Offline mode - no MultiplayerManager, using default peer ID: ", local_peer_id)
	
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
	if not mode_definition:
		return
	
	var scene_path := _get_character_scene_path(character_id)
	if scene_path.is_empty():
		push_warning("[DuelGameMode] Character '%s' not found in definition" % character_id)
		return
	
	# Handle offline mode (no MultiplayerManager)
	if not MultiplayerManager:
		print("[DuelGameMode] Offline mode - processing character selection directly")
		_process_character_selection(peer_id, character_id, scene_path)
		return
	
	# Online mode - use multiplayer logic
	if MultiplayerManager.is_server():
		_process_character_selection(peer_id, character_id, scene_path)
	else:
		# Send selection to host for validation/spawn
		request_spawn_with_character.rpc_id(1, peer_id, character_id)

func _process_character_selection(peer_id: int, character_id: String, scene_path: String) -> void:
	player_character_selections[peer_id] = character_id
	_update_player_character_path(peer_id, scene_path)
	
	# In offline mode, call directly; in online mode, use RPC
	if not MultiplayerManager:
		_spawn_player_with_character(peer_id, scene_path)
	else:
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
	# Ensure local player info reflects the chosen character (only in online mode)
	if MultiplayerManager:
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
		# Track that this player has been spawned
		call_deferred("_on_player_spawned", peer_id)

# --- Waiting Phase & Countdown System ---

func _initialize_waiting_phase() -> void:
	"""Initialize the waiting phase system and UI"""
	duel_state = DuelState.WAITING_FOR_PLAYERS
	spawned_players.clear()
	player_ids.clear()
	player_scores.clear()
	kill_log.clear()
	countdown_value = 3
	
	# Create countdown timer
	countdown_timer = Timer.new()
	countdown_timer.one_shot = false
	countdown_timer.wait_time = 1.0
	countdown_timer.timeout.connect(_on_countdown_tick)
	add_child(countdown_timer)
	
	# Create round timer
	round_timer = Timer.new()
	round_timer.one_shot = true
	round_timer.timeout.connect(_on_round_timeout)
	add_child(round_timer)
	
	# Find UI elements from editor paths
	_find_countdown_label()
	_find_scoreboard_ui()
	_find_clock_label()
	
	# Initialize scoreboard
	_update_scoreboard()
	
	# Start periodic scoreboard updates
	_start_scoreboard_updates()

func _start_spawn_checking() -> void:
	"""Start checking for spawned players"""
	if game_world:
		_check_player_spawns()

func _find_countdown_label() -> void:
	"""Find the countdown label from the editor-assigned path"""
	if not game_world:
		return
	
	# Wait a frame to ensure scene is fully loaded
	await get_tree().process_frame
	
	# Try to find the label using the path
	if countdown_label_path != NodePath(""):
		# Path is relative to game_world or scene root
		var node = game_world.get_node_or_null(countdown_label_path)
		if not node:
			# Try from scene root
			var scene_root = get_tree().current_scene
			if scene_root:
				node = scene_root.get_node_or_null(countdown_label_path)
		
		if node and node is Label:
			countdown_label = node as Label
			print("[DuelGameMode] Found countdown label at path: ", countdown_label_path)
		else:
			push_warning("[DuelGameMode] Countdown label path points to invalid node or non-Label: %s" % countdown_label_path)
	else:
		print("[DuelGameMode] No countdown label path assigned. Countdown UI will not be displayed.")
	
	# Update display if label was found
	if countdown_label and duel_state == DuelState.WAITING_FOR_PLAYERS:
		_update_countdown_display()

func _find_scoreboard_ui() -> void:
	"""Find the scoreboard node and its child labels"""
	if not game_world:
		return
	
	# Wait a frame to ensure scene is fully loaded
	await get_tree().process_frame
	
	if scoreboard_path != NodePath(""):
		# Try to find the scoreboard node
		var node = game_world.get_node_or_null(scoreboard_path)
		if not node:
			# Try from scene root
			var scene_root = get_tree().current_scene
			if scene_root:
				node = scene_root.get_node_or_null(scoreboard_path)
		
		if node:
			scoreboard_node = node
			# Find child labels
			local_score_label = node.get_node_or_null("localScore") as Label
			opp_score_label = node.get_node_or_null("oppScore") as Label
			
			if local_score_label:
				print("[DuelGameMode] Found localScore label")
			else:
				push_warning("[DuelGameMode] localScore label not found in scoreboard")
			
			if opp_score_label:
				print("[DuelGameMode] Found oppScore label")
			else:
				push_warning("[DuelGameMode] oppScore label not found in scoreboard")
		else:
			push_warning("[DuelGameMode] Scoreboard node not found at path: %s" % scoreboard_path)
	else:
		print("[DuelGameMode] No scoreboard path assigned")

func _find_clock_label() -> void:
	"""Find the clock label from the editor-assigned path"""
	if not game_world:
		return
	
	# Wait a frame to ensure scene is fully loaded
	await get_tree().process_frame
	
	if clock_label_path != NodePath(""):
		# Try to find the label using the path
		var node = game_world.get_node_or_null(clock_label_path)
		if not node:
			# Try from scene root
			var scene_root = get_tree().current_scene
			if scene_root:
				node = scene_root.get_node_or_null(clock_label_path)
		
		if node and node is Label:
			clock_label = node as Label
			print("[DuelGameMode] Found clock label at path: ", clock_label_path)
		else:
			push_warning("[DuelGameMode] Clock label path points to invalid node or non-Label: %s" % clock_label_path)
	else:
		print("[DuelGameMode] No clock label path assigned")

func _check_player_spawns() -> void:
	"""Periodically check if players have spawned"""
	if not game_world:
		return
	
	# Check all players in game_world
	var all_players = game_world.players
	for peer_id in all_players:
		if peer_id not in spawned_players:
			var player = all_players[peer_id]
			if player and is_instance_valid(player):
				# Wait a frame for pawn to be initialized
				await get_tree().process_frame
				if player.pawn:
					_on_player_spawned(peer_id)
	
	# Check again after a short delay if still waiting
	if duel_state == DuelState.WAITING_FOR_PLAYERS and is_inside_tree():
		await get_tree().create_timer(0.5).timeout
		if is_inside_tree():
			_check_player_spawns()

func _on_player_spawned(peer_id: int) -> void:
	"""Called when a player has been spawned"""
	if peer_id in spawned_players:
		return
	
	spawned_players.append(peer_id)
	
	# Initialize score for this player
	if peer_id not in player_scores:
		player_scores[peer_id] = 0
	
	# Store player IDs (should be exactly 2 for duel)
	if spawned_players.size() <= mode_definition.max_players:
		player_ids = spawned_players.duplicate()
	
	print("[DuelGameMode] Player %d spawned. Total spawned: %d/%d" % [peer_id, spawned_players.size(), mode_definition.max_players])
	
	# Allow free movement during waiting phase
	# _disable_player_movement(peer_id)
	
	# Check if all players are spawned (server only for multiplayer)
	if not MultiplayerManager or MultiplayerManager.is_server():
		_check_all_players_spawned()
		
		# Sync initial scores to all clients
		_sync_scores.rpc(player_scores)

func _check_all_players_spawned() -> void:
	"""Check if all required players have spawned and start countdown"""
	if duel_state != DuelState.WAITING_FOR_PLAYERS:
		return
	
	var required_players = mode_definition.max_players
	if spawned_players.size() >= required_players:
		print("[DuelGameMode] All players spawned! Starting countdown...")
		_start_countdown()

func _start_countdown() -> void:
	"""Start the countdown timer"""
	if duel_state != DuelState.WAITING_FOR_PLAYERS:
		return
	
	duel_state = DuelState.COUNTDOWN
	countdown_value = 3
	
	# Show countdown label if it exists
	if countdown_label:
		countdown_label.visible = true
	_update_countdown_display()
	
	# Start timer (server only for multiplayer)
	if not MultiplayerManager or MultiplayerManager.is_server():
		countdown_timer.start()
		# Sync countdown start to clients
		if MultiplayerManager:
			_sync_countdown_start.rpc(countdown_value)

@rpc("authority", "call_local", "reliable")
func _sync_countdown_start(value: int) -> void:
	"""Sync countdown start to all clients"""
	if duel_state != DuelState.COUNTDOWN:
		duel_state = DuelState.COUNTDOWN
		countdown_value = value
		if countdown_label:
			countdown_label.visible = true
		_update_countdown_display()
		if not countdown_timer.is_stopped():
			countdown_timer.stop()
		countdown_timer.start()

func _on_countdown_tick() -> void:
	"""Called each second during countdown"""
	if duel_state != DuelState.COUNTDOWN:
		return
	
	countdown_value -= 1
	_update_countdown_display()
	
	# Sync countdown value to clients (server only)
	if MultiplayerManager and MultiplayerManager.is_server():
		_sync_countdown_value.rpc(countdown_value)
	
	if countdown_value <= 0:
		# Server triggers end, which syncs to clients
		_end_countdown()

@rpc("authority", "call_local", "reliable")
func _sync_countdown_value(value: int) -> void:
	"""Sync countdown value to all clients"""
	countdown_value = value
	_update_countdown_display()
	# Don't call _end_countdown here - wait for server to sync it

func _update_countdown_display() -> void:
	"""Update the countdown UI display"""
	if not countdown_label:
		return
	
	if duel_state == DuelState.COUNTDOWN:
		if countdown_value > 0:
			countdown_label.text = str(countdown_value)
		else:
			countdown_label.text = "FIGHT!"
		countdown_label.visible = true
	elif duel_state == DuelState.WAITING_FOR_PLAYERS:
		var spawned = spawned_players.size()
		var required = mode_definition.max_players
		countdown_label.text = "Waiting for players...\n%d/%d" % [spawned, required]
		countdown_label.visible = true
	else:
		# Hide label when match is active
		countdown_label.visible = false

func _end_countdown() -> void:
	"""End countdown and enable player movement (server only)"""
	if duel_state != DuelState.COUNTDOWN:
		return
	
	# Only server should trigger the end sequence
	if MultiplayerManager and not MultiplayerManager.is_server():
		return
	
	duel_state = DuelState.ACTIVE
	countdown_timer.stop()
	
	# Sync end to all clients (including this one via call_local)
	if MultiplayerManager:
		_sync_countdown_end.rpc()
	else:
		# Offline mode - handle locally
		_handle_countdown_end()

@rpc("authority", "call_local", "reliable")
func _sync_countdown_end() -> void:
	"""Sync countdown end to all clients"""
	_handle_countdown_end()

func _handle_countdown_end() -> void:
	"""Handle the countdown end sequence (called on all clients)"""
	if duel_state != DuelState.COUNTDOWN and duel_state != DuelState.ACTIVE:
		return
	
	duel_state = DuelState.ACTIVE
	if countdown_timer:
		countdown_timer.stop()
	
	# Show "FIGHT!" briefly, then hide
	_update_countdown_display()
	await get_tree().create_timer(0.5).timeout
	
	if not is_inside_tree():
		return
	
	# Hide countdown label
	if countdown_label:
		countdown_label.visible = false
	
	# Enable movement for all players
	_enable_all_players_movement()
	
	# Start round timer (default 60 seconds per round)
	_start_round_timer(60.0)
	
	print("[DuelGameMode] Countdown ended! Players can now move.")

func _disable_player_movement(peer_id: int) -> void:
	"""Disable movement for a specific player"""
	if not game_world:
		return
	
	var player = game_world.get_player_by_peer_id(peer_id)
	if not player or not player.pawn:
		return
	
	# Find GoldGdt_Controls in the pawn
	var controls = _find_goldgdt_controls(player.pawn)
	if controls:
		controls.disable_movement()
		print("[DuelGameMode] Disabled movement for player %d" % peer_id)
	else:
		# Fallback: disable input processing
		player.pawn.set_process_input(false)
		print("[DuelGameMode] Disabled input for player %d (no GoldGdt_Controls found)" % peer_id)

func _enable_all_players_movement() -> void:
	"""Enable movement for all spawned players"""
	if not game_world:
		return
	
	for peer_id in spawned_players:
		var player = game_world.get_player_by_peer_id(peer_id)
		if not player or not player.pawn:
			continue
		
		# Find GoldGdt_Controls in the pawn
		var controls = _find_goldgdt_controls(player.pawn)
		if controls:
			controls.enable_movement()
			print("[DuelGameMode] Enabled movement for player %d" % peer_id)
		else:
			# Fallback: enable input processing
			player.pawn.set_process_input(true)
			print("[DuelGameMode] Enabled input for player %d (no GoldGdt_Controls found)" % peer_id)

func _find_goldgdt_controls(node: Node) -> GoldGdt_Controls:
	"""Recursively find GoldGdt_Controls component"""
	if node is GoldGdt_Controls:
		return node as GoldGdt_Controls
	
	for child in node.get_children():
		var result = _find_goldgdt_controls(child)
		if result:
			return result
	
	return null

# --- Round-Based Duel System ---

func _on_game_rules_kill(killer_peer_id: int, points: int) -> void:
	"""Called when GameRulesManager registers a kill (server-side only)"""
	# GameRulesManager already validated this is server-only
	if duel_state != DuelState.ACTIVE:
		return
	
	# Only handle in duel mode
	if GameRulesManager.get_current_mode() != GameRulesManager.GameMode.DUEL:
		return
	
	# Only server handles round resets
	if MultiplayerManager and not MultiplayerManager.is_server():
		return
	
	# Update our local score tracking
	if killer_peer_id >= 0 and killer_peer_id in player_scores:
		player_scores[killer_peer_id] += 1
		print("[DuelGameMode] Player %d scored! New score: %d" % [killer_peer_id, player_scores[killer_peer_id]])
		
		# Sync scores to all clients
		_sync_scores.rpc(player_scores)
		
		# Update scoreboard immediately
		_update_scoreboard()
		
		# Stop round timer
		if round_timer:
			round_timer.stop()
		
		# Check if player reached win condition
		var score_limit = GameRulesManager.score_limit if GameRulesManager else 5
		if player_scores[killer_peer_id] >= score_limit:
			print("[DuelGameMode] Player %d reached score limit! Ending match..." % killer_peer_id)
			# End the match
			if GameRulesManager:
				GameRulesManager.end_match()
			return
		
		# Wait 4 seconds before starting new round
		await get_tree().create_timer(4.0).timeout
		
		if not is_inside_tree():
			return
		
		# Start new round
		_start_new_round()

func _on_player_died_direct(killer_peer_id: int, victim_peer_id: int) -> void:
	"""Direct handler for player_died signal - tracks kills and updates scores
	Parameters come in this order because:
	1. Signal emits killer_peer_id (first param from signal)
	2. .bind() appends victim_peer_id (bound when connecting)
	"""
	if duel_state != DuelState.ACTIVE:
		return
	
	if victim_peer_id < 0 or victim_peer_id not in spawned_players:
		return
	
	# Only server processes kills and updates scores
	if MultiplayerManager and not MultiplayerManager.is_server():
		return
	
	print("[DuelGameMode] Kill detected - killer: %d, victim: %d" % [killer_peer_id, victim_peer_id])
	
	# Log the kill
	var kill_entry = {
		"killer_id": killer_peer_id,
		"victim_id": victim_peer_id,
		"timestamp": Time.get_unix_time_from_system()
	}
	kill_log.append(kill_entry)
	
	# Update score for the killer (only if valid killer, not suicide/world kill)
	if killer_peer_id >= 0 and killer_peer_id in player_scores:
		player_scores[killer_peer_id] += 1
		print("[DuelGameMode] Player %d scored! New score: %d" % [killer_peer_id, player_scores[killer_peer_id]])
		
		# Sync scores to all clients
		_sync_scores.rpc(player_scores)
		
		# Update scoreboard immediately
		_update_scoreboard()
		
		# Stop round timer
		if round_timer:
			round_timer.stop()
		
		# Wait 4 seconds before starting new round
		await get_tree().create_timer(4.0).timeout
		
		if not is_inside_tree():
			return
		
		# Start new round
		_start_new_round()

func _start_new_round() -> void:
	"""Start a new round: reset players to spawn and begin countdown"""
	if not game_world:
		return
	
	# Reset duel state to waiting
	duel_state = DuelState.WAITING_FOR_PLAYERS
	countdown_value = 3
	
	# Sync round reset to all clients
	if MultiplayerManager:
		_sync_round_reset.rpc()
	else:
		# Offline mode - handle locally
		_handle_round_reset()

@rpc("authority", "call_local", "reliable")
func _sync_round_reset() -> void:
	"""Sync round reset to all clients"""
	_handle_round_reset()

@rpc("authority", "call_local", "reliable")
func _sync_scores(scores: Dictionary) -> void:
	"""Sync scores from server to all clients"""
	player_scores = scores
	_update_scoreboard()

func _handle_round_reset() -> void:
	"""Handle the round reset sequence (called on all clients)"""
	if not game_world:
		return
	
	# Reset duel state to waiting
	duel_state = DuelState.WAITING_FOR_PLAYERS
	countdown_value = 3
	
	# Allow free movement during waiting phase
	# _disable_all_players_movement()
	
	# Reset all players to their spawn points
	_reset_all_players_to_spawn()
	
	# Update scoreboard after reset
	_update_scoreboard()
	
	# Sync scores to ensure clients have latest
	if MultiplayerManager and MultiplayerManager.is_server():
		_sync_scores.rpc(player_scores)
	
	# Wait a moment for players to be reset, then start countdown
	await get_tree().create_timer(0.5).timeout
	
	if not is_inside_tree():
		return
	
	# Start countdown (server only)
	if not MultiplayerManager or MultiplayerManager.is_server():
		_start_countdown()

func _reset_all_players_to_spawn() -> void:
	"""Reset all spawned players to their assigned spawn points"""
	if not game_world:
		return
	
	# Only server should trigger the reset, then sync to clients
	if MultiplayerManager and MultiplayerManager.is_server():
		# Sync reset to all clients
		_sync_player_reset.rpc()
	else:
		# Client: handle reset locally
		_handle_player_reset_local()

@rpc("authority", "call_local", "reliable")
func _sync_player_reset() -> void:
	"""Sync player reset to all clients"""
	_handle_player_reset_local()

func _handle_player_reset_local() -> void:
	"""Handle player reset on all clients"""
	if not game_world:
		return
	
	for peer_id in spawned_players:
		var player = game_world.get_player_by_peer_id(peer_id)
		if not player or not is_instance_valid(player):
			continue
		
		# Get spawn point for this player
		var spawn_point = game_world.get_spawn_point_node_for_player(peer_id)
		if not spawn_point:
			push_warning("[DuelGameMode] No spawn point found for player %d" % peer_id)
			continue
		
		# Use exact spawn position (no random variation for round resets)
		var spawn_pos = spawn_point.global_position
		var spawn_yaw = spawn_point.get_spawn_rotation_y()
		
		# Only authority should modify health/is_alive
		if player.is_multiplayer_authority():
			# Reset player health and state
			if player.has_method("_respawn_player"):
				# Use the respawn method to restore health
				player._respawn_player()
			else:
				# Fallback: manually restore health
				player.health = player.max_health
				player.is_alive = true
				if player.has_method("health_changed"):
					player.health_changed.emit(0, player.health)
		else:
			# For non-authority, just ensure is_alive is true
			player.is_alive = true
		
		# Teleport player to spawn (all clients)
		if player.has_method("set_spawn_transform"):
			player.set_spawn_transform(spawn_pos, spawn_yaw)
		else:
			player.global_position = spawn_pos
			if player.pawn:
				if player.pawn.has_method("set_spawn_transform"):
					player.pawn.set_spawn_transform(spawn_pos, spawn_yaw)
				else:
					player.pawn.global_position = spawn_pos
					if player.pawn_body:
						player.pawn_body.global_position = spawn_pos
		
		# Ensure pawn is visible (all clients)
		if player.pawn:
			player.pawn.visible = true
			# Ensure all mesh instances are visible
			_set_pawn_visibility_recursive(player.pawn, true)
		
		# Use the existing RPC method to clear death visuals on all clients
		# This ensures proper synchronization across network
		# Only server should call the RPC (it will sync to all clients via call_local)
		if player.has_method("player_respawned_networked"):
			if not MultiplayerManager or MultiplayerManager.is_server():
				# Server calls RPC which syncs to all clients
				player.player_respawned_networked.rpc()
			# Clients will receive the RPC automatically
		else:
			# Fallback: clear locally if RPC doesn't exist
			if player.has_method("_clear_dead_visuals"):
				player._clear_dead_visuals()
			# Ensure visibility
			if player.pawn:
				player.pawn.visible = true
				_set_pawn_visibility_recursive(player.pawn, true)
		
		# Reset PlayerState to NORMAL if available (all clients)
		if player.pawn:
			var player_state = player.pawn.get_node_or_null("Body/PlayerState")
			if player_state and player_state.has_method("set_state"):
				# PlayerState enum should be available if set_state exists
				# Access it directly - if it doesn't exist, the script will error which is fine
				player_state.set_state(player_state.PlayerState.NORMAL)
		
		# Force sync for authority players
		if player.is_multiplayer_authority() and player.has_method("force_sync"):
			player.force_sync()
		
		print("[DuelGameMode] Reset player %d to spawn point: %s" % [peer_id, spawn_point.name])

func _set_pawn_visibility_recursive(node: Node, visible: bool) -> void:
	"""Recursively set visibility on all MeshInstance3D nodes"""
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = visible
	
	for child in node.get_children():
		_set_pawn_visibility_recursive(child, visible)

func _disable_all_players_movement() -> void:
	"""Disable movement for all spawned players"""
	if not game_world:
		return
	
	for peer_id in spawned_players:
		_disable_player_movement(peer_id)

# --- Scoreboard & Round Timer UI ---

func _update_scoreboard() -> void:
	"""Update the scoreboard with current scores"""
	if not local_score_label or not opp_score_label:
		return
	
	var local_peer_id = MultiplayerManager.get_local_peer_id() if MultiplayerManager else 1
	var local_score = 0
	var opp_score = 0
	
	# Get scores for both players from our local tracking
	for peer_id in player_ids:
		var score = player_scores.get(peer_id, 0)
		
		if peer_id == local_peer_id:
			local_score = score
		else:
			opp_score = score
	
	# Update labels - left is local player, right is opponent
	local_score_label.text = str(local_score)
	opp_score_label.text = str(opp_score)

func _start_round_timer(duration: float) -> void:
	"""Start the round timer"""
	if not round_timer:
		return
	
	round_time_remaining = duration
	round_timer.wait_time = duration
	round_timer.start()
	
	# Update clock immediately
	_update_clock_display()
	
	# Start periodic updates
	_update_clock_periodically()

func _update_clock_periodically() -> void:
	"""Update clock display every frame while timer is running"""
	while round_timer and not round_timer.is_stopped() and round_time_remaining > 0:
		round_time_remaining = round_timer.time_left
		_update_clock_display()
		await get_tree().process_frame

func _update_clock_display() -> void:
	"""Update the clock label with remaining time"""
	if not clock_label:
		return
	
	var minutes = int(round_time_remaining) / 60
	var seconds = int(round_time_remaining) % 60
	clock_label.text = "%02d:%02d" % [minutes, seconds]

func _on_round_timeout() -> void:
	"""Called when round timer expires"""
	print("[DuelGameMode] Round timer expired!")
	
	# Round timeout - could end in a draw or give point to player with more health
	# For now, just reset the round
	if MultiplayerManager and MultiplayerManager.is_server():
		# Reset round after timeout
		_start_new_round()

func _start_scoreboard_updates() -> void:
	"""Start periodically updating the scoreboard"""
	# Update scoreboard periodically as a fallback
	while is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		# Check again after await (scene might have unloaded during wait)
		if not is_inside_tree():
			break
		if duel_state == DuelState.ACTIVE:
			_update_scoreboard()

func _connect_to_player_deaths() -> void:
	"""Connect to player_died signals from all NetworkedPlayer instances"""
	if not game_world:
		return
	
	# Wait a frame for players to spawn
	await get_tree().process_frame
	
	# Connect to existing players - bind victim_peer_id so we know who died
	for peer_id in game_world.players:
		var player = game_world.get_player_by_peer_id(peer_id)
		if player and is_instance_valid(player):
			# Disconnect if already connected (to avoid duplicates)
			if player.player_died.is_connected(_on_player_died_direct):
				player.player_died.disconnect(_on_player_died_direct)
			# Connect with victim_peer_id bound as first parameter
			player.player_died.connect(_on_player_died_direct.bind(peer_id))
	
	# Also check periodically for new players
	_check_for_new_players_to_connect()

func _check_for_new_players_to_connect() -> void:
	"""Periodically check for new players and connect to their death signals"""
	if not game_world:
		return
	
	for peer_id in game_world.players:
		var player = game_world.get_player_by_peer_id(peer_id)
		if player and is_instance_valid(player):
			# Disconnect if already connected (to avoid duplicates)
			if player.player_died.is_connected(_on_player_died_direct):
				player.player_died.disconnect(_on_player_died_direct)
			# Connect with victim_peer_id bound as first parameter
			player.player_died.connect(_on_player_died_direct.bind(peer_id))
	
	# Check again after a delay
	await get_tree().create_timer(1.0).timeout
	if is_inside_tree():
		_check_for_new_players_to_connect()
