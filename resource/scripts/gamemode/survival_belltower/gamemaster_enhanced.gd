extends Node

# Enhanced GameMaster.gd – controls round flow for survival maps like "Belltower".
# Integrates with MusicManager for automatic music transitions

signal game_started                             # emitted once bell rings
signal game_over(survived_time_ms, kills)       # emitted when player dies

@export var bell_path: NodePath
@export var player_path: NodePath
@export var ui_timer_label: NodePath
@export var ui_ms_label: NodePath       # optional label to show centiseconds
@export var ui_kills_label: NodePath
@export var ui_doom_label: NodePath       # optional label to show doom countdown seconds
@export var enemy_spawn_zones_path: NodePath # New export variable for enemy spawn zones
@export var bgm_node_path: NodePath = NodePath("env/bgm")  # Path to the BGM AudioStreamPlayer

# Music Manager Integration
@export var music_manager: MusicManager
@export var auto_randomize_music: bool = true

# Overwhelm UI & audio
@export var ui_overwhelm_meter: NodePath  # ProgressBar / TextureProgress showing enemy count
@export var doom_tick_sound: AudioStream  # Sound played every second while doom timer counts
@export var doom_zero_sound: AudioStream  # Sound played when countdown hits zero
@export var in_game_bgm_stream: AudioStream  # BGM to switch to when bell rings (in-game music)

# --- Reaper parameters ---------------------------------------------------
@export var reaper_threshold_speed : float = 100.0 # Speed below which reaper timer counts
@export var reaper_time : float = 2.0              # Seconds before instant death
@export var reaper_color : Color = Color(1,0,0,0.6) # Target screen tint color
@export var ui_reaper_overlay : NodePath           # ColorRect or Control to tint screen
@export var reaper_sound : AudioStream             # Sound played when reaper strikes
@export var overwhelm_bgm_stream : AudioStream      # Optional BGM to play once doom finishes

# Audio fade settings
const BGM_BUS_NAME := "bgm"
var _bgm_bus_idx : int = -1
const BGM_ORIGINAL_DB : float = 0.0
var _bgm_tween : Tween
var _original_bgm_stream : AudioStream = null
var _current_bgm_stream : AudioStream = null # Tracks the music that should play when not in overwhelm

enum State { WARMUP, RUNNING, GAME_OVER }

var _state : State = State.WARMUP
var _start_time_ms : int = 0
var _kills : int = 0
var _ticker : Timer
var _spawn_timer : Timer # New timer for enemy spawning
var _spawn_interval : float = 40.0 # Initial spawn interval of 40 seconds
var _interval_decrease_timer : Timer # Timer to decrease spawn interval
var _player_connected : bool = false

# Helper to find a descendant that has any of the given signals
func _find_node_with_signal(root: Node, signal_names: Array[String]) -> Node:
	if not root:
		return null
	for sig in signal_names:
		if root.has_signal(sig):
			return root
	# search children
	for child in root.get_children():
		var found = _find_node_with_signal(child, signal_names)
		if found:
			return found
	return null

# --- Overwhelm parameters -----------------------------------------------
@export var overwhelm_limit : int = 30   # Max enemies allowed before doom
@export var doom_countdown : float = 5.0 # Seconds before charge starts
@export var overwhelm_speed_multiplier : float = 6.0 # Speed multiplier applied to enemies during overwhelm
@export var global_enemy_cap : int = 80   # Hard limit on number of enemies in the scene
@export var max_spawners : int = 3        # Maximum concurrent enemy spawners
@export var default_wave_pool: Resource # Optional EnemyWavePool resource; left untyped for editor compatibility
var _doom_timer : Timer
var _doom_pending : bool = false
var _doom_active  : bool = false

var _tick_timer : Timer         # 1-second interval for countdown beeps
var _tick_player : AudioStreamPlayer
var _zero_player : AudioStreamPlayer
# Reaper internals
var _reaper_elapsed : float = 0.0
var _overlay_original_color : Color = Color(0,0,0,0)
const _UPS_FACTOR : float = 39.37 # meters/sec to Quake-style units/sec

