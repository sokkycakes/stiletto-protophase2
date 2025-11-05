extends Node

# GameMaster.gd – controls round flow for survival maps like "Belltower".
# Attach to a Node inside the map scene. Wire bell/player/UI paths via inspector.

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

func _ready():
	_ticker = Timer.new()
	_ticker.wait_time = 0.05   # update 20 Hz for smooth ms display
	_ticker.timeout.connect(_on_tick)
	add_child(_ticker)

	# Initialize spawn timer
	_spawn_timer = Timer.new()
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)

	# Initialize interval decrease timer
	_interval_decrease_timer = Timer.new()
	_interval_decrease_timer.wait_time = 30.0 # Decrease every 30 seconds
	_interval_decrease_timer.timeout.connect(_on_interval_decrease_timeout)
	add_child(_interval_decrease_timer)

	# Doom timer setup
	_doom_timer = Timer.new()
	_doom_timer.one_shot = true
	_doom_timer.wait_time = doom_countdown
	_doom_timer.timeout.connect(_on_doom_timer_timeout)
	add_child(_doom_timer)

	# Tick timer and audio player for doom countdown
	_tick_timer = Timer.new()
	_tick_timer.wait_time = 1.0
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_on_tick_timer_timeout)
	add_child(_tick_timer)

	_tick_player = AudioStreamPlayer.new()
	_tick_player.stream = doom_tick_sound
	add_child(_tick_player)

	# Cache bgm bus index and original volume
	_bgm_bus_idx = AudioServer.get_bus_index(BGM_BUS_NAME)
	if _bgm_bus_idx >= 0:
		pass # No longer caching original volume

	# Cache original BGM stream if autoload present
	var bgm = get_node_or_null(bgm_node_path)
	if bgm:
		if bgm and "stream" in bgm:
			_original_bgm_stream = bgm.stream
			_current_bgm_stream = bgm.stream

	# Add to global group for other systems to query (e.g., grappling hook)
	add_to_group("gamemaster")

	_zero_player = AudioStreamPlayer.new()
	_zero_player.stream = doom_zero_sound
	add_child(_zero_player)

	# Listen for new nodes so we can apply overwhelm effects to late spawns
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

# -------- State transitions -------------------------------------------------
func _switch_to_in_game_bgm():
	print("[GameMaster] _switch_to_in_game_bgm called")
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

func _on_bell_rang():
	if _state != State.WARMUP:
		return
	print("[GameMaster] Bell rang - switching to in-game BGM: ", in_game_bgm_stream.resource_path if in_game_bgm_stream else "null")
	_state = State.RUNNING
	_start_time_ms = Time.get_ticks_msec()
	_kills = 0
	_ticker.start()
	# Switch to in-game BGM after a short delay (like BellController did)
	if in_game_bgm_stream:
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

func _on_interval_decrease_timeout():
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
	# Fade BGM down to -80 dB over 2 seconds (completes by count 3)
	_fade_bgm_to(-80.0, 2.0)
	# Cache meter's original modulate color for pulsing
	if ui_overwhelm_meter != NodePath("") and has_node(ui_overwhelm_meter):
		var m = get_node(ui_overwhelm_meter)
		if m is CanvasItem:
			_meter_original_modulate = (m as CanvasItem).modulate
	# play initial tick immediately
	_on_tick_timer_timeout()

func _cancel_doom_countdown():
	print("[GameMaster] Enemy count back under limit – cancelling doom countdown")
	_doom_pending = false
	_doom_timer.stop()
	_doom_timer.wait_time = doom_countdown
	_tick_timer.stop()
	_update_doom_label(-1) # Clear label

	# Restore BGM volume to normal level
	_fade_bgm_to(BGM_ORIGINAL_DB, 0.6)

	# Only swap the stream back if it was actually changed (prevents restart)
	var bgm = get_node_or_null(bgm_node_path)
	if bgm and _current_bgm_stream and bgm.stream != _current_bgm_stream:
		bgm.stream = _current_bgm_stream
		if not bgm.playing:
			bgm.play()

	# Resume hook recharge
	for hook in get_tree().get_nodes_in_group("hook_controller"):
		if hook.has_method("resume_recharge"):
			hook.resume_recharge()

