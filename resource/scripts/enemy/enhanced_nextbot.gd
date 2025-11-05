## Enhanced NextBot Implementation
## Combines the new NextBot system with legacy compatibility

class_name EnhancedNextBot
extends INextBot

# Action classes will be resolved at runtime

# Component type declarations (using untyped variables to avoid preload issues)

# Component implementations
var enhanced_locomotion
var enhanced_body
var enhanced_vision
var enhanced_intention

# Legacy compatibility
var legacy_locomotion
var legacy_body
var legacy_vision
var legacy_intention

# Bot properties
var health: float = 100.0
var max_health: float = 100.0
var health_threshold: float = 30.0
var is_dead: bool = false
var team: int = 1

# Navigation
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	super._ready()

	# Set debug name
	debug_name = "EnhancedBot_%d" % get_instance_id()

# Interface implementations
func get_locomotion_interface() -> ILocomotion:
	if enhanced_locomotion:
		return enhanced_locomotion
	return null

func get_body_interface() -> IBody:
	if enhanced_body:
		return enhanced_body
	return null

func get_vision_interface() -> IVision:
	if enhanced_vision:
		return enhanced_vision
	return null

func get_intention_interface():
	if enhanced_intention:
		return enhanced_intention
	return null

# Legacy compatibility methods
func is_health_low() -> bool:
	return health < health_threshold

func has_threats() -> bool:
	var vision = get_vision_interface()
	if vision:
		return vision.get_primary_known_threat(true) != null
	return legacy_vision and legacy_vision.get_threats().size() > 0

func get_nearest_threat() -> Node:
	var vision = get_vision_interface()
	if vision:
		var threat = vision.get_primary_known_threat(true)
		return threat.entity if threat else null
	return legacy_vision.get_nearest_threat() if legacy_vision else null

func can_see(target: Node) -> bool:
	var vision = get_vision_interface()
	if vision:
		return vision.is_able_to_see(target)
	return legacy_vision.can_see(target) if legacy_vision else false

func get_team() -> int:
	return team

func set_team(new_team: int) -> void:
	team = new_team

# Health system
func take_damage(damage_info: Dictionary) -> void:
	var damage_amount = damage_info.get("amount", 0.0)
	var attacker = damage_info.get("attacker", null)
	
	health -= damage_amount
	health = max(0.0, health)
	
	# Trigger injury event
	on_injured(damage_info)
	
	if health <= 0 and not is_dead:
		is_dead = true
		on_killed(damage_info)

func heal(amount: float) -> void:
	health = min(max_health, health + amount)

# Event handlers
func on_injured(damage_info: Dictionary) -> void:
	# Update threat tracking
	var attacker = damage_info.get("attacker", null)
	if attacker:
		var vision = get_vision_interface()
		if vision:
			vision.register_entity(attacker)
			vision.update_threat(attacker)
		elif legacy_vision:
			legacy_vision.register_entity(attacker)
			legacy_vision.update_threat(attacker)

func on_killed(damage_info: Dictionary) -> void:
	# Stop all movement
	var locomotion = get_locomotion_interface()
	if locomotion:
		locomotion.drive_to(global_position)

	# Play death animation
	var body = get_body_interface()
	if body:
		body.start_activity(IBody.ActivityType.DEATH)

	# Switch to death behavior
	var intention = get_intention_interface()
	if intention:
		var death_action_class = load("res://scripts/enemy/actions/death_action.gd")
		var death_action = death_action_class.new()
		intention.change_action(death_action)

func on_sight(entity: Node) -> void:
	# Legacy compatibility
	if legacy_intention:
		legacy_intention.evaluate_threat(entity)

func on_lost_sight(entity: Node) -> void:
	# Legacy compatibility
	if legacy_intention:
		legacy_intention.evaluate_threat_lost(entity)

func on_stuck() -> void:
	# Legacy compatibility
	if legacy_intention:
		legacy_intention.evaluate_stuck_state()

# Movement helpers
func move_toward(target_pos: Vector3) -> void:
	var locomotion = get_locomotion_interface()
	if locomotion:
		locomotion.approach(target_pos)
	elif legacy_locomotion:
		legacy_locomotion.move_to(target_pos)

func face_toward(target_pos: Vector3) -> void:
	var body = get_body_interface()
	if body:
		body.face_towards(target_pos)
	elif legacy_body:
		legacy_body.face_toward(target_pos)

func play_animation(anim_name: String) -> void:
	var body = get_body_interface()
	if body:
		body.play_animation(anim_name)
	elif legacy_body:
		legacy_body.play_animation(anim_name)

# Utility methods
func is_hostile_to(other: Node) -> bool:
	if other.has_method("get_team"):
		return other.get_team() != team
	return false

func get_weapon() -> Node:
	# Placeholder for weapon system
	return null

func get_view_vector() -> Vector3:
	var body = get_body_interface()
	if body:
		return body.get_view_vector()
	return -global_transform.basis.z

# Debug
func get_debug_name() -> String:
	if debug_name.is_empty():
		return "EnhancedNextBot_%d" % get_instance_id()
	return debug_name

# Navigation callback override
func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()
	
	# Update ground state for locomotion
	var locomotion = get_locomotion_interface()
	if locomotion and locomotion.has_method("_update_ground_state"):
		locomotion._update_ground_state()

# Component initialization override
func _initialize_components() -> void:
	# Initialize enhanced components first
	_setup_enhanced_components()

	# Then call parent to set up interfaces
	super._initialize_components()

	# Legacy components are not initialized here due to type compatibility issues
	# They expect EnemyNextBot type but we're EnhancedNextBot
	# Since the current scene only uses enhanced components, this is fine
	# Legacy components will remain null and the enhanced components will be used instead

func _setup_enhanced_components() -> void:
	# Get enhanced component nodes and assign them to typed variables
	var locomotion_node = get_node_or_null("Components/EnhancedLocomotionComponent")
	if locomotion_node and locomotion_node.has_method("approach"):
		enhanced_locomotion = locomotion_node

	var body_node = get_node_or_null("Components/EnhancedBodyComponent")
	if body_node and body_node.has_method("start_activity"):
		enhanced_body = body_node

	var vision_node = get_node_or_null("Components/EnhancedVisionComponent")
	if vision_node and vision_node.has_method("is_able_to_see"):
		enhanced_vision = vision_node

	var intention_node = get_node_or_null("Components/EnhancedIntentionComponent")
	if intention_node and intention_node.has_method("start_action"):
		enhanced_intention = intention_node

	# Also try to get legacy components if they exist (for backward compatibility)
	var legacy_locomotion_node = get_node_or_null("Components/LocomotionComponent")
	if legacy_locomotion_node and legacy_locomotion_node.has_method("approach"):
		legacy_locomotion = legacy_locomotion_node

	var legacy_body_node = get_node_or_null("Components/BodyComponent")
	if legacy_body_node and legacy_body_node.has_method("start_activity"):
		legacy_body = legacy_body_node

	var legacy_vision_node = get_node_or_null("Components/VisionComponent")
	if legacy_vision_node and legacy_vision_node.has_method("is_able_to_see"):
		legacy_vision = legacy_vision_node

	var legacy_intention_node = get_node_or_null("Components/IntentionComponent")
	if legacy_intention_node and legacy_intention_node.has_method("start_action"):
		legacy_intention = legacy_intention_node