# Overwhelm meter pulse helpers
var _meter_original_modulate : Color = Color(1,1,1,1)
var _meter_pulse_tween : Tween
# Doom label animation helpers
var _prev_doom_value : int = -999
var _doom_label_tween : Tween

# --- Wave control ---------------------------------------------------------
var _wave : int = 0           # Current wave number (first wave = 1)
# --- Simple kill tracking -----------------------------------------------
var _enemy_set : Dictionary = {}
var _prev_enemy_count : int = -1
var _last_wave_time_ms : int = 0
var _extra_wave_timer : Timer
var _extra_wave_pending : bool = false

func _ready():
	_ticker = Timer.new()
	_ticker.wait_time = 0.05   # update 20 Hz for smooth ms display
	_ticker.timeout.connect(_on_tick)
	add_child(_ticker)

	_spawn_timer = Timer.new()
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)

	_interval_decrease_timer = Timer.new()
	_interval_decrease_timer.wait_time = 60.0 # Decrease spawn interval every 60 seconds
	_interval_decrease_timer.timeout.connect(_on_interval_decrease_timer_timeout)
	add_child(_interval_decrease_timer)

	# Extra wave timer (spawns an early wave at the next 10s boundary if enemies are zero)
	_extra_wave_timer = Timer.new()
	_extra_wave_timer.one_shot = true
	_extra_wave_timer.timeout.connect(_on_extra_wave_timer_timeout)
	add_child(_extra_wave_timer)

	# Initialize overwhelm system
	_doom_timer = Timer.new()
	_doom_timer.one_shot = true
	_doom_timer.wait_time = doom_countdown
	_doom_timer.timeout.connect(_on_doom_timer_timeout)
	add_child(_doom_timer)

	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_on_tick_timer_timeout)
	add_child(_tick_timer)

	_tick_player = AudioStreamPlayer.new()
	_tick_player.stream = doom_tick_sound
	_tick_player.bus = "sfx"
	add_child(_tick_player)

	_zero_player = AudioStreamPlayer.new()
	_zero_player.stream = doom_zero_sound
	_zero_player.bus = "sfx"
	add_child(_zero_player)

	# Initialize audio fade system
	_bgm_bus_idx = AudioServer.get_bus_index(BGM_BUS_NAME)
	if _bgm_bus_idx == -1:
		push_warning("BGM bus not found: ", BGM_BUS_NAME)

	# Initialize overwhelm meter
	if ui_overwhelm_meter != NodePath("") and has_node(ui_overwhelm_meter):
		var meter = get_node(ui_overwhelm_meter)
		if meter.has_method("set_value"):
			meter.set_value(0)
			_meter_original_modulate = meter.modulate

	# Initialize doom label
	if ui_doom_label != NodePath("") and has_node(ui_doom_label):
		var doom_label = get_node(ui_doom_label)
		if doom_label.has_method("set_text"):
			doom_label.set_text("")

	# Initialize reaper overlay
	if ui_reaper_overlay != NodePath("") and has_node(ui_reaper_overlay):
		var overlay = get_node(ui_reaper_overlay)
		if overlay.has_method("set_color"):
			_overlay_original_color = overlay.color

	# Initialize UI
	_update_ui()

	# Connect to scene tree for player detection
	get_tree().node_added.connect(_on_node_added)

	# Bell hookup
	if bell_path != NodePath("") and has_node(bell_path):
		var bell = get_node(bell_path)
		if bell.has_signal("bell_rang"):
			bell.connect("bell_rang", _on_bell_rang)
		else:
			push_warning("Bell has no bell_rang signal – game will not start")
	else:
		push_warning("bell_path not assigned")

	connect("game_started", _on_game_started) # Connect to game_started signal
	# Defer player signal hookup to ensure entire scene tree is ready
	call_deferred("_setup_player_connection")
	
	# Initialize music manager if available
	_initialize_music_manager()

