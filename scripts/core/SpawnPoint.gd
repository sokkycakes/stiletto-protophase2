extends Node3D
class_name SpawnPoint

## Spawn point for player respawning in multiplayer games
## Supports team-based spawning and usage tracking

# --- Configuration ---
@export var team_id: int = 0  ## Which team can use this spawn point (-1 = any team)
@export var spawn_radius: float = 1.0  ## Radius for spawn position variation
@export var check_for_obstacles: bool = true  ## Whether to check for clear spawn space
@export var min_distance_from_enemies: float = 5.0  ## Minimum distance from enemy players

# --- Orientation ---
@export_group("Orientation")
## If true, uses the SpawnPoint node's rotation for the player's facing direction.
## If false, uses fixed_yaw_degrees.
@export var use_node_rotation: bool = true

## Fixed Y-rotation (yaw) in degrees to apply if use_node_rotation is false.
## Can also be used as an offset if logic is adjusted, but currently acts as override.
@export_range(-180, 180) var fixed_yaw_degrees: float = 0.0

# --- State Tracking ---
var last_used_time: float = 0.0
var total_usage_count: int = 0
var is_currently_occupied: bool = false

# --- Visual Debug (Editor only) ---
@export var show_debug_visualization: bool = false
var debug_mesh: MeshInstance3D

func _ready() -> void:
	# Add to spawn points group if not already
	if not is_in_group("spawn_points"):
		add_to_group("spawn_points")
	
	# Create debug visualization in editor
	if Engine.is_editor_hint() and show_debug_visualization:
		_create_debug_visualization()

func _create_debug_visualization() -> void:
	# Create a simple cylinder to visualize spawn point
	debug_mesh = MeshInstance3D.new()
	var cylinder_mesh = CylinderMesh.new()
	cylinder_mesh.bottom_radius = spawn_radius
	cylinder_mesh.top_radius = spawn_radius
	cylinder_mesh.height = 2.0
	debug_mesh.mesh = cylinder_mesh
	
	# Set team color
	var material = StandardMaterial3D.new()
	match team_id:
		0:
			material.albedo_color = Color.BLUE
		1:
			material.albedo_color = Color.RED
		2:
			material.albedo_color = Color.GREEN
		3:
			material.albedo_color = Color.YELLOW
		_:
			material.albedo_color = Color.WHITE
	
	material.flags_transparent = true
	material.albedo_color.a = 0.3
	debug_mesh.material_override = material
	
	add_child(debug_mesh)

# --- Public API ---

## Get the spawn rotation Y in degrees
func get_spawn_rotation_y() -> float:
	if use_node_rotation:
		return global_rotation_degrees.y + fixed_yaw_degrees
	return fixed_yaw_degrees

## Use this spawn point and return the exact spawn position
func use_spawn_point() -> Vector3:
	last_used_time = Time.get_unix_time_from_system()
	total_usage_count += 1
	
	var spawn_position = global_position
	
	# Add random variation within radius
	if spawn_radius > 0.0:
		var random_offset = Vector2(
			randf_range(-spawn_radius, spawn_radius),
			randf_range(-spawn_radius, spawn_radius)
		)
		spawn_position.x += random_offset.x
		spawn_position.z += random_offset.y
	
	# Check for obstacles if enabled
	if check_for_obstacles:
		spawn_position = _find_clear_spawn_position(spawn_position)
	
	print("Spawn point used: Team ", team_id, " at ", spawn_position)
	return spawn_position

## Check if this spawn point is suitable for a specific team
func is_suitable_for_team(team: int) -> bool:
	return team_id == -1 or team_id == team

## Check if spawn point is currently safe to use
func is_safe_to_use() -> bool:
	if not check_for_obstacles:
		return true
	
	# Check for nearby enemies
	if min_distance_from_enemies > 0.0:
		var nearby_players = _find_nearby_players()
		for player in nearby_players:
			var distance = global_position.distance_to(player.global_position)
			if distance < min_distance_from_enemies:
				# Check if it's an enemy (different team)
				if _is_enemy_player(player):
					return false
	
	return true

## Get spawn point info for UI/debugging
func get_spawn_info() -> Dictionary:
	return {
		"team_id": team_id,
		"position": global_position,
		"last_used": last_used_time,
		"usage_count": total_usage_count,
		"is_safe": is_safe_to_use(),
		"is_occupied": is_currently_occupied
	}

## Get team this spawn point belongs to
func get_team_id() -> int:
	return team_id

