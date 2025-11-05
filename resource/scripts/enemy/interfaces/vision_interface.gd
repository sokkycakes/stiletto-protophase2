## NextBot Vision Interface
## Based on Source SDK NextBotVisionInterface.h
class_name IVision
extends INextBotComponent

# Vision properties
var max_vision_range: float = 20.0
var field_of_view: float = 90.0  # degrees
var min_recognition_time: float = 0.1
var max_recognition_time: float = 2.0

# Known entities tracking
var known_entities: Array[KnownEntity] = []
var primary_threat: KnownEntity = null

# Vision state
var is_looking_at: Node = null
var last_vision_update_time: float = 0.0

# KnownEntity class for tracking seen entities
class KnownEntity:
	var entity: Node
	var last_known_position: Vector3
	var last_seen_time: float
	var first_seen_time: float
	var visibility_status: VisibilityStatus
	var threat_level: float = 0.0
	var is_visible_now: bool = false
	
	enum VisibilityStatus {
		NOT_VISIBLE,
		VISIBLE,
		PARTIALLY_VISIBLE
	}
	
	func _init(ent: Node):
		entity = ent
		last_known_position = ent.global_position
		var current_time = Time.get_unix_time_from_system()
		first_seen_time = current_time
		last_seen_time = current_time
		visibility_status = VisibilityStatus.VISIBLE
		is_visible_now = true

# Vision interface methods
func reset() -> void:
	known_entities.clear()
	primary_threat = null
	is_looking_at = null

func update(delta: float) -> void:
	last_vision_update_time = Time.get_unix_time_from_system()
	_update_vision(delta)

func is_able_to_see(entity: Node, field_of_view_check: bool = true) -> bool:
	if not entity or not is_instance_valid(entity):
		return false
		
	var eye_pos = bot.get_body_interface().get_eye_position()
	var target_pos = entity.global_position
	var distance = eye_pos.distance_to(target_pos)
	
	# Range check
	if distance > max_vision_range:
		return false
	
	# Field of view check
	if field_of_view_check:
		var to_target = (target_pos - eye_pos).normalized()
		var forward = bot.get_body_interface().get_view_vector()
		var angle = rad_to_deg(acos(forward.dot(to_target)))
		
		if angle > field_of_view * 0.5:
			return false
	
	# Line of sight check
	return _has_line_of_sight(eye_pos, target_pos, entity)

func get_primary_known_threat(only_visible: bool = false) -> KnownEntity:
	if not primary_threat:
		return null
		
	if only_visible and not primary_threat.is_visible_now:
		return null
		
	return primary_threat

func get_time_since_visible(team_id: int = -1) -> float:
	var current_time = Time.get_unix_time_from_system()
	var most_recent_time = 0.0
	
	for known_entity in known_entities:
		if team_id != -1:
			# Check team if specified (would need team system)
			pass
		
		if known_entity.last_seen_time > most_recent_time:
			most_recent_time = known_entity.last_seen_time
	
	if most_recent_time == 0.0:
		return 999999.0  # Never seen
		
	return current_time - most_recent_time

func get_closest_known(team_id: int = -1) -> KnownEntity:
	var closest: KnownEntity = null
	var closest_distance = INF
	var eye_pos = bot.get_body_interface().get_eye_position()
	
	for known_entity in known_entities:
		if team_id != -1:
			# Check team if specified
			pass
			
		var distance = eye_pos.distance_to(known_entity.last_known_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = known_entity
	
	return closest

func get_known_count(team_id: int = -1, only_visible: bool = false) -> int:
	var count = 0
	
	for known_entity in known_entities:
		if team_id != -1:
			# Check team if specified
			pass
			
		if only_visible and not known_entity.is_visible_now:
			continue
			
		count += 1
	
	return count

func collect_known_entities(output_vector: Array[KnownEntity]) -> void:
	output_vector.clear()
	output_vector.append_array(known_entities)

func for_each_known_entity(functor: Callable) -> bool:
	for known_entity in known_entities:
		if not functor.call(known_entity):
			return false
	return true

func is_looking_at_entity(entity: Node, cos_half_fov: float = 0.95) -> bool:
	return is_looking_at == entity

func look_at(subject: Node) -> void:
	is_looking_at = subject
	if bot.get_body_interface():
		bot.get_body_interface().aim_head_towards(subject)

# Vision range and FOV
func get_max_vision_range() -> float:
	return max_vision_range

func set_max_vision_range(range: float) -> void:
	max_vision_range = range

func get_field_of_view() -> float:
	return field_of_view

func set_field_of_view(fov: float) -> void:
	field_of_view = fov

# Component initialization
func _init() -> void:
	component_name = "Vision"

# Internal vision update
func _update_vision(delta: float) -> void:
	_update_known_entities()
	_scan_for_new_entities()
	_update_primary_threat()

func _update_known_entities() -> void:
	var current_time = Time.get_unix_time_from_system()
	var entities_to_remove: Array[int] = []
	
	for i in range(known_entities.size()):
		var known_entity = known_entities[i]
		
		# Check if entity still exists
		if not is_instance_valid(known_entity.entity):
			entities_to_remove.append(i)
			continue
		
		# Update visibility
		var was_visible = known_entity.is_visible_now
		known_entity.is_visible_now = is_able_to_see(known_entity.entity)
		
		if known_entity.is_visible_now:
			known_entity.last_seen_time = current_time
			known_entity.last_known_position = known_entity.entity.global_position
			known_entity.visibility_status = KnownEntity.VisibilityStatus.VISIBLE
			
			if not was_visible:
				on_sight(known_entity.entity)
		else:
			known_entity.visibility_status = KnownEntity.VisibilityStatus.NOT_VISIBLE
			
			if was_visible:
				on_lost_sight(known_entity.entity)
	
	# Remove invalid entities
	for i in range(entities_to_remove.size() - 1, -1, -1):
		known_entities.remove_at(entities_to_remove[i])

func _scan_for_new_entities() -> void:
	# Get all potential targets in range
	var eye_pos = bot.get_body_interface().get_eye_position()
	var space_state = bot.get_world_3d().direct_space_state
	
	# This is a simplified scan - in practice you'd use area queries or other methods
	var potential_targets = _get_potential_targets_in_range(eye_pos)
	
	for target in potential_targets:
		if not _is_entity_known(target) and is_able_to_see(target):
			var known_entity = KnownEntity.new(target)
			known_entities.append(known_entity)
			on_sight(target)

func _update_primary_threat() -> void:
	var highest_threat: KnownEntity = null
	var highest_threat_level = 0.0
	
	for known_entity in known_entities:
		if known_entity.threat_level > highest_threat_level:
			highest_threat_level = known_entity.threat_level
			highest_threat = known_entity
	
	if primary_threat != highest_threat:
		primary_threat = highest_threat

func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3, target: Node) -> bool:
	var space_state = bot.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [bot]  # Don't hit ourselves
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return true
		
	# Check if we hit the target or something else
	return result.get("collider") == target

func _is_entity_known(entity: Node) -> bool:
	for known_entity in known_entities:
		if known_entity.entity == entity:
			return true
	return false

func _get_potential_targets_in_range(eye_pos: Vector3) -> Array[Node]:
	# Simplified implementation - in practice you'd use proper spatial queries
	var targets: Array[Node] = []
	
	# This would typically query the game's entity system
	# For now, return empty array - implement based on your game's needs
	
	return targets
