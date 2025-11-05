extends Node
class_name VisionComponent

var bot: EnemyNextBot
var ray_cast: RayCast3D
var known_entities: Array[Dictionary] = []
var field_of_view: float = 90.0 # degrees
var max_vision_range: float = 20.0

func initialize(bot_ref: EnemyNextBot) -> void:
    bot = bot_ref
    ray_cast = bot.get_node("RayCasts/VisionRayCast")
    ray_cast.target_position.z = -max_vision_range

func update(delta: float) -> void:
    # Update known entities
    for entity in known_entities:
        if not is_instance_valid(entity.node):
            known_entities.erase(entity)
            continue
            
        # Check if entity is still visible
        if not can_see(entity.node):
            entity.last_seen_time += delta
            if entity.last_seen_time > 5.0: # Memory timeout
                known_entities.erase(entity)
                bot.on_lost_sight(entity.node)

func can_see(target: Node) -> bool:
    if not is_instance_valid(target):
        return false
        
    # Check distance
    var distance = bot.global_position.distance_to(target.global_position)
    if distance > max_vision_range:
        return false
        
    # Check field of view
    var direction_to_target = (target.global_position - bot.global_position).normalized()
    var forward = -bot.global_transform.basis.z
    var angle = rad_to_deg(forward.angle_to(direction_to_target))
    if angle > field_of_view * 0.5:
        return false
        
    # Check line of sight
    ray_cast.look_at(target.global_position)
    ray_cast.force_raycast_update()
    
    if ray_cast.is_colliding():
        var collider = ray_cast.get_collider()
        return collider == target
        
    return false

func register_entity(entity: Node) -> void:
    # Check if entity is already known
    for known in known_entities:
        if known.node == entity:
            known.last_seen_time = 0.0
            return
            
    # Add new entity
    known_entities.append({
        "node": entity,
        "last_seen_time": 0.0,
        "first_seen_time": Time.get_ticks_msec() / 1000.0
    })
    
    bot.on_sight(entity)

func unregister_entity(entity: Node) -> void:
    for known in known_entities:
        if known.node == entity:
            known_entities.erase(known)
            bot.on_lost_sight(entity)
            return

func get_threats() -> Array[Node]:
    var threats: Array[Node] = []
    for entity in known_entities:
        if is_threat(entity.node):
            threats.append(entity.node)
    return threats

func get_nearest_threat() -> Node:
    var nearest_threat: Node = null
    var nearest_distance: float = INF
    
    for entity in known_entities:
        if not is_threat(entity.node):
            continue
            
        var distance = bot.global_position.distance_to(entity.node.global_position)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_threat = entity.node
            
    return nearest_threat

func update_threat(entity: Node) -> void:
    if not entity:
        return
        
    # Update threat status
    for known in known_entities:
        if known.node == entity:
            known.is_threat = true
            known.threat_level = calculate_threat_level(entity)
            return
            
    # If not known, register it
    register_entity(entity)

func is_threat(entity: Node) -> bool:
    # Implement threat detection logic
    # For example, check if entity is on enemy team
    if entity.has_method("get_team"):
        return entity.get_team() != bot.get_team()
    return false

func calculate_threat_level(entity: Node) -> float:
    # Implement threat level calculation
    # For example, based on distance, health, weapons, etc.
    var threat_level = 1.0
    var distance = bot.global_position.distance_to(entity.global_position)
    
    # Distance factor (closer = more threatening)
    threat_level *= 1.0 - clamp(distance / max_vision_range, 0.0, 1.0)
    
    # Add other factors like health, weapons, etc.
    
    return threat_level 