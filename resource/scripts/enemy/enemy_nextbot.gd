class_name EnemyNextBot
extends CharacterBody3D

# Core components
@onready var locomotion: LocomotionComponent = $Components/LocomotionComponent
@onready var body: BodyComponent = $Components/BodyComponent
@onready var vision: VisionComponent = $Components/VisionComponent
@onready var intention: IntentionComponent = $Components/IntentionComponent
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# Bot properties
var speed: float = 5.0
var health: float = 100.0
var health_threshold: float = 40.0
var is_dead: bool = false

func _ready() -> void:
    # Initialize components with reference to self
    for component in $Components.get_children():
        component.initialize(self)
    
    # Connect navigation signals
    nav_agent.velocity_computed.connect(_on_velocity_computed)
    
func _physics_process(delta: float) -> void:
    if is_dead:
        return
        
    # Update components
    vision.update(delta)
    intention.update(delta)
    locomotion.update(delta)
    body.update(delta)

# Event handlers
func on_injured(damage: float, attacker: Node = null) -> void:
    health -= damage
    
    if health <= 0:
        is_dead = true
        body.play_animation("death")
        intention.change_behavior("dead")
        return
        
    # Coordinate component responses
    body.play_animation("flinch")
    vision.update_threat(attacker)
    intention.evaluate_retreat_need()
    locomotion.prepare_retreat_movement()

func on_sight(entity: Node) -> void:
    vision.register_entity(entity)
    intention.evaluate_threat(entity)

func on_lost_sight(entity: Node) -> void:
    vision.unregister_entity(entity)
    intention.evaluate_threat_lost(entity)

func on_stuck() -> void:
    locomotion.handle_stuck()
    intention.evaluate_stuck_state()

# Navigation callback
func _on_velocity_computed(safe_velocity: Vector3) -> void:
    velocity = safe_velocity
    move_and_slide()

# Utility functions
func is_health_low() -> bool:
    return health < health_threshold

func has_threats() -> bool:
    return vision.get_threats().size() > 0

func get_nearest_threat() -> Node:
    return vision.get_nearest_threat()

func move_toward(target_pos: Vector3) -> void:
    locomotion.move_to(target_pos)

func face_toward(target_pos: Vector3) -> void:
    body.face_toward(target_pos)

func play_animation(anim_name: String) -> void:
    body.play_animation(anim_name)

func can_see(target: Node) -> bool:
    return vision.can_see(target) 