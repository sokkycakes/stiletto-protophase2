extends Control
class_name LatencyDebugUI

## Latency debug UI component for multiplayer
## Displays ping/latency in milliseconds in the top left corner
## Uses a ping/pong RPC system to measure round-trip time

@onready var latency_label: Label = $LatencyLabel

# Ping/pong state
var last_ping_time: int = 0
var current_latency_ms: int = 0
var ping_timer: Timer
var ping_interval: float = 1.0  # Send ping every second

# Only show in multiplayer
var is_multiplayer: bool = false

func _ready() -> void:
	# Create latency label if it doesn't exist
	if not latency_label:
		latency_label = Label.new()
		latency_label.name = "LatencyLabel"
		add_child(latency_label)
	
	# Setup label appearance
	latency_label.text = "Ping: -- ms"
	latency_label.add_theme_color_override("font_color", Color.WHITE)
	latency_label.add_theme_color_override("font_outline_color", Color.BLACK)
	latency_label.add_theme_constant_override("outline_size", 2)
	
	# Position in top left
	anchors_preset = Control.PRESET_TOP_LEFT
	offset_left = 20
	offset_top = 20
	offset_right = 200
	offset_bottom = 50
	
	# Don't capture mouse input - allow clicks to pass through
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create ping timer
	ping_timer = Timer.new()
	ping_timer.wait_time = ping_interval
	ping_timer.timeout.connect(_on_ping_timer_timeout)
	ping_timer.autostart = false
	add_child(ping_timer)
	
	# Connect to multiplayer signals
	if multiplayer:
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		multiplayer.connection_failed.connect(_on_connection_failed)
	
	# Check if we're in multiplayer
	call_deferred("_check_multiplayer_status")
	
	# Hide initially
	visible = false

func _check_multiplayer_status() -> void:
	# Check if multiplayer is active
	if not multiplayer:
		is_multiplayer = false
		visible = false
		return
	
	if not multiplayer.has_multiplayer_peer():
		is_multiplayer = false
		visible = false
		return
	
	var peer = multiplayer.multiplayer_peer
	if peer == null:
		is_multiplayer = false
		visible = false
		return
	
	# Check if we're connected (not just the server)
	is_multiplayer = peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	
	# Server doesn't need to show latency (it's the host)
	# Only clients show latency to server
	if multiplayer.is_server():
		is_multiplayer = false
	
	visible = is_multiplayer
	
	if is_multiplayer:
		ping_timer.start()
		# Send initial ping
		call_deferred("_send_ping")
	else:
		ping_timer.stop()
		latency_label.text = "Ping: -- ms"


func _on_ping_timer_timeout() -> void:
	if is_multiplayer:
		_send_ping()

func _send_ping() -> void:
	if not is_multiplayer:
		return
	
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	
	# Only clients send pings to server (server doesn't need to measure its own latency)
	if multiplayer.is_server():
		# Server doesn't measure latency - it's the host
		# Could optionally measure latency to clients, but for debug UI, client latency is more useful
		return
	
	# Client pings server
	last_ping_time = Time.get_ticks_msec()
	receive_ping.rpc_id(1)  # Server is always peer 1

@rpc("any_peer", "call_remote", "reliable")
func receive_ping() -> void:
	# Immediately respond with pong
	var sender_id = multiplayer.get_remote_sender_id()
	receive_pong.rpc_id(sender_id)

@rpc("any_peer", "call_remote", "reliable")
func receive_pong() -> void:
	# Calculate latency
	var current_time = Time.get_ticks_msec()
	current_latency_ms = current_time - last_ping_time
	
	# Update label
	_update_latency_display()

func _update_latency_display() -> void:
	if not latency_label:
		return
	
	# Color code based on latency
	var color: Color
	if current_latency_ms < 50:
		color = Color.GREEN
	elif current_latency_ms < 100:
		color = Color.YELLOW
	elif current_latency_ms < 200:
		color = Color.ORANGE
	else:
		color = Color.RED
	
	latency_label.text = "Ping: %d ms" % current_latency_ms
	latency_label.add_theme_color_override("font_color", color)

func _on_connected_to_server() -> void:
	_check_multiplayer_status()

func _on_server_disconnected() -> void:
	is_multiplayer = false
	visible = false
	ping_timer.stop()
	if latency_label:
		latency_label.text = "Ping: -- ms"
	current_latency_ms = 0

func _on_connection_failed() -> void:
	is_multiplayer = false
	visible = false
	ping_timer.stop()
	if latency_label:
		latency_label.text = "Ping: -- ms"
	current_latency_ms = 0

func _process(_delta: float) -> void:
	# Periodically check multiplayer status
	if Engine.get_process_frames() % 60 == 0:  # Check every second at 60 FPS
		var was_multiplayer = is_multiplayer
		_check_multiplayer_status()
		
		# If status changed, update display
		if was_multiplayer != is_multiplayer and not is_multiplayer:
			if latency_label:
				latency_label.text = "Ping: -- ms"
			current_latency_ms = 0

