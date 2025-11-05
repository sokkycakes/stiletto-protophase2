class_name GameMasterMusicController
extends Node

## Integrates MusicManager with GameMaster to handle automatic music transitions
## Listens to GameMaster signals and triggers appropriate music changes

@export var music_manager: MusicManager
@export var gamemaster_path: NodePath

var _gamemaster: Node

func _ready():
	# Find the GameMaster in the scene
	if gamemaster_path != NodePath(""):
		_gamemaster = get_node_or_null(gamemaster_path)
	else:
		# Try to find GameMaster automatically
		_gamemaster = _find_gamemaster()
	
	if not _gamemaster:
		push_warning("GameMasterMusicController: No GameMaster found")
		return
	
	print("[GameMasterMusicController] Found GameMaster: ", _gamemaster.name)
	
	# Connect to GameMaster signals
	_connect_to_gamemaster_signals()
	
	# Connect to MusicManager signals for debugging
	if music_manager:
		music_manager.music_changed.connect(_on_music_changed)
		music_manager.music_set_changed.connect(_on_music_set_changed)

func _find_gamemaster() -> Node:
	# Look for GameMaster in common locations
	var possible_paths = [
		"GameMaster",
		"../GameMaster",
		"../../GameMaster"
	]
	
	for path in possible_paths:
		var node = get_node_or_null(path)
		if node and node.has_method("_on_bell_rang"):
			return node
	
	# Look for any node in the gamemaster group
	var gamemasters = get_tree().get_nodes_in_group("gamemaster")
	if gamemasters.size() > 0:
		return gamemasters[0]
	
	return null

func _connect_to_gamemaster_signals() -> void:
	if not _gamemaster:
		return
	
	print("[GameMasterMusicController] Connecting to GameMaster signals...")
	
	# Connect to game state signals
	if _gamemaster.has_signal("game_started"):
		_gamemaster.game_started.connect(_on_game_started)
		print("[GameMasterMusicController] Connected to game_started signal")
	
	if _gamemaster.has_signal("game_over"):
		_gamemaster.game_over.connect(_on_game_over)
		print("[GameMasterMusicController] Connected to game_over signal")
	
	# Don't try to connect to bell directly - let GameMaster handle that
	# Instead, we'll override the GameMaster's _on_bell_rang method to also trigger music

func _on_bell_rang() -> void:
	if music_manager:
		print("[GameMasterMusicController] Bell rang - switching to normal game music")
		music_manager.play_state_music(MusicManager.GameState.NORMAL_GAME)

func _on_game_started() -> void:
	if music_manager:
		print("[GameMasterMusicController] Game started - ensuring normal game music")
		music_manager.play_state_music(MusicManager.GameState.NORMAL_GAME)

func _on_game_over(survived_time_ms: int, kills: int) -> void:
	if music_manager:
		print("[GameMasterMusicController] Game over - switching to pre-game music")
		music_manager.play_state_music(MusicManager.GameState.PRE_GAME)

func _on_music_changed(track_name: String, state: MusicManager.GameState) -> void:
	print("[GameMasterMusicController] Music changed to: ", track_name, " (State: ", state, ")")

func _on_music_set_changed(set_name: String) -> void:
	print("[GameMasterMusicController] Music set changed to: ", set_name)

# Public methods for manual control
func trigger_doom_music() -> void:
	if music_manager:
		print("[GameMasterMusicController] Triggering doom music")
		music_manager.play_state_music(MusicManager.GameState.DOOM)

func trigger_overwhelm_music() -> void:
	if music_manager:
		print("[GameMasterMusicController] Triggering overwhelm music")
		music_manager.play_state_music(MusicManager.GameState.OVERWHELM)

func select_random_music_set() -> void:
	if music_manager:
		music_manager.select_random_music_set() 