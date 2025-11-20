extends Node

# Multiplayer weapon synchronization
# Handles weapon firing, reloading, and effects across all clients

# Node references
@onready var player_root = get_parent()
@onready var weapon_system = null
var is_local_player: bool = false

# Weapon state
var current_ammo: int = 6
var max_ammo: int = 6
var is_reloading: bool = false
var can_fire: bool = true

# Effects
const MUZZLE_FLASH_SCENE = preload("res://scenes/effects/muzzle_flash.tscn")
const BULLET_TRAIL_SCENE = preload("res://scenes/effects/bullet_trail.tscn")
const IMPACT_EFFECT_SCENE = preload("res://scenes/effects/spark_effect.tscn")

func _ready():
	# Wait for player setup
	await get_tree().process_frame
	
	# Find weapon system in player
	weapon_system = _find_weapon_system(player_root)
	
	# Determine if this is the local player
	var networked_script = player_root.get_node_or_null("NetworkedPlayerScript")
	if networked_script:
		is_local_player = networked_script.is_local()
	
	# Connect to weapon system if found and this is local player
	if weapon_system and is_local_player:
		_connect_weapon_signals()
	
	print("Weapon sync initialized for ", player_root.name, " (Local: ", is_local_player, ")")

func _find_weapon_system(node: Node) -> Node:
	# Recursively search for weapon system
	if node.has_method("shoot") or node.has_method("get_current_ammo"):
		return node
	
	for child in node.get_children():
		var result = _find_weapon_system(child)
		if result:
			return result
	
	return null

func _connect_weapon_signals():
	# Connect to weapon system signals if available
	if weapon_system:
		# Try to connect to common weapon signals
		if weapon_system.has_signal("fired"):
			weapon_system.fired.connect(_on_weapon_fired)
		if weapon_system.has_signal("ammo_changed"):
			weapon_system.ammo_changed.connect(_on_ammo_changed)
		if weapon_system.has_signal("reload_finished"):
			weapon_system.reload_finished.connect(_on_reload_finished)

func _input(event):
	if not is_local_player:
		return
	
	# Handle weapon input
	if event.is_action_pressed("fire"):
		_handle_fire_input()
	elif event.is_action_pressed("reload"):
		_handle_reload_input()

func _handle_fire_input():
	if not can_fire or current_ammo <= 0 or is_reloading:
		return
	
	# Fire weapon locally and sync to others
	_fire_weapon()

func _handle_reload_input():
	if is_reloading or current_ammo >= max_ammo:
		return
	
	# Start reload locally and sync to others
	_start_reload()

func _fire_weapon():
	if not can_fire or current_ammo <= 0:
		return
	
	# Update local state
	current_ammo -= 1
	can_fire = false
	
	# Get firing data
	var fire_data = _get_fire_data()
	
	# Sync to all clients
	_rpc_fire_weapon.rpc(fire_data)
	
	# Reset fire cooldown
	await get_tree().create_timer(0.2).timeout
	can_fire = true

func _start_reload():
	if is_reloading:
		return
	
	is_reloading = true
	
	# Sync reload start to all clients
	_rpc_start_reload.rpc()
	
	# Simulate reload time
	await get_tree().create_timer(1.5).timeout
	
	# Complete reload
	current_ammo = max_ammo
	is_reloading = false
	
	# Sync reload complete to all clients
	_rpc_complete_reload.rpc(current_ammo)

func _get_fire_data() -> Dictionary:
	# Get camera for firing direction
	var camera = player_root.get_node_or_null("Interpolated Camera/Arm/Arm Anchor/Camera")
	if not camera:
		return {}
	
	return {
		"origin": camera.global_position,
		"direction": -camera.global_transform.basis.z,
		"ammo": current_ammo,
		"timestamp": Time.get_unix_time_from_system()
	}

# RPC methods