## Set team assignment
func set_team_id(new_team_id: int) -> void:
	team_id = new_team_id
	
	# Update debug visualization if it exists
	if debug_mesh and debug_mesh.material_override:
		var material = debug_mesh.material_override as StandardMaterial3D
		match team_id:
			0:
				material.albedo_color = Color.BLUE
			1:
				material.albedo_color = Color.RED
			2:
				material.albedo_color = Color.GREEN
			3:
				material.albedo_color = Color.YELLOW
			_:
				material.albedo_color = Color.WHITE
		material.albedo_color.a = 0.3

# --- Internal Helper Methods ---

func _find_clear_spawn_position(preferred_position: Vector3) -> Vector3:
	# Use physics to find a clear position
	var world = get_world_3d()
	if not world:
		return preferred_position
	
	var space_state = world.direct_space_state
	if not space_state:
		return preferred_position
	
	# Check if preferred position is clear
	if _is_position_clear(preferred_position, space_state):
		return preferred_position
	
	# Try nearby positions in a spiral pattern
	var attempts = 8
	var angle_step = 2.0 * PI / attempts
	var test_radius = spawn_radius * 2.0
	
	for i in range(attempts):
		var angle = i * angle_step
		var test_position = preferred_position + Vector3(
			cos(angle) * test_radius,
			0.0,
			sin(angle) * test_radius
		)
		
		if _is_position_clear(test_position, space_state):
			return test_position
	
	# If no clear position found, return preferred position
	print("Warning: No clear spawn position found for spawn point at ", global_position)
	return preferred_position

func _is_position_clear(position: Vector3, space_state: PhysicsDirectSpaceState3D) -> bool:
	# Check for obstacles using a shape cast
	var shape = SphereShape3D.new()
	shape.radius = 0.5  # Player capsule approximation
	
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = position + Vector3(0, 1, 0)  # Offset up for player height
	query.collision_mask = 1  # World layer
	query.exclude = [self]
	
	var results = space_state.intersect_shape(query)
	return results.is_empty()

func _find_nearby_players() -> Array:
	var nearby_players = []
	
	# Find all players in the scene
	var players_node = get_node_or_null("/root/GameWorld/Players")
	if not players_node:
		return nearby_players
	
	for child in players_node.get_children():
		if child is NetworkedPlayer:
			var distance = global_position.distance_to(child.global_position)
			if distance <= min_distance_from_enemies * 2.0:  # Check larger radius
				nearby_players.append(child)
	
	return nearby_players

func _is_enemy_player(player: NetworkedPlayer) -> bool:
	if not TeamManager:
		return true  # In deathmatch, everyone is an enemy
	
	# Check if player is on different team
	var player_team = player.team_id
	return player_team != team_id and team_id != -1

# --- Occupation Tracking ---

## Mark spawn point as occupied (for preventing simultaneous spawns)
func set_occupied(occupied: bool) -> void:
	is_currently_occupied = occupied

## Check occupation status
func is_occupied() -> bool:
	return is_currently_occupied

# --- Utility Functions ---

## Get spawn priority (lower is better)
func get_spawn_priority() -> float:
	var priority = last_used_time  # Prefer less recently used
	
	# Penalty for being unsafe
	if not is_safe_to_use():
		priority += 1000.0
	
	# Penalty for being occupied
	if is_currently_occupied:
		priority += 500.0
	
	return priority

## Distance to a specific position
func distance_to_position(position: Vector3) -> float:
	return global_position.distance_to(position)

## Check if within spawn radius of a position
func is_within_spawn_radius(position: Vector3) -> bool:
	return distance_to_position(position) <= spawn_radius

# --- Editor Tools ---

func _get_configuration_warnings() -> PackedStringArray:
	var warnings = PackedStringArray()
	
	# Check if properly positioned
	if global_position.y < 0:
		warnings.append("Spawn point is below ground level")
	
	# Check for nearby spawn points
	var nearby_spawns = get_tree().get_nodes_in_group("spawn_points")
	for spawn in nearby_spawns:
		if spawn != self and spawn is SpawnPoint:
			var distance = global_position.distance_to(spawn.global_position)
			if distance < 2.0:
				warnings.append("Very close to another spawn point (%s)" % spawn.name)
				break
	
	return warnings

# --- Debug Information ---

func get_debug_info() -> String:
	return "SpawnPoint %s\nTeam: %d\nUsage: %d\nLast Used: %.1fs ago\nSafe: %s" % [
		name,
		team_id,
		total_usage_count,
		Time.get_unix_time_from_system() - last_used_time,
		"Yes" if is_safe_to_use() else "No"
	]

# --- Visualization Update ---

func _process(delta: float) -> void:
	# Update debug visualization if needed
	if Engine.is_editor_hint() and debug_mesh:
		debug_mesh.visible = show_debug_visualization