# -------- State transitions -------------------------------------------------
func _switch_to_in_game_bgm():
	print("[GameMaster] _switch_to_in_game_bgm called")
	
	# Use MusicManager if available, otherwise fall back to legacy system
	if music_manager:
		print("[GameMaster] Using MusicManager for in-game music")
		print("[GameMaster] MusicManager current set: ", music_manager.get_current_music_set().set_name if music_manager.get_current_music_set() else "null")
		print("[GameMaster] MusicManager current state: ", music_manager.get_current_state())
		music_manager.play_state_music(MusicManager.GameState.NORMAL_GAME)
	else:
		print("[GameMaster] Using legacy BGM system")
		await get_tree().create_timer(0.5).timeout
		var bgm_node = get_node_or_null(bgm_node_path)
		print("[GameMaster] BGM node found: ", bgm_node)
		print("[GameMaster] In-game BGM stream: ", in_game_bgm_stream.resource_path if in_game_bgm_stream else "null")
		if bgm_node and bgm_node is AudioStreamPlayer:
			bgm_node.stream = in_game_bgm_stream
			bgm_node.play()
			_current_bgm_stream = in_game_bgm_stream
			print("[GameMaster] Switched to in-game BGM: ", in_game_bgm_stream.resource_path)
		else:
			print("[GameMaster] Unable to find BGM player at env/bgm")

func _initialize_music_manager():
	if music_manager:
		print("[GameMaster] Music manager found - initializing music system")
		print("[GameMaster] MusicManager path: ", music_manager.get_path())
		print("[GameMaster] MusicManager ready: ", music_manager.get("_ready_called") if music_manager.has_method("_ready") else "unknown")
		
		# Manually call _ready if it hasn't been called yet
		if not music_manager.has_method("_ready") or not music_manager.get("_ready_called"):
			print("[GameMaster] Manually initializing MusicManager")
			music_manager._ready()
			music_manager.set("_ready_called", true)
		
		# Force manual initialization
		print("[GameMaster] Forcing MusicManager manual initialization")
		music_manager.manual_initialize()
		
		# Try to manually find and set BGM player
		print("[GameMaster] Attempting to manually find BGM player...")
		var bgm_player = _find_bgm_player_for_music_manager()
		if bgm_player:
			print("[GameMaster] Found BGM player manually: ", bgm_player.name)
			music_manager.set_bgm_player(bgm_player)
		else:
			print("[GameMaster] Could not find BGM player manually")
	else:
		print("[GameMaster] No music manager assigned - using legacy BGM system")

func _find_bgm_player_for_music_manager() -> AudioStreamPlayer:
	print("[GameMaster] Searching for BGM player from GameMaster...")
	
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
		if node and node is AudioStreamPlayer:
			print("[GameMaster] Found BGM player at: ", path)
			return node
	
	# If not found, look for any AudioStreamPlayer in the scene
	print("[GameMaster] Searching for AudioStreamPlayer nodes in scene...")
	var all_nodes = get_tree().get_nodes_in_group("")
	var audio_players = []
	
	for node in all_nodes:
		if node is AudioStreamPlayer:
			audio_players.append(node)
			print("[GameMaster] Found AudioStreamPlayer: ", node.name, " at path: ", node.get_path())
	
	if audio_players.size() > 0:
		print("[GameMaster] Using first AudioStreamPlayer found: ", audio_players[0].name)
		return audio_players[0]
	
	# Also check for nodes in the "bgm" group
	var bgm_group_nodes = get_tree().get_nodes_in_group("bgm")
	print("[GameMaster] Nodes in 'bgm' group: ", bgm_group_nodes.size())
	for node in bgm_group_nodes:
		print("[GameMaster] BGM group node: ", node.name, " (", node.get_class(), ")")
		if node is AudioStreamPlayer:
			print("[GameMaster] Found BGM player in group: ", node.name)
			return node
	
	print("[GameMaster] No BGM player found!")
	return null

func _on_bell_rang():
	if _state != State.WARMUP:
		return
	print("[GameMaster] Bell rang - switching to in-game BGM")
	_state = State.RUNNING
	_start_time_ms = Time.get_ticks_msec()
	_kills = 0
	_ticker.start()
	# Switch to in-game BGM after a short delay (like BellController did)
	if music_manager:
		call_deferred("_switch_to_in_game_bgm")
	elif in_game_bgm_stream:
		call_deferred("_switch_to_in_game_bgm")
	emit_signal("game_started")
	_update_ui()

