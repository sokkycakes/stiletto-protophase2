class_name MusicManager
extends Node

## Manages music transitions between different game states
## Handles random selection of music sets and smooth transitions

signal music_changed(track_name: String, state: GameState)
signal music_set_changed(set_name: String)

enum GameState {
	PRE_GAME,
	NORMAL_GAME,
	DOOM,
	OVERWHELM
}

@export var music_sets: Array[MusicSet] = []
@export var fade_duration: float = 1.0
@export var auto_randomize: bool = true

var _current_music_set: MusicSet
var _current_state: GameState = GameState.PRE_GAME
var _bgm_player: AudioStreamPlayer
var _fade_tween: Tween
var _doom_countdown_active: bool = false

func _ready():
	# Add to group for easy finding
	add_to_group("music_manager")
	
	# Find the BGM player in the scene
	_bgm_player = _find_bgm_player()
	if not _bgm_player:
		push_warning("MusicManager: No BGM player found in scene")
		return
	
	print("[MusicManager] Found BGM player: ", _bgm_player.name, " at path: ", _bgm_player.get_path())
	print("[MusicManager] BGM player bus: ", _bgm_player.bus)
	print("[MusicManager] BGM player volume: ", _bgm_player.volume_db)
	print("[MusicManager] BGM player autoplay: ", _bgm_player.autoplay)
	print("[MusicManager] Available music sets: ", music_sets.size())
	
	# Initialize with a random music set if available
	if auto_randomize and music_sets.size() > 0:
		select_random_music_set()
		
		# Debug: Check if the selected music set has valid tracks
		if _current_music_set:
			print("[MusicManager] Selected music set details:")
			print("[MusicManager] - Pre-game track: ", _current_music_set.pre_game_track.resource_path if _current_music_set.pre_game_track else "null")
			print("[MusicManager] - Normal track: ", _current_music_set.normal_game_track.resource_path if _current_music_set.normal_game_track else "null")
			print("[MusicManager] - Doom track: ", _current_music_set.doom_track.resource_path if _current_music_set.doom_track else "null")
			print("[MusicManager] - Overwhelm track: ", _current_music_set.overwhelm_track.resource_path if _current_music_set.overwhelm_track else "null")
	else:
		push_warning("MusicManager: No music sets available or auto_randomize disabled")
	
	# Force take control and start with pre-game music
	force_take_control()

func _find_bgm_player() -> AudioStreamPlayer:
	print("[MusicManager] Searching for BGM player...")
	
	# Try to find BGM player in common locations
	var possible_paths = [
		"env/bgm",
		"BGM",
		"Audio/BGM",
		"Music/BGM",
		"../env/bgm",
		"../../env/bgm",
		"../BGM",
		"../../BGM"
	]
	
	for path in possible_paths:
		var node = get_node_or_null(path)
		print("[MusicManager] Checking path '", path, "': ", node.name if node else "null")
		if node and node is AudioStreamPlayer:
			print("[MusicManager] Found BGM player at: ", path)
			return node
	
	# If not found, look for any AudioStreamPlayer in the scene
	print("[MusicManager] Searching for AudioStreamPlayer nodes in scene...")
	var all_nodes = get_tree().get_nodes_in_group("")
	var audio_players = []
	
	for node in all_nodes:
		if node is AudioStreamPlayer:
			audio_players.append(node)
			print("[MusicManager] Found AudioStreamPlayer: ", node.name, " at path: ", node.get_path())
	
	if audio_players.size() > 0:
		print("[MusicManager] Using first AudioStreamPlayer found: ", audio_players[0].name)
		return audio_players[0]
	
	# Also check for nodes in the "bgm" group
	var bgm_group_nodes = get_tree().get_nodes_in_group("bgm")
	print("[MusicManager] Nodes in 'bgm' group: ", bgm_group_nodes.size())
	for node in bgm_group_nodes:
		print("[MusicManager] BGM group node: ", node.name, " (", node.get_class(), ")")
		if node is AudioStreamPlayer:
			print("[MusicManager] Found BGM player in group: ", node.name)
			return node
	
	print("[MusicManager] No BGM player found!")
	return null