@rpc("any_peer", "call_local", "reliable")
func _rpc_fire_weapon(fire_data: Dictionary):
	# Handle weapon firing on all clients
	var origin = fire_data.get("origin", Vector3.ZERO)
	var direction = fire_data.get("direction", Vector3.FORWARD)
	var ammo = fire_data.get("ammo", 0)
	
	# Update ammo state
	current_ammo = ammo
	
	# Create visual effects
	_create_muzzle_flash(origin)
	_perform_hitscan(origin, direction)
	
	print("Player ", player_root.name, " fired weapon. Ammo: ", current_ammo)

@rpc("any_peer", "call_local", "reliable")
func _rpc_start_reload():
	# Handle reload start on all clients
	is_reloading = true
	print("Player ", player_root.name, " started reloading")

@rpc("any_peer", "call_local", "reliable")
func _rpc_complete_reload(new_ammo: int):
	# Handle reload completion on all clients
	current_ammo = new_ammo
	is_reloading = false
	print("Player ", player_root.name, " finished reloading. Ammo: ", current_ammo)

# Effect methods

func _create_muzzle_flash(position: Vector3):
	if not MUZZLE_FLASH_SCENE:
		return
	
	var muzzle_flash = MUZZLE_FLASH_SCENE.instantiate()
	get_tree().current_scene.add_child(muzzle_flash)
	muzzle_flash.global_position = position
	
	# Auto-remove after a short time
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(muzzle_flash):
		muzzle_flash.queue_free()

func _perform_hitscan(origin: Vector3, direction: Vector3):
	# Perform raycast for hit detection
	# Access world through the viewport (more reliable method)
	var space_state = get_viewport().world_3d.direct_space_state
	if not space_state:
		print("Warning: Could not access 3D world space for hitscan")
		return
	var query = PhysicsRayQueryParameters3D.create(origin, origin + direction * 100.0)
	
	# Exclude the firing player
	var exclude_list = [player_root]
	var body_node = player_root.get_node_or_null("Body")
	if body_node:
		exclude_list.append(body_node)
	query.exclude = exclude_list
	
	var result = space_state.intersect_ray(query)
	var hit_point = origin + direction * 100.0
	var hit_normal = Vector3.UP
	
	if result:
		hit_point = result.position
		hit_normal = result.normal

		# Apply damage if this is the local player (authority)
		if is_local_player and result.collider.has_method("take_damage"):
			result.collider.take_damage(25)  # Weapon damage
			print("Hit target: ", result.collider.name, " - Damage applied: 25")
		elif result.collider:
			print("Hit object: ", result.collider.name, " (no damage method)")
	
	# Create bullet trail
	_create_bullet_trail(origin, hit_point)
	
	# Create impact effect
	_create_impact_effect(hit_point, hit_normal)

func _create_bullet_trail(from: Vector3, to: Vector3):
	if not BULLET_TRAIL_SCENE:
		return
	
	var trail = BULLET_TRAIL_SCENE.instantiate()
	get_tree().current_scene.add_child(trail)
	
	# Set trail positions
	if trail.has_method("setup_trail"):
		trail.setup_trail(from, to)
	else:
		trail.global_position = from
		trail.look_at(to)

func _create_impact_effect(position: Vector3, normal: Vector3):
	if not IMPACT_EFFECT_SCENE:
		return
	
	var impact = IMPACT_EFFECT_SCENE.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = position
	impact.look_at(position + normal)

# Signal handlers (for local weapon system)

func _on_weapon_fired():
	# Called when local weapon system fires
	print("Local weapon fired")

func _on_ammo_changed(ammo_in_clip: int, total_ammo: int):
	# Called when local weapon ammo changes
	current_ammo = ammo_in_clip
	max_ammo = total_ammo

func _on_reload_finished():
	# Called when local weapon reload finishes
	print("Local weapon reload finished")

# Public methods

func get_current_ammo() -> int:
	return current_ammo

func get_max_ammo() -> int:
	return max_ammo

func is_weapon_reloading() -> bool:
	return is_reloading

func can_fire_weapon() -> bool:
	return can_fire and current_ammo > 0 and not is_reloading