func _on_game_started():
	# Start spawning enemies
	if enemy_spawn_zones_path != NodePath("") and has_node(enemy_spawn_zones_path):
		var spawn_zones_node = get_node(enemy_spawn_zones_path)
		if spawn_zones_node.get_child_count() > 0:
			_spawn_timer.wait_time = 0.0 # Trigger first wave immediately
			_on_spawn_timer_timeout()    # Wave 1
			# Prepare timer for subsequent waves (until wave 5)
			if _wave < 5:
				_spawn_timer.wait_time = _spawn_interval
				_spawn_timer.start()
			_interval_decrease_timer.start()
		else:
			push_warning("No Area3D nodes found under enemy_spawn_zones_path")
	else:
		push_warning("enemy_spawn_zones_path not assigned or not found")

func _on_spawn_timer_timeout():
	_last_wave_time_ms = Time.get_ticks_msec()
	_wave += 1
	# Count existing spawners
	var current_spawners := get_tree().get_nodes_in_group("enemy_spawner").size()
	var spawner_slots_left := max_spawners - current_spawners
	if spawner_slots_left <= 0:
		print("[GameMaster] Max spawners reached (", current_spawners, ") – no new spawners this wave")
		# Reschedule but skip spawn
		_spawn_timer.wait_time = _spawn_interval
		_spawn_timer.start()
		return

	var spawn_zones_node = get_node(enemy_spawn_zones_path)
	var spawn_areas : Array = []
	for child in spawn_zones_node.get_children():
		if child is Area3D:
			spawn_areas.append(child)

	# Determine how many spawners and what cap this wave should use
	var spawners_this_wave : int
	var cap_this_wave : int
	if _wave < 3:
		spawners_this_wave = 2
		cap_this_wave = 2
	elif _wave < 5:
		spawners_this_wave = 2
		cap_this_wave = 3
	else:
		spawners_this_wave = 3
		cap_this_wave = 3

	# Determine how many spawners can actually be added respecting cap
	var remaining_allowed := global_enemy_cap - get_tree().get_nodes_in_group("enemy").size()
	# each spawner can at most create enemy_cap enemies, so approximate required spawners
	var max_spawners_allowed := int(ceil(float(remaining_allowed) / float(cap_this_wave)))
	spawners_this_wave = min(spawners_this_wave, spawner_slots_left)
	if spawners_this_wave <= 0:
		return

	_spawn_spawners(spawn_areas, spawners_this_wave, cap_this_wave)

	# Schedule next wave (always – waves continue indefinitely)
	_spawn_timer.wait_time = _spawn_interval
	_spawn_timer.start()

func _on_interval_decrease_timer_timeout():
	if _spawn_interval > 20.0:
		_spawn_interval = max(20.0, _spawn_interval - 5.0)
		print("Spawn interval decreased to: ", _spawn_interval)
	else:
		_interval_decrease_timer.stop() # Stop decreasing once it hits 20 seconds

func register_kill(count:int=1):
	if _state == State.RUNNING:
		_kills += count
		_update_ui()
		# If overwhelm active, notify hook controllers to refill charges
		if _doom_active:
			for hook in get_tree().get_nodes_in_group("hook_controller"):
				if hook.has_method("recharge_charges"):
					hook.recharge_charges()

