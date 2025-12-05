class_name LanDiscovery
extends Node

## robust LAN discovery component
## Handles broadcasting server presence and discovering other servers on the local network.
## Decoupled from MultiplayerManager to ensure Single Responsibility.

signal server_found(server_info: Dictionary)
signal server_lost(server_info: Dictionary)
signal server_list_updated(servers: Array[Dictionary])

const DEFAULT_BROADCAST_PORT: int = 7001
const CLEANUP_INTERVAL: float = 1.0
const SERVER_TTL: float = 5.0 # Seconds before a server is considered lost if no broadcast received

@export var broadcast_port: int = DEFAULT_BROADCAST_PORT
@export var broadcast_interval: float = 1.0

var _broadcast_timer: Timer
var _cleanup_timer: Timer
var _socket: PacketPeerUDP
var _is_broadcasting: bool = false
var _is_listening: bool = false
var _server_info: Dictionary = {}
var _discovered_servers: Dictionary = {} # Key: "ip:port", Value: server_info

var _session_id: String = ""

func _ready() -> void:
	randomize()
	_session_id = str(randi())
	
	# Create the socket immediately but don't bind until listening
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	
	_cleanup_timer = Timer.new()
	_cleanup_timer.wait_time = CLEANUP_INTERVAL
	_cleanup_timer.timeout.connect(_prune_expired_servers)
	add_child(_cleanup_timer)
	_cleanup_timer.start()

func _process(_delta: float) -> void:
	if _is_listening and _socket:
		_process_incoming_packets()

## Start broadcasting this machine as a server
func start_broadcasting(info: Dictionary) -> void:
	_server_info = info.duplicate()
	_server_info["unique_id"] = _session_id
		
	if _is_broadcasting:
		return

	_is_broadcasting = true
	
	# We need a socket for sending broadcasts too
	# We use the persistent socket if available (and not bound to a specific port preventing send?)
	# Actually, we should just use a transient socket for sending if we aren't listening on the broadcast port
	# to avoid any issues. But if we ARE listening on the broadcast port, we can send from it too.
	
	if not _broadcast_timer:
		_broadcast_timer = Timer.new()
		_broadcast_timer.wait_time = broadcast_interval
		_broadcast_timer.timeout.connect(_broadcast_presence)
		add_child(_broadcast_timer)
		
	_broadcast_timer.start()
	_broadcast_presence() # Broadcast immediately
	print("[LanDiscovery] Started broadcasting")

## Stop broadcasting
func stop_broadcasting() -> void:
	_is_broadcasting = false
	if _broadcast_timer:
		_broadcast_timer.stop()
	print("[LanDiscovery] Stopped broadcasting")

## Start listening for other servers
func start_listening() -> void:
	if _is_listening:
		return

	# If we have a socket, close it to unbind/reset
	if _socket:
		_socket.close()
	
	_socket = PacketPeerUDP.new()
	_socket.set_broadcast_enabled(true)
	
	# Try to bind to the broadcast port
	# We need to allow address reuse so multiple instances can bind to the same port on the same machine
	# Godot 4's PacketPeerUDP automatically attempts SO_REUSEADDR when binding
	var err = _socket.bind(broadcast_port)
	if err != OK:
		print("[LanDiscovery] Failed to bind to broadcast port %d: %s" % [broadcast_port, error_string(err)])
		# Fallback: Try binding to a random port for testing (though this limits discovery to broadcast only)
		# Real LAN discovery needs the fixed port.
		_is_listening = false
		return
		
	_is_listening = true
	print("[LanDiscovery] Started listening on port %d" % broadcast_port)

## Stop listening
func stop_listening() -> void:
	_is_listening = false
	if _socket:
		_socket.close()
		_socket = null
	_discovered_servers.clear()
	var empty_list: Array[Dictionary] = []
	server_list_updated.emit(empty_list)
	print("[LanDiscovery] Stopped listening")

func _broadcast_presence() -> void:
	if not _is_broadcasting: 
		return
		
	# Use a temporary socket for sending to avoid conflict if we are also bound for listening
	# Using a fresh socket for every broadcast ensures we don't block or interfere with the listening socket
	var packet_socket = PacketPeerUDP.new()
	packet_socket.set_broadcast_enabled(true)
	# Destination: Broadcast address
	packet_socket.set_dest_address("255.255.255.255", broadcast_port)
	
	var json_str = JSON.stringify(_server_info)
	var packet = json_str.to_utf8_buffer()
	
	var err = packet_socket.put_packet(packet)
	if err != OK:
		print("[LanDiscovery] Error sending broadcast: ", error_string(err))
	
	packet_socket.close()

func _process_incoming_packets() -> void:
	while _socket.get_available_packet_count() > 0:
		var packet = _socket.get_packet()
		var packet_ip = _socket.get_packet_ip()
		var packet_port = _socket.get_packet_port()
		var data_str = packet.get_string_from_utf8()
		
		if data_str.is_empty():
			continue
			
		var json = JSON.new()
		var err = json.parse(data_str)
		if err == OK:
			var info = json.data
			if info is Dictionary:
				_handle_discovered_server(info, packet_ip)

func _handle_discovered_server(info: Dictionary, ip: String) -> void:
	# Basic validation
	if not info.has("port"):
		return
		
	# If it's our own broadcast?
	if info.get("unique_id") == _session_id:
		return
		
	# Key for the server map
	var key = "%s:%d" % [ip, int(info["port"])]
	
	info["ip"] = ip # Ensure IP is correct from the packet source
	info["last_seen"] = Time.get_ticks_msec()
	
	if not _discovered_servers.has(key):
		print("[LanDiscovery] New server found: %s" % key)
		_discovered_servers[key] = info
		server_found.emit(info)
		_emit_list_update()
	else:
		# Update info
		_discovered_servers[key] = info
		# We don't emit server_found again, but we updated timestamp

func _prune_expired_servers() -> void:
	var current_time = Time.get_ticks_msec()
	var expired_keys = []
	
	for key in _discovered_servers:
		var server = _discovered_servers[key]
		if current_time - server["last_seen"] > SERVER_TTL * 1000:
			expired_keys.append(key)
			
	if expired_keys.size() > 0:
		for key in expired_keys:
			var server = _discovered_servers[key]
			print("[LanDiscovery] Server lost: %s" % key)
			server_lost.emit(server)
			_discovered_servers.erase(key)
		_emit_list_update()

func _emit_list_update() -> void:
	var list: Array[Dictionary] = []
	for key in _discovered_servers:
		list.append(_discovered_servers[key])
	server_list_updated.emit(list)

# Utility to force clear
func clear_servers() -> void:
	_discovered_servers.clear()
	_emit_list_update()

