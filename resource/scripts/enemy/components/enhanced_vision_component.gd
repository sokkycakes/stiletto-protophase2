## Enhanced Vision Component Implementation

class_name EnhancedVisionComponent
extends IVision

# Legacy compatibility
var ray_cast: RayCast3D
var legacy_known_entities: Array[Dictionary] = []

func on_initialize() -> void:
	# Set default vision properties
	max_vision_range = 20.0
	field_of_view = 90.0
	min_recognition_time = 0.1
	max_recognition_time = 2.0
	
	# Try to find vision raycast
	ray_cast = bot.get_node_or_null("RayCasts/VisionRayCast")
	if ray_cast:
		ray_cast.target_position = Vector3(0, 0, -max_vision_range)

func on_update(delta: float) -> void:
	super.on_update(delta)
	
	# Update legacy entities for compatibility
	_update_legacy_entities(delta)

# Enhanced line of sight with raycast
func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3, target: Node) -> bool:
	if ray_cast:
		# Use the bot's raycast for more accurate results
		var original_pos = ray_cast.global_position
		var original_rotation = ray_cast.global_rotation
		
		ray_cast.global_position = from_pos
		ray_cast.look_at(to_pos, Vector3.UP)
		ray_cast.force_raycast_update()
		
		var result = false
		if ray_cast.is_colliding():
			var collider = ray_cast.get_collider()
			result = collider == target
		else:
			result = true
		
		# Restore original transform
		ray_cast.global_position = original_pos
		ray_cast.global_rotation = original_rotation
		
		return result
	else:
		# Fallback to physics query
		return super._has_line_of_sight(from_pos, to_pos, target)

# Enhanced potential target scanning
func _get_potential_targets_in_range(eye_pos: Vector3) -> Array[Node]:
	var targets: Array[Node] = []
	
	# Get all players
	var players = bot.get_tree().get_nodes_in_group("players")
	for player in players:
		if player != bot and eye_pos.distance_to(player.global_position) <= max_vision_range:
			targets.append(player)

	# Get all enemies
	var enemies = bot.get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy != bot and eye_pos.distance_to(enemy.global_position) <= max_vision_range:
			targets.append(enemy)

	# Get all threats
	var threats = bot.get_tree().get_nodes_in_group("threats")
	for threat in threats:
		if threat != bot and eye_pos.distance_to(threat.global_position) <= max_vision_range:
			targets.append(threat)
	
	return targets

# Legacy compatibility methods
func register_entity(entity: Node) -> void:
	# Add to new system
	if not _is_entity_known(entity):
		var known_entity = KnownEntity.new(entity)
		known_entities.append(known_entity)
	
	# Add to legacy system for compatibility
	for known in legacy_known_entities:
		if known.node == entity:
			known.last_seen_time = 0.0
			return
	
	legacy_known_entities.append({
		"node": entity,
		"last_seen_time": 0.0,
		"first_seen_time": Time.get_ticks_msec() / 1000.0,
		"is_threat": false,
		"threat_level": 0.0
	})

func unregister_entity(entity: Node) -> void:
	# Remove from new system
	for i in range(known_entities.size() - 1, -1, -1):
		if known_entities[i].entity == entity:
			known_entities.remove_at(i)
			break
	
	# Remove from legacy system
	for known in legacy_known_entities:
		if known.node == entity:
			legacy_known_entities.erase(known)
			return

func update_threat(entity: Node) -> void:
	if not entity:
		return
	
	# Update in new system
	var known_entity = _get_known_entity(entity)
	if known_entity:
		known_entity.threat_level = _calculate_threat_level(entity)
	
	# Update in legacy system
	for known in legacy_known_entities:
		if known.node == entity:
			known.is_threat = true
			known.threat_level = _calculate_threat_level(entity)
			return
	
	# If not known, register it
	register_entity(entity)

func get_threats() -> Array:
	var threats = []
	
	# Get from new system
	for known_entity in known_entities:
		if known_entity.threat_level > 0.3:
			threats.append(known_entity.entity)
	
	# Also check legacy system for compatibility
	for entity in legacy_known_entities:
		if entity.get("is_threat", false) and entity.node not in threats:
			threats.append(entity.node)
	
	return threats

func get_nearest_threat() -> Node:
	var primary = get_primary_known_threat(true)
	if primary:
		return primary.entity
	
	# Fallback to legacy system
	var nearest_threat: Node = null
	var nearest_distance: float = INF
	
	for entity in legacy_known_entities:
		if not entity.get("is_threat", false):
			continue
		
		var distance = bot.global_position.distance_to(entity.node.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_threat = entity.node
	
	return nearest_threat

func can_see(target: Node) -> bool:
	return is_able_to_see(target)

# Threat assessment
func _calculate_threat_level(entity: Node) -> float:
	var threat_level = 0.0
	var distance = bot.global_position.distance_to(entity.global_position)
	
	# Base threat based on proximity
	threat_level += max(0.0, (max_vision_range - distance) / max_vision_range)
	
	# Check if entity has weapon or is hostile
	if entity.has_method("get_weapon") and entity.get_weapon():
		threat_level += 0.5
	
	if entity.has_method("is_hostile_to") and entity.is_hostile_to(bot):
		threat_level += 0.3
	
	if entity.has_method("get_team") and bot.has_method("get_team"):
		if entity.get_team() != bot.get_team():
			threat_level += 0.2
	
	# Check if entity is looking at us
	if entity.has_method("get_view_vector"):
		var their_view = entity.get_view_vector()
		var to_us = (bot.global_position - entity.global_position).normalized()
		var dot = their_view.dot(to_us)
		if dot > 0.7:  # They're looking roughly at us
			threat_level += 0.2
	
	return clamp(threat_level, 0.0, 1.0)

func is_threat(entity: Node) -> bool:
	if entity.has_method("get_team") and bot.has_method("get_team"):
		return entity.get_team() != bot.get_team()
	return false

func calculate_threat_level(entity: Node) -> float:
	return _calculate_threat_level(entity)

# Update legacy entities for compatibility
func _update_legacy_entities(delta: float) -> void:
	for entity in legacy_known_entities:
		if not is_instance_valid(entity.node):
			legacy_known_entities.erase(entity)
			continue
		
		# Check if entity is still visible
		if not can_see(entity.node):
			entity.last_seen_time += delta
			if entity.last_seen_time > 5.0:  # Memory timeout
				legacy_known_entities.erase(entity)
				bot.on_lost_sight(entity.node)

# Get known entity by node reference
func _get_known_entity(entity: Node) -> KnownEntity:
	for known_entity in known_entities:
		if known_entity.entity == entity:
			return known_entity
	return null