func _process(delta):
	if _state != State.RUNNING:
		return
	var current_enemies := get_tree().get_nodes_in_group("enemy")
	# Populate dictionary with current enemy instance_ids
	var new_set : Dictionary = {}
	for e in current_enemies:
		new_set[e.get_instance_id()] = true
	# Detect removed enemies (killed or freed)
	for id in _enemy_set.keys():
		if not new_set.has(id):
			register_kill(1)
	var enemy_count := current_enemies.size()
	_enemy_set = new_set
	_update_overwhelm_ui(enemy_count)

	# Schedule an extra wave at the next 10s boundary if enemies reached zero
	# and the boundary occurs before the next scheduled wave time.
	if enemy_count == 0 and _prev_enemy_count != 0 and not _extra_wave_pending:
		# Compute next 10-second boundary (relative to game start)
		var now_ms : int = Time.get_ticks_msec()
		var elapsed_s : float = float(now_ms - _start_time_ms) / 1000.0
		var next_boundary_s : float = ceil(elapsed_s / 10.0) * 10.0
		var boundary_ms : int = _start_time_ms + int(next_boundary_s * 1000.0)
		# Compute next scheduled wave time based on last wave spawn and current interval
		var next_wave_ms : int = _last_wave_time_ms + int(_spawn_interval * 1000.0)
		# Only schedule if boundary strictly before next scheduled wave
		if boundary_ms < next_wave_ms:
			var wait_ms : int = max(0, boundary_ms - now_ms)
			if wait_ms > 0:
				_extra_wave_pending = true
				_extra_wave_timer.wait_time = float(wait_ms) / 1000.0
				_extra_wave_timer.start()

	_prev_enemy_count = enemy_count

	if not _doom_active:
		if enemy_count >= overwhelm_limit and not _doom_pending:
			_start_doom_countdown()
		elif _doom_pending and enemy_count < overwhelm_limit:
			_cancel_doom_countdown()
	else:
		_update_reaper(delta)

# Starts the doom countdown when overwhelm threshold is reached
func _start_doom_countdown():
	if _doom_pending or _doom_active:
		return  # Already counting or active
	_doom_pending = true
	print("[GameMaster] OVERWHELM – starting doom countdown (", doom_countdown, "s)")
	_doom_timer.start()
	_tick_timer.start()
	
	# Notify MusicManager about doom countdown
	if music_manager:
		music_manager.set_doom_countdown_active(true)
	
	# Cache meter's original modulate color for pulsing
	if ui_overwhelm_meter != NodePath("") and has_node(ui_overwhelm_meter):
		var m = get_node(ui_overwhelm_meter)
		if m is CanvasItem:
			_meter_original_modulate = (m as CanvasItem).modulate
	
	# Play initial tick immediately
	_on_tick_timer_timeout()

# Cancels the doom countdown if enemy count drops below threshold
func _cancel_doom_countdown():
	if not _doom_pending:
		return
	print("[GameMaster] Enemy count back under limit – cancelling doom countdown")
	_doom_pending = false
	_doom_timer.stop()
	_doom_timer.wait_time = doom_countdown
	_tick_timer.stop()
	_update_doom_label(-1) # Clear label
	
	# Notify MusicManager that doom countdown ended
	if music_manager:
		music_manager.set_doom_countdown_active(false)
	
	print("[GameMaster] Doom countdown cancelled")

# Called when doom countdown expires
func _on_doom_timer_timeout():
	print("[GameMaster] Doom countdown expired – enemies charging!")
	_doom_active = true
	_doom_pending = false
	_tick_timer.stop()
	
	# Notify MusicManager that doom countdown ended
	if music_manager:
		music_manager.set_doom_countdown_active(false)
	
	# Apply overwhelm effects to all existing enemies
	var player_node: Node3D = null
	if player_path != NodePath("") and has_node(player_path):
		player_node = get_node(player_path)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_apply_overwhelm_to_enemy(enemy, player_node)
	
	# Switch to overwhelm music
	if music_manager:
		music_manager.play_state_music(MusicManager.GameState.DOOM)
	elif overwhelm_bgm_stream:
		# Legacy overwhelm music handling
		var bgm_node = get_node_or_null(bgm_node_path)
		if bgm_node and bgm_node is AudioStreamPlayer:
			bgm_node.stream = overwhelm_bgm_stream
			bgm_node.play()
	
	# Play zero sound
	if doom_zero_sound and _zero_player:
		_zero_player.play()
	
	_update_doom_label(0)

# Called when player dies
func _on_player_died():
	if _state != State.RUNNING:
		return
	_state = State.GAME_OVER
	# Stop timers that drive UI/time and spawning
	if _ticker:
		_ticker.stop()
	if _spawn_timer:
		_spawn_timer.stop()
	if _interval_decrease_timer:
		_interval_decrease_timer.stop()
	# Stop doom countdown if active and clear flags/UI
	if _doom_timer and not _doom_timer.is_stopped():
		_doom_timer.stop()
	if _tick_timer and not _tick_timer.is_stopped():
		_tick_timer.stop()
	_doom_active = false
	_doom_pending = false
	_update_doom_label(-1)
	
	# Switch back to pre-game music
	if music_manager:
		music_manager.play_state_music(MusicManager.GameState.PRE_GAME)
	
	var elapsed_ms := Time.get_ticks_msec() - _start_time_ms
	emit_signal("game_over", elapsed_ms, _kills)
	_show_game_over(elapsed_ms)

