extends Node3D
class_name SpectatorPlayer

## Spectator player for watching matches without participating
## Provides free-fly camera movement and ability to cycle through spectating players

# --- Network Identity ---
var peer_id: int = -1
var player_name: String = "Spectator"

# --- Camera Components ---
var camera: Camera3D
var camera_pivot: Node3D

# --- Movement Settings ---
@export var fly_speed: float = 10.0
@export var fast_fly_speed: float = 25.0
@export var mouse_sensitivity: float = 0.002

# --- Spectate Mode ---
enum SpectateMode {
	FREE_FLY,        # Free camera movement
	FIRST_PERSON,    # View from a player's eyes
	THIRD_PERSON     # Follow behind a player
}

var spectate_mode: SpectateMode = SpectateMode.FREE_FLY
var spectate_target: Node3D = null
var spectate_target_index: int = 0
var available_targets: Array[Node3D] = []

# --- Camera State ---
var pitch: float = 0.0
var yaw: float = 0.0

# --- UI ---
var spectator_ui: Control

# --- Reference to GameWorld ---
var game_world: GameWorld

signal spectate_mode_changed(mode: SpectateMode)
signal spectate_target_changed(target: Node3D)

func _ready() -> void:
	# Set up network authority
	if peer_id > 0:
		set_multiplayer_authority(peer_id)
	
	# Create camera pivot and camera
	_setup_camera()
	
	# Create spectator UI
	_setup_ui()
	
	# Capture mouse for camera control
	if _has_local_authority():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _has_local_authority() -> bool:
	if not MultiplayerManager:
		return true
	return peer_id == MultiplayerManager.get_local_peer_id()

func _setup_camera() -> void:
	# Create camera pivot for rotation
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	add_child(camera_pivot)
	
	# Create the camera
	camera = Camera3D.new()
	camera.name = "SpectatorCamera"
	camera.fov = 90.0
	camera.near = 0.05
	camera.far = 4000.0
	camera_pivot.add_child(camera)
	
	# Only make camera current for local player
	if _has_local_authority():
		camera.current = true

func _setup_ui() -> void:
	if not _has_local_authority():
		return
	
	# Create a simple UI overlay for spectator controls
	spectator_ui = Control.new()
	spectator_ui.name = "SpectatorUI"
	spectator_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(spectator_ui)
	
	# Create container for labels
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vbox.offset_left = 20
	vbox.offset_bottom = -20
	vbox.offset_right = 400
	vbox.offset_top = -150
	spectator_ui.add_child(vbox)
	
	# Spectator mode label
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.text = "SPECTATOR"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	vbox.add_child(title_label)
	
	# Controls hint label
	var controls_label = Label.new()
	controls_label.name = "ControlsLabel"
	controls_label.text = "[WASD] Fly  [Shift] Fast  [Mouse1/2] Cycle Players  [Space] Free Cam"
	controls_label.add_theme_font_size_override("font_size", 14)
	controls_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(controls_label)
	
	# Currently spectating label
	var target_label = Label.new()
	target_label.name = "TargetLabel"
	target_label.text = ""
	target_label.add_theme_font_size_override("font_size", 16)
	target_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	vbox.add_child(target_label)