func select_random_music_set() -> MusicSet:
	if music_sets.size() == 0:
		push_warning("MusicManager: No music sets available")
		return null
	
	var random_index = randi() % music_sets.size()
	_current_music_set = music_sets[random_index]
	music_set_changed.emit(_current_music_set.set_name)
	print("[MusicManager] Selected music set: ", _current_music_set.set_name)
	return _current_music_set

func select_music_set(set_index: int) -> MusicSet:
	if set_index < 0 or set_index >= music_sets.size():
		push_warning("MusicManager: Invalid music set index: ", set_index)
		return null
	
	_current_music_set = music_sets[set_index]
	music_set_changed.emit(_current_music_set.set_name)
	print("[MusicManager] Selected music set: ", _current_music_set.set_name)
	return _current_music_set

func play_state_music(state: GameState) -> void:
	if not _current_music_set:
		push_warning("MusicManager: No music set selected")
		return
	
	if not _bgm_player:
		push_warning("MusicManager: No BGM player available")
		return
	
	# Don't play music during doom countdown - let the countdown effects play
	if _doom_countdown_active and state != GameState.DOOM:
		print("[MusicManager] Doom countdown active - skipping music change")
		return
	
	var track: AudioStream = null
	var track_name: String = ""
	
	match state:
		GameState.PRE_GAME:
			track = _current_music_set.pre_game_track
			track_name = "Pre-Game"
		GameState.NORMAL_GAME:
			track = _current_music_set.normal_game_track
			track_name = "Normal Game"
		GameState.DOOM:
			track = _current_music_set.doom_track
			track_name = "Doom"
		GameState.OVERWHELM:
			track = _current_music_set.overwhelm_track
			track_name = "Overwhelm"
	
	if not track:
		push_warning("MusicManager: No track available for state: ", state)
		print("[MusicManager] Current music set: ", _current_music_set.set_name)
		print("[MusicManager] Pre-game track: ", _current_music_set.pre_game_track)
		print("[MusicManager] Normal track: ", _current_music_set.normal_game_track)
		print("[MusicManager] Doom track: ", _current_music_set.doom_track)
		print("[MusicManager] Overwhelm track: ", _current_music_set.overwhelm_track)
		return
	
	print("[MusicManager] Playing track: ", track_name, " from set: ", _current_music_set.set_name)
	print("[MusicManager] Track resource: ", track.resource_path if track else "null")
	
	_current_state = state
	_change_music_direct(track, track_name)

func _change_music_direct(new_track: AudioStream, track_name: String) -> void:
	if not _bgm_player:
		return
	
	print("[MusicManager] Changing music directly (no fade)")
	print("[MusicManager] Setting stream to: ", new_track.resource_path if new_track else "null")
	
	# Stop any existing music
	_bgm_player.stop()
	
	# Set the new track
	_bgm_player.stream = new_track
	_bgm_player.volume_db = 0.0  # Set to full volume
	_bgm_player.play()
	
	print("[MusicManager] BGM player stream is now: ", _bgm_player.stream.resource_path if _bgm_player.stream else "null")
	print("[MusicManager] BGM player playing: ", _bgm_player.playing)
	print("[MusicManager] BGM player volume: ", _bgm_player.volume_db)
	
	music_changed.emit(track_name, _current_state)
	print("[MusicManager] Changed to: ", track_name, " (", _current_music_set.set_name, ")")

func _change_music_with_fade(new_track: AudioStream, track_name: String) -> void:
	if not _bgm_player:
		return
	
	# Stop any existing fade tween
	if _fade_tween:
		_fade_tween.kill()
	
	# Store original volume for fade back
	var original_volume = _bgm_player.volume_db
	
	# Create new tween for the transition
	_fade_tween = create_tween()
	_fade_tween.set_parallel(false)  # Sequential tweens
	
	# Fade out current music
	if _bgm_player.playing:
		_fade_tween.tween_property(_bgm_player, "volume_db", -80.0, fade_duration * 0.5)
	
	# Add a callback to change the track after fade out
	_fade_tween.tween_callback(_change_track_and_fade_in.bind(new_track, original_volume))
	
	music_changed.emit(track_name, _current_state)
	print("[MusicManager] Changing to: ", track_name, " (", _current_music_set.set_name, ")")