# -------- Timer & UI --------------------------------------------------------
func _on_tick():
	_update_ui()

func _update_ui():
	if _state == State.RUNNING:
		var elapsed := Time.get_ticks_msec() - _start_time_ms
		var minutes := int(elapsed / 60000)
		var seconds := int((elapsed % 60000) / 1000)
		var centi   := int((elapsed % 1000) / 10) # two-digit fraction

		# Update main (MM:SS)
		if ui_timer_label != NodePath("") and has_node(ui_timer_label):
			var time_text := str(minutes).pad_zeros(2) + ":" + str(seconds).pad_zeros(2)
			var rt := get_node(ui_timer_label) as RichTextLabel
			if rt:
				rt.clear()
				rt.append_text(time_text)
			else:
				(get_node(ui_timer_label) as Label).text = time_text

		# Update centiseconds label
		if ui_ms_label != NodePath("") and has_node(ui_ms_label):
			(get_node(ui_ms_label) as Label).text = "." + str(centi).pad_zeros(2)

	if ui_kills_label != NodePath("") and has_node(ui_kills_label):
		(get_node(ui_kills_label) as Label).text = str(_kills)

# -------- Helpers -----------------------------------------------------------
func _show_game_over(elapsed_ms:int):
	var minutes := int(elapsed_ms / 60000)
	var seconds := int((elapsed_ms % 60000) / 1000)
	var centi   := int((elapsed_ms % 1000) / 10)
	var formatted := str(minutes).pad_zeros(2)+":"+str(seconds).pad_zeros(2)+"."+str(centi).pad_zeros(2)
	print("[GameMaster] GAME OVER – survived ", formatted, "  kills: ", _kills) 

# -------- Spawn placement helpers ---------------------------------------------------
@export var spawner_min_spacing : float = 6.0
@export var spawner_edge_padding : float = 0.5
@export var spawner_sample_attempts : int = 12

func _get_random_point_in_area(area: Area3D) -> Vector3:
	var local : Vector3 = Vector3.ZERO
	var shape : Shape3D = null
	for c in area.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape:
			shape = (c as CollisionShape3D).shape
			break
	if shape is BoxShape3D:
		var half : Vector3 = ((shape as BoxShape3D).size * 0.5) - Vector3.ONE * spawner_edge_padding
		half = Vector3(max(half.x, 0.1), max(half.y, 0.1), max(half.z, 0.1))
		local = Vector3(
			randf_range(-half.x, half.x),
			0.0,
			randf_range(-half.z, half.z)
		)
	elif shape is SphereShape3D:
		var r : float = max((shape as SphereShape3D).radius - spawner_edge_padding, 0.1)
		var ang : float = randf() * TAU
		var dist : float = sqrt(randf()) * r
		local = Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
	else:
		# Fallback: use a radius based on area scale
		var r2 : float = max(max(area.scale.x, area.scale.z) * 2.0 - spawner_edge_padding, 0.5)
		var ang2 : float = randf() * TAU
		var dist2 : float = sqrt(randf()) * r2
		local = Vector3(cos(ang2) * dist2, 0.0, sin(ang2) * dist2)
	return area.to_global(local)

func _pick_spawner_positions(spawn_areas:Array, amount:int) -> Array:
	var positions : Array = []
	for i in range(amount):
		var placed := false
		for attempt in range(spawner_sample_attempts):
			var area : Area3D = spawn_areas[randi() % spawn_areas.size()]
			var candidate : Vector3 = _get_random_point_in_area(area)
			var ok := true
			for p in positions:
				if (p as Vector3).distance_to(candidate) < spawner_min_spacing:
					ok = false
					break
			if ok:
				positions.append(candidate)
				placed = true
				break
		if not placed:
			# Fallback: jitter around a random area's origin with enforced spacing
			var area2 : Area3D = spawn_areas[randi() % spawn_areas.size()]
			var base : Vector3 = area2.global_transform.origin
			var angle : float = randf() * TAU
			var dist : float = spawner_min_spacing * (1.0 + float(i) * 0.15)
			var fallback_pos : Vector3 = base + Vector3(cos(angle), 0.0, sin(angle)) * dist
			positions.append(fallback_pos)
	return positions