func _on_doom_timer_timeout():
	print("[GameMaster] Doom countdown expired – enemies charging!")
	_doom_active = true
	_doom_pending = false
	_tick_timer.stop()
	# Apply overwhelm effects to all existing enemies
	var player_node: Node3D = null
	if player_path != NodePath("") and has_node(player_path):
		player_node = get_node(player_path)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_apply_overwhelm_to_enemy(enemy, player_node)

	# Switch to overwhelm BGM if provided
	var bgm_node: Node = null
	# Try to locate BGM node under env in current scene
	bgm_node = get_node_or_null(bgm_node_path)

	if overwhelm_bgm_stream and bgm_node:
		# Force-switch to the overwhelm track
		bgm_node.stop()               # halt any currently playing music
		bgm_node.stream = overwhelm_bgm_stream
		# Force the stream to take effect
		bgm_node.stream_paused = false
		bgm_node.process_mode = Node.PROCESS_MODE_INHERIT
		bgm_node.play()               # start the new track immediately
		# Fade bus back up to original volume over 1 second
		AudioServer.set_bus_volume_db(_bgm_bus_idx, 0.0) # Directly set to 0 dB
	else:
		# No custom overwhelm track; keep the bus muted so the previous track stays silent
		AudioServer.set_bus_volume_db(_bgm_bus_idx, 0.0) # Directly set to 0 dB

	# Play zero sound
	if doom_zero_sound and _zero_player:
		_zero_player.play()

	_update_doom_label(0)


func _on_player_died():
	if _state != State.RUNNING:
		return
	# Stop doom timer if active
	if _doom_timer and _doom_timer.is_stopped() == false:
		_doom_timer.stop()
	if _tick_timer and _tick_timer.is_stopped() == false:
		_tick_timer.stop()
	_doom_active = false
	_doom_pending = false
	# Restore BGM volume/state if it was lowered by the doom mechanic
	if _bgm_bus_idx >= 0:
		_fade_bgm_to(BGM_ORIGINAL_DB, 0.5)
	# If we switched to the overwhelm music stream, revert to the original
	var bgm = get_node_or_null(bgm_node_path)
	if bgm and _current_bgm_stream:
		if bgm:
			bgm.stream = _current_bgm_stream
			if not bgm.playing:
				bgm.play()
	_state = State.GAME_OVER
	_ticker.stop()
	_spawn_timer.stop() # Stop the enemy spawn timer
	_interval_decrease_timer.stop() # Stop the interval decrease timer
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
	for i in range(amount):
		var area : Area3D = spawn_areas[randi() % spawn_areas.size()]
		var spawner_scene = load("res://resource/entities/enemy_spawner.tscn")
		var spawner_instance = spawner_scene.instantiate()
		spawner_instance.spawn_count = enemy_cap
		# Configure composition per wave and per-area
		var is_archer_only_area := false
		if area:
			is_archer_only_area = area.is_in_group("archer_only") or area.is_in_group("archer_only_spawn") or (area.has_meta("archer_only") and bool(area.get_meta("archer_only")))

		# Waves 1-2: strictly knights everywhere
		if _wave <= 2:
			spawner_instance.force_knights_only = true
			spawner_instance.archer_only_area = false
		else:
			spawner_instance.force_knights_only = false
			spawner_instance.archer_only_area = is_archer_only_area
			spawner_instance.mixed_knight_ratio = 0.7

		spawner_instance.global_transform.origin = area.global_transform.origin
		get_tree().current_scene.add_child(spawner_instance)
		print("[Wave %d] Spawned enemy spawner at %s with cap %d" % [_wave, area.name, enemy_cap]) 

func _on_tick_timer_timeout():
	if doom_tick_sound and _tick_player:
		_tick_player.play()
	# Update doom label each second
	_update_doom_label(_doom_timer.time_left)
	# Pulse overwhelm meter red
	_pulse_overwhelm_meter()

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