func _change_track_and_fade_in(new_track: AudioStream, original_volume: float) -> void:
	if not _bgm_player:
		return
	
	# Stop any currently playing music
	_bgm_player.stop()
	
	# Change track
	_bgm_player.stream = new_track
	_bgm_player.volume_db = -80.0
	_bgm_player.play()
	
	print("[MusicManager] Set stream to: ", new_track.resource_path if new_track else "null")
	print("[MusicManager] BGM player stream is now: ", _bgm_player.stream.resource_path if _bgm_player.stream else "null")
	
	# Fade in new track
	if _fade_tween:
		_fade_tween.tween_property(_bgm_player, "volume_db", original_volume, fade_duration * 0.5)

func get_current_music_set() -> MusicSet:
	return _current_music_set

func get_current_state() -> GameState:
	return _current_state

func add_music_set(music_set: MusicSet) -> void:
	music_sets.append(music_set)

func remove_music_set(set_index: int) -> void:
	if set_index >= 0 and set_index < music_sets.size():
		music_sets.remove_at(set_index)

func clear_music_sets() -> void:
	music_sets.clear()
	_current_music_set = null

# Force take control of the BGM player
func force_take_control() -> void:
	if not _bgm_player:
		push_warning("MusicManager: No BGM player to take control of")
		return
	
	print("[MusicManager] Taking control of BGM player")
	print("[MusicManager] Current BGM stream: ", _bgm_player.stream.resource_path if _bgm_player.stream else "null")
	print("[MusicManager] BGM player playing: ", _bgm_player.playing)
	
	# Stop any existing music
	_bgm_player.stop()
	
	# If we have a music set selected, start with pre-game music
	if _current_music_set:
		play_state_music(GameState.PRE_GAME)

# Debug method to test direct stream setting
func test_direct_stream(track: AudioStream) -> void:
	# Try to find BGM player if not already found
	if not _bgm_player:
		print("[MusicManager] No BGM player cached, trying to find one...")
		_bgm_player = _find_bgm_player()
	
	if not _bgm_player:
		push_warning("MusicManager: No BGM player for direct stream test")
		return
	
	print("[MusicManager] Testing direct stream setting")
	print("[MusicManager] Setting stream to: ", track.resource_path if track else "null")
	
	_bgm_player.stop()
	_bgm_player.stream = track
	_bgm_player.volume_db = 0.0
	_bgm_player.play()
	
	print("[MusicManager] BGM player stream is now: ", _bgm_player.stream.resource_path if _bgm_player.stream else "null")
	print("[MusicManager] BGM player playing: ", _bgm_player.playing)

# Public method to manually initialize
func manual_initialize() -> void:
	print("[MusicManager] Manual initialization called")
	_ready()

# Public method to manually set BGM player
func set_bgm_player(bgm_player: AudioStreamPlayer) -> void:
	print("[MusicManager] Manually setting BGM player: ", bgm_player.name if bgm_player else "null")
	_bgm_player = bgm_player
	if _bgm_player:
		print("[MusicManager] BGM player set successfully")
		# Force take control if we have a music set
		if _current_music_set:
			force_take_control()
	else:
		push_warning("MusicManager: Invalid BGM player provided")

# Public method to set doom countdown state
func set_doom_countdown_active(active: bool) -> void:
	_doom_countdown_active = active
	print("[MusicManager] Doom countdown active: ", active)
	if active:
		# Fade out current music during countdown
		if _bgm_player and _bgm_player.playing:
			if _fade_tween:
				_fade_tween.kill()
			_fade_tween = create_tween()
			_fade_tween.tween_property(_bgm_player, "volume_db", -80.0, 0.5)
			print("[MusicManager] Fading out music for doom countdown")
	else:
		# Resume music after countdown ends
		if _bgm_player and _bgm_player.stream:
			if _fade_tween:
				_fade_tween.kill()
			_fade_tween = create_tween()
			_fade_tween.tween_property(_bgm_player, "volume_db", 0.0, 0.5)
			print("[MusicManager] Resuming music after doom countdown") 
