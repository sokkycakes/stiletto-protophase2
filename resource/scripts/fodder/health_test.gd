extends Node

# Test script for the new health system
# This can be attached to any node to test the health mechanics

@export var test_health_component: NodePath
var health: Node

func _ready() -> void:
	# Find the health component
	health = get_node_or_null(test_health_component)
	if not health:
		print("HealthTest: No health component found at path: ", test_health_component)
		return
	
	print("HealthTest: Found health component")
	print("HealthTest: Initial health: ", health.get_current_health(), "/", health.max_health)
	
	# Connect to health signals
	if health.has_signal("damage_taken"):
		health.damage_taken.connect(_on_damage_taken)
	if health.has_signal("health_changed"):
		health.health_changed.connect(_on_health_changed)
	if health.has_signal("invulnerability_started"):
		health.invulnerability_started.connect(_on_invulnerability_started)
	if health.has_signal("invulnerability_ended"):
		health.invulnerability_ended.connect(_on_invulnerability_ended)
	if health.has_signal("healing_started"):
		health.healing_started.connect(_on_healing_started)
	if health.has_signal("healing_completed"):
		health.healing_completed.connect(_on_healing_completed)

func _input(event: InputEvent) -> void:
	if not health:
		return
	
	# Test damage
	if event.is_action_pressed("test_damage"):
		print("HealthTest: Testing damage...")
		health.take_damage(1)
	
	# Test healing
	if event.is_action_pressed("test_heal"):
		print("HealthTest: Testing heal...")
		health.heal(1)
	
	# Test invulnerability
	if event.is_action_pressed("test_invulnerability"):
		print("HealthTest: Testing invulnerability...")
		health.take_damage(1)
		await get_tree().create_timer(0.1).timeout
		health.take_damage(1)  # This should be blocked
	
	# Test healing timer
	if event.is_action_pressed("test_healing_timer"):
		print("HealthTest: Testing healing timer...")
		health.take_damage(1)
		print("HealthTest: Damage taken, waiting for healing to start...")

func _on_damage_taken(amount: int, current_health: int, max_health: int) -> void:
	print("HealthTest: Damage taken - amount: ", amount, ", health: ", current_health, "/", max_health)

func _on_health_changed(current_health: int, max_health: int) -> void:
	print("HealthTest: Health changed - ", current_health, "/", max_health)

func _on_invulnerability_started() -> void:
	print("HealthTest: Invulnerability started")

func _on_invulnerability_ended() -> void:
	print("HealthTest: Invulnerability ended")

func _on_healing_started() -> void:
	print("HealthTest: Healing started")

func _on_healing_completed() -> void:
	print("HealthTest: Healing completed") 