# Tween bounce animation for doom label
func _animate_doom_label(lbl: CanvasItem):
	if lbl == null:
		return
	# Reset scale to ensure consistent start
	lbl.scale = Vector2.ONE
	if _doom_label_tween and _doom_label_tween.is_running():
		_doom_label_tween.kill()
	_doom_label_tween = create_tween()
	_doom_label_tween.tween_property(lbl, "scale", Vector2(1.3,1.3), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_doom_label_tween.tween_property(lbl, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Pulse the overwhelm meter by briefly tinting it red
func _pulse_overwhelm_meter():
	if ui_overwhelm_meter == NodePath("") or not has_node(ui_overwhelm_meter):
		return
	var n = get_node(ui_overwhelm_meter)
	if not (n is CanvasItem):
		return
	# Kill previous tween if still running
	if _meter_pulse_tween and _meter_pulse_tween.is_running():
		_meter_pulse_tween.kill()
	_meter_pulse_tween = create_tween()
	_meter_pulse_tween.tween_property(n, "modulate", Color(1,0,0,1), 0.1)
	_meter_pulse_tween.tween_property(n, "modulate", _meter_original_modulate, 0.3).set_delay(0.1)

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
		if target.has_signal("died"):
			target.connect("died", _on_player_died)
			print("[GameMaster] Connected to 'died' signal from " + str(target.get_path()))
		elif target.has_signal("player_died"):
			target.connect("player_died", _on_player_died)
			print("[GameMaster] Connected to 'player_died' signal from " + str(target.get_path()))
		_player_connected = true
	else:
		push_warning("Player " + player_root.name + " has no descendant emitting death signals") 

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

# Callback for SceneTree.node_added – ensures late-spawned enemies are overwhelmed
func _on_node_added(node: Node):
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

# Called when an enemy node exits tree (i.e., is killed/freed)
func _on_enemy_node_exited(enemy: Node):
	if enemy == null:
		return
	register_kill(1)
	print("[GameMaster] Enemy freed -> kill registered")

# ---------------- Reaper update ----------------------
func _update_reaper(delta: float):
	# Only run if player available
	var player_node: Node3D = null
	if player_path != NodePath("") and has_node(player_path):
		player_node = get_node(player_path)
	else:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_node = players[0]
	if player_node == null:
		return
	# Compute horizontal speed in UPS (units/sec). If root lacks velocity, look for child 'Body'.
	var speed: float = 0.0
	var body_node := player_node
	if not "velocity" in body_node:
		body_node = player_node.get_node_or_null("Body")
	if body_node and "velocity" in body_node:
		var vel: Vector3 = body_node.velocity
		var h_vel: Vector2 = Vector2(vel.x, vel.z)
		speed = h_vel.length() * _UPS_FACTOR
	else:
		# Fallback to 0 so reaper works
		speed = 0.0

	if speed < reaper_threshold_speed:
		_reaper_elapsed += delta
	else:
		_reaper_elapsed = 0.0

	# Update overlay tint (first calculate progress)
	var progress: float = clamp(_reaper_elapsed / reaper_time, 0.0, 1.0)
	if ui_reaper_overlay != NodePath("") and has_node(ui_reaper_overlay):
		var ov_node := get_node(ui_reaper_overlay)
		if ov_node is Control:
			(ov_node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ov: CanvasItem = ov_node as CanvasItem
		if ov:
			var target: Color = _overlay_original_color.lerp(reaper_color, progress)
			ov.modulate = target

	# If timer exceeded -> kill player (after applying tint)
	if _reaper_elapsed >= reaper_time:
		if reaper_sound and _tick_player:
			_tick_player.stop()
			_tick_player.stream = reaper_sound
			_tick_player.play()
		print("[GameMaster] Reaper triggered – player too slow")
		_inflict_reaper_death()
		return # stop further processing to avoid multiple calls

# Inflict death via player's health component so normal death flow runs
func _inflict_reaper_death():
	var player_root : Node = null
	if player_path != NodePath("") and has_node(player_path):
		player_root = get_node(player_path)
	else:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			player_root = players[0]
	if player_root == null:
		_on_player_died()
		return
	# Prefer PlayerState.die() if available
	var ps_node = _find_node_with_signal(player_root, ["player_died"])
	if ps_node and ps_node.has_method("die"):
		ps_node.die()
		return

	var health_node = _find_node_with_signal(player_root, ["died"])
	if health_node and health_node.has_method("take_damage"):
		var dmg: int = 9999
		if health_node.has_method("get_current_health"):
			dmg = int(health_node.get_current_health())
		health_node.take_damage(dmg)
	elif player_root.has_method("die"):
		player_root.die()
	else:
		_on_player_died() 

# Helper to tween BGM bus volume
func _set_bgm_volume(value: float):
	if _bgm_bus_idx >= 0:
		AudioServer.set_bus_volume_db(_bgm_bus_idx, value) 

# ---------------------- BGM helpers ----------------------
func _fade_bgm_to(target_db: float, duration: float):
	if _bgm_bus_idx < 0:
		return
	var clamped_target : float = clamp(target_db, -80.0, BGM_ORIGINAL_DB)
	if duration <= 0.0:
		AudioServer.set_bus_volume_db(_bgm_bus_idx, clamped_target)
		return
	if _bgm_tween and _bgm_tween.is_running():
		_bgm_tween.kill()
	_bgm_tween = create_tween()
	_bgm_tween.tween_method(_set_bgm_volume, AudioServer.get_bus_volume_db(_bgm_bus_idx), clamped_target, duration)

# ---------------- Public API -----------------
## Returns whether the doom/overwhelm state is currently active
func is_doom_active() -> bool:
	return _doom_active 