# -------- Spawner helper ---------------------------------------------------
func _spawn_spawners(spawn_areas:Array, amount:int, enemy_cap:int):
	# Global enemy cap guard – skip spawning if cap reached
	var current_total : int = get_tree().get_nodes_in_group("enemy").size()
	if current_total >= global_enemy_cap:
		print("[GameMaster] Global enemy cap reached (", current_total, "/", global_enemy_cap, ") – skipping this wave")
		return
	if spawn_areas.is_empty():
		push_warning("No spawn areas available to spawn enemies.")
		return
	var positions : Array = _pick_spawner_positions(spawn_areas, amount)
	for i in range(positions.size()):
		var spawner_scene = load("res://resource/entities/enemy_spawner.tscn")
		var spawner_instance = spawner_scene.instantiate()
		spawner_instance.spawn_count = enemy_cap
		# Apply default wave pool if provided
		if default_wave_pool:
			spawner_instance.wave_pool = default_wave_pool
		spawner_instance.global_transform.origin = positions[i]
		get_tree().current_scene.add_child(spawner_instance)
		print("[Wave %d] Spawned enemy spawner at %s with cap %d" % [_wave, str(positions[i]), enemy_cap]) 

func _on_tick_timer_timeout():
	if doom_tick_sound and _tick_player:
		_tick_player.play()
	# Update doom label each second
	_update_doom_label(_doom_timer.time_left)
	# Pulse overwhelm meter red
	_pulse_overwhelm_meter()

func _on_extra_wave_timer_timeout():
	# Spawn an extra wave using the same logic as normal waves
	_extra_wave_pending = false
	_on_spawn_timer_timeout()

# Overwhelm UI update
func _update_overwhelm_ui(count:int):
	if ui_overwhelm_meter == NodePath("") or not has_node(ui_overwhelm_meter):
		return
	var n = get_node(ui_overwhelm_meter)
	if "value" in n: # ProgressBar/TextureProgress
		n.max_value = overwhelm_limit
		n.value = clamp(count, 0, overwhelm_limit)
	elif n is Label:
		(n as Label).text = "%d/%d" % [count, overwhelm_limit] 

# ---------------- Doom label helpers ---------------------
func _update_doom_label(time_left: float):
	if ui_doom_label == NodePath("") or not has_node(ui_doom_label):
		return
	var lbl: CanvasItem = get_node(ui_doom_label) as CanvasItem
	var text: String = ""
	if time_left < 0:
		text = ""
	else:
		text = str(int(ceil(max(time_left,0))))
	# Animate on change
	var int_val: int = text.to_int() if text != "" else -1
	if int_val != _prev_doom_value:
		_prev_doom_value = int_val
		_animate_doom_label(lbl)

	# Apply to RichTextLabel or Label
	if lbl is RichTextLabel:
		(lbl as RichTextLabel).clear()
		(lbl as RichTextLabel).append_text(text)
	elif lbl is Label:
		(lbl as Label).text = text

func _animate_doom_label(lbl: CanvasItem):
	if _doom_label_tween:
		_doom_label_tween.kill()
	_doom_label_tween = create_tween()
	_doom_label_tween.tween_property(lbl, "scale", Vector2(1.5, 1.5), 0.1)
	_doom_label_tween.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.1)

func _pulse_overwhelm_meter():
	if ui_overwhelm_meter == NodePath("") or not has_node(ui_overwhelm_meter):
		return
	var meter = get_node(ui_overwhelm_meter)
	if _meter_pulse_tween:
		_meter_pulse_tween.kill()
	_meter_pulse_tween = create_tween()
	_meter_pulse_tween.tween_property(meter, "modulate", Color.RED, 0.2)
	_meter_pulse_tween.tween_property(meter, "modulate", _meter_original_modulate, 0.2)