func _input(event: InputEvent) -> void:
	if not _has_local_authority():
		return
	
	# Handle mouse motion for camera
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_mouse_motion(event)
	
	# Handle spectate cycling
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_cycle_spectate_target(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cycle_spectate_target(-1)
	
	# Toggle free fly mode
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			_toggle_free_fly()
		elif event.keycode == KEY_ESCAPE:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if spectate_mode != SpectateMode.FREE_FLY:
		return
	
	yaw -= event.relative.x * mouse_sensitivity
	pitch -= event.relative.y * mouse_sensitivity
	pitch = clamp(pitch, -PI / 2.0 + 0.1, PI / 2.0 - 0.1)
	
	camera_pivot.rotation = Vector3(pitch, yaw, 0)

func _physics_process(delta: float) -> void:
	if not _has_local_authority():
		return
	
	match spectate_mode:
		SpectateMode.FREE_FLY:
			_process_free_fly(delta)
		SpectateMode.FIRST_PERSON:
			_process_first_person()
		SpectateMode.THIRD_PERSON:
			_process_third_person(delta)

func _process_free_fly(delta: float) -> void:
	# Get movement input
	var input_dir = Vector3.ZERO
	
	if Input.is_action_pressed("pm_moveforward"):
		input_dir.z -= 1
	if Input.is_action_pressed("pm_movebackward"):
		input_dir.z += 1
	if Input.is_action_pressed("pm_moveleft"):
		input_dir.x -= 1
	if Input.is_action_pressed("pm_moveright"):
		input_dir.x += 1
	
	# Up/down movement
	if Input.is_action_pressed("pm_jump"):
		input_dir.y += 1
	if Input.is_action_pressed("pm_duck"):
		input_dir.y -= 1
	
	input_dir = input_dir.normalized()
	
	# Apply movement in camera direction
	var speed = fast_fly_speed if Input.is_key_pressed(KEY_SHIFT) else fly_speed
	var velocity = camera_pivot.global_transform.basis * input_dir * speed
	
	global_position += velocity * delta

func _process_first_person() -> void:
	if not spectate_target or not is_instance_valid(spectate_target):
		_find_valid_target()
		return
	
	# Position camera at target's view position
	var target_player = spectate_target as NetworkedPlayer
	if target_player and target_player.pawn:
		# Find the camera or view position in the pawn
		var target_camera = target_player.pawn_camera
		if target_camera:
			global_position = target_camera.global_position
			camera_pivot.global_rotation = target_camera.global_rotation
		else:
			# Fallback to pawn position + offset
			var view_pos = target_player.pawn.global_position + Vector3(0, 1.6, 0)
			global_position = view_pos
			if target_player.pawn_horizontal_view:
				camera_pivot.rotation.y = target_player.pawn_horizontal_view.rotation.y
			if target_player.pawn_vertical_view:
				camera_pivot.rotation.x = target_player.pawn_vertical_view.rotation.x

func _process_third_person(delta: float) -> void:
	if not spectate_target or not is_instance_valid(spectate_target):
		_find_valid_target()
		return
	
	# Position camera behind and above target
	var target_player = spectate_target as NetworkedPlayer
	if target_player and target_player.pawn:
		var target_pos = target_player.pawn.global_position
		var follow_distance = 5.0
		var follow_height = 2.5
		
		# Calculate camera position behind target
		var target_rotation_y = 0.0
		if target_player.pawn_horizontal_view:
			target_rotation_y = target_player.pawn_horizontal_view.rotation.y
		
		var offset = Vector3(0, follow_height, follow_distance).rotated(Vector3.UP, target_rotation_y)
		var desired_pos = target_pos + offset
		
		# Smooth follow
		global_position = global_position.lerp(desired_pos, 5.0 * delta)
		
		# Look at target
		camera_pivot.look_at(target_pos + Vector3(0, 1.0, 0), Vector3.UP)

func _toggle_free_fly() -> void:
	if spectate_mode == SpectateMode.FREE_FLY:
		# Switch to first person spectate
		spectate_mode = SpectateMode.FIRST_PERSON
		_find_valid_target()
	else:
		# Switch to free fly
		spectate_mode = SpectateMode.FREE_FLY
		spectate_target = null
	
	_update_ui()
	spectate_mode_changed.emit(spectate_mode)

func _cycle_spectate_target(direction: int) -> void:
	if spectate_mode == SpectateMode.FREE_FLY:
		# Start spectating first available target
		spectate_mode = SpectateMode.FIRST_PERSON
	
	_update_available_targets()
	
	if available_targets.is_empty():
		return
	
	spectate_target_index = (spectate_target_index + direction) % available_targets.size()
	if spectate_target_index < 0:
		spectate_target_index = available_targets.size() - 1
	
	spectate_target = available_targets[spectate_target_index]
	_update_ui()
	spectate_target_changed.emit(spectate_target)

func _find_valid_target() -> void:
	_update_available_targets()
	
	if available_targets.is_empty():
		spectate_target = null
		return
	
	if spectate_target_index >= available_targets.size():
		spectate_target_index = 0
	
	spectate_target = available_targets[spectate_target_index]
	_update_ui()

func _update_available_targets() -> void:
	available_targets.clear()
	
	if not game_world:
		# Try to find game world
		var game_worlds = get_tree().get_nodes_in_group("game_world")
		if game_worlds.size() > 0:
			game_world = game_worlds[0] as GameWorld
	
	if not game_world:
		return
	
	# Get all active players (duelists)
	for player_id in game_world.players:
		var player = game_world.players[player_id] as NetworkedPlayer
		if player and is_instance_valid(player) and player.is_alive:
			available_targets.append(player)

func _update_ui() -> void:
	if not spectator_ui:
		return
	
	var target_label = spectator_ui.get_node_or_null("VBoxContainer/TargetLabel") as Label
	if not target_label:
		return
	
	match spectate_mode:
		SpectateMode.FREE_FLY:
			target_label.text = "Free Camera"
		SpectateMode.FIRST_PERSON, SpectateMode.THIRD_PERSON:
			if spectate_target:
				var target_player = spectate_target as NetworkedPlayer
				if target_player:
					target_label.text = "Spectating: " + target_player.player_name
				else:
					target_label.text = "Spectating: Unknown"
			else:
				target_label.text = "No players to spectate"

## Initialize spectator with network info
func initialize_spectator(id: int, name: String) -> void:
	peer_id = id
	player_name = name
	set_multiplayer_authority(peer_id)
	print("[SpectatorPlayer] Initialized spectator: ", name, " (ID: ", id, ")")

## Set initial position for spectator
func set_spawn_position(pos: Vector3) -> void:
	global_position = pos
	# Also set initial yaw based on spawn point if desired