# ---------------- Reaper system ---------------------
func _update_reaper(delta: float):
	var player = get_node_or_null(player_path)
	if not player or not player.has_method("get_velocity"):
		return
	
	var velocity: Vector3 = player.get_velocity()
	var speed: float = velocity.length()
	
	if speed < reaper_threshold_speed:
		_reaper_elapsed += delta
		if _reaper_elapsed >= reaper_time:
			_reaper_strike()
	else:
		_reaper_elapsed = 0.0
	
	# Update overlay
	if ui_reaper_overlay != NodePath("") and has_node(ui_reaper_overlay):
		var overlay = get_node(ui_reaper_overlay)
		if overlay.has_method("set_color"):
			var progress := _reaper_elapsed / reaper_time
			var color := _overlay_original_color.lerp(reaper_color, progress)
			overlay.set_color(color)

func _reaper_strike():
	print("[GameMaster] REAPER STRIKE!")
	if reaper_sound:
		var player = AudioStreamPlayer.new()
		player.stream = reaper_sound
		player.bus = "sfx"
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)
	
	# Kill the player
	var player_node = get_node_or_null(player_path)
	if player_node and player_node.has_method("die"):
		player_node.die()

# ---------------- Player connection ---------------------
func _setup_player_connection():
	if _player_connected:
		return
	var player_root : Node = null
	if player_path != NodePath("") and has_node(player_path):
		player_root = get_node(player_path)
	else:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_root = players[0]
	if player_root == null:
		push_warning("Unable to locate player for death signal hookup")
		return
	var target = _find_node_with_signal(player_root, ["died", "player_died"])
	if target:
		if target.has_signal("died") and not target.is_connected("died", Callable(self, "_on_player_died")):
			target.connect("died", _on_player_died)
			print("[GameMaster] Connected to 'died' signal from "+str(target.get_path()))
		elif target.has_signal("player_died") and not target.is_connected("player_died", Callable(self, "_on_player_died")):
			target.connect("player_died", _on_player_died)
			print("[GameMaster] Connected to 'player_died' signal from "+str(target.get_path()))
		_player_connected = true
	else:
		push_warning("Player "+player_root.name+" has no descendant emitting death signals")

func _on_node_added(node: Node):
	if _player_connected:
		return
	if node.get_path() == player_path:
		_setup_player_connection()
	
	# Handle overwhelm for late-spawned enemies
	if not _doom_active:
		return
	# Ignore non-combat nodes like spawners – they won't define boost_speed
	if not node.has_method("boost_speed"):
		return

	# Hook kill tracking
	if node.is_in_group("enemy"):
		node.tree_exited.connect(_on_enemy_node_exited.bind(node))

	var player_node: Node3D = null
	if player_path != NodePath("") and has_node(player_path):
		player_node = get_node(player_path)

	# Defer the overwhelm application to allow the enemy's _ready() to run first
	call_deferred("_apply_overwhelm_to_enemy", node, player_node)

# Apply overwhelm effects (boost + forced chase) to a single enemy
func _apply_overwhelm_to_enemy(enemy: Node, player_node: Node3D = null):
	if enemy == null:
		return
	if enemy.has_method("boost_speed"):
		enemy.boost_speed(overwhelm_speed_multiplier)

	if enemy.has_node("AI"):
		var ai = enemy.get_node("AI")
		if ai:
			# Force awareness and chase behavior
			ai.current_awareness = ai.awareness_threshold
			ai.player_in_range = true
			ai.player = player_node
			if ai.has_method("change_state"):
				ai.change_state(ai.States.CHASE)
		print(" -- Enemy ", enemy.name, " overwhelmed and set to CHASE")
	else:
		print(" -- Enemy ", enemy.name, " overwhelmed but has no AI node")

# Called when an enemy node exits tree (i.e., is killed/freed)
func _on_enemy_node_exited(enemy: Node):
	if enemy == null:
		return
	register_kill(1)
	print("[GameMaster] Enemy freed -> kill registered")

# ---------------- Public API -----------------
## Returns whether the doom/overwhelm state is currently active
func is_doom_active() -> bool:
	return _doom_active 
