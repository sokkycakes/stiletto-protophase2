extends Node
class_name BaseEnemyAI

signal player_noticed
signal player_lost
signal state_changed(old_state: String, new_state: String)

# State machine
enum States {
	IDLE,
	ALERT,
	CHASE,
	SEARCH,  # New state for searching when player is lost but awareness > 0
	ATTACK,
	STUNNED,
	DEAD
}

@export var current_state: States = States.IDLE
var previous_state: States = States.IDLE

# Debug settings
@export var debug_enabled: bool = false

# Awareness parameters
@export var awareness_radius: float = 10.0
@export var awareness_build_rate: float = 1.0
@export var awareness_decay_rate: float = 0.5
@export var awareness_threshold: float = 1.0

# Combat parameters
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.0
@export var attack_windup_time: float = 0.33  # Time in seconds for attack windup
var can_attack: bool = true
var is_winding_up: bool = false
var windup_timer: float = 0.0

# Search parameters
@export var scan_speed: float = 180.0  # Degrees per second (3 full rotations per second)
@export var scan_angle: float = 160.0  # Total angle to scan (80 degrees each way)
var current_scan_angle: float = 0.0
var scan_direction: float = 1.0  # 1 for right, -1 for left
var initial_rotation: float = 0.0  # Store the initial rotation when entering search

@export_node_path("Area3D") var awareness_area_path: NodePath
@export_node_path("Label3D") var debug_label_path: NodePath = NodePath("../Model/DebugLabel")
@onready var awareness_area: Area3D = get_node(awareness_area_path)
@onready var debug_label: Label3D = get_node(debug_label_path)
@onready var attack_system = get_node("../AttackSystem")

var current_awareness: float = 0.0
var player_in_range: bool = false
var player: Node3D = null
var last_known_player_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	if not awareness_area:
		push_error("Awareness Area not set in the inspector!")
		return
		
	# Connect signals
	awareness_area.body_entered.connect(_on_awareness_area_body_entered)
	awareness_area.body_exited.connect(_on_awareness_area_body_exited)
	
	# Initialize debug label
	if debug_label:
		debug_label.visible = debug_enabled
	
	# Initialize state
	change_state(States.IDLE)

func _process(delta: float) -> void:
	update_awareness(delta)
	update_state(delta)
	update_debug_info()

func update_awareness(delta: float) -> void:
	if player_in_range and is_instance_valid(player):
		# If we're searching and player re-enters range, immediately set awareness to max
		if current_state == States.SEARCH and current_awareness > 0:
			current_awareness = 1.0
			change_state(States.CHASE)
		else:
			# Normal awareness building
			current_awareness = min(current_awareness + awareness_build_rate * delta, 1.0)
		
		# Check if we've just noticed the player
		if current_awareness >= awareness_threshold and current_awareness - awareness_build_rate * delta < awareness_threshold:
			player_noticed.emit()
	else:
		# Decrease awareness when player is not in range
		current_awareness = max(current_awareness - awareness_decay_rate * delta, 0.0)
		
		# Check if we've just lost the player
		if current_awareness < awareness_threshold and current_awareness + awareness_decay_rate * delta >= awareness_threshold:
			player_lost.emit()

func update_state(delta: float) -> void:
	match current_state:
		States.IDLE:
			process_idle_state(delta)
		States.ALERT:
			process_alert_state(delta)
		States.CHASE:
			process_chase_state(delta)
		States.SEARCH:
			process_search_state(delta)
		States.ATTACK:
			process_attack_state(delta)
		States.STUNNED:
			process_stunned_state(delta)
		States.DEAD:
			process_dead_state(delta)

func process_idle_state(_delta: float) -> void:
	if current_awareness >= awareness_threshold:
		change_state(States.ALERT)

func process_alert_state(_delta: float) -> void:
	if current_awareness < awareness_threshold:
		change_state(States.IDLE)
	elif player and is_instance_valid(player):
		face_player()
		if get_distance_to_player() <= attack_range:
			change_state(States.ATTACK)
		else:
			change_state(States.CHASE)

func process_chase_state(_delta: float) -> void:
	if not player_in_range and current_awareness > 0:
		# Store last known position before switching to search
		if player and is_instance_valid(player):
			last_known_player_position = player.global_position
		change_state(States.SEARCH)
	elif current_awareness < awareness_threshold:
		change_state(States.IDLE)
	elif player and is_instance_valid(player):
		face_player()
		
		# Update navigation target if we have a navigation agent
		var nav_agent = owner.get_node_or_null("NavigationAgent3D")
		if nav_agent:
			nav_agent.target_position = player.global_position
		
		if get_distance_to_player() <= attack_range:
			change_state(States.ATTACK)

func process_search_state(delta: float) -> void:
	if player_in_range and is_instance_valid(player):
		# Player found again, go back to chase
		change_state(States.CHASE)
	elif current_awareness <= 0:
		# Lost all awareness, go back to idle
		change_state(States.IDLE)
	else:
		# Update scan angle
		current_scan_angle += scan_speed * scan_direction * delta
		
		# Check if we've reached the scan limits
		if abs(current_scan_angle) >= scan_angle / 2.0:
			# Reverse direction
			scan_direction *= -1
			# Clamp the angle to prevent overshooting
			current_scan_angle = (scan_angle / 2.0) * sign(current_scan_angle)
		
		# Apply the rotation
		owner.rotation.y = initial_rotation + deg_to_rad(current_scan_angle)
		
		if debug_label:
			print("Scan angle: ", current_scan_angle, " Direction: ", scan_direction)

func process_attack_state(delta: float) -> void:
	if not player_in_range and current_awareness > 0:
		# Store last known position before switching to search
		if player and is_instance_valid(player):
			last_known_player_position = player.global_position
		change_state(States.SEARCH)
	elif current_awareness < awareness_threshold:
		change_state(States.IDLE)
	elif player and is_instance_valid(player):
		face_player()
		if get_distance_to_player() > attack_range:
			change_state(States.CHASE)
		elif can_attack and not is_winding_up:
			if debug_label:
				print("Starting attack - Distance to player: ", get_distance_to_player())
			start_attack_windup()
		elif is_winding_up:
			update_attack_windup(delta)

func process_stunned_state(_delta: float) -> void:
	# Implement stun duration and recovery logic here
	pass

func process_dead_state(_delta: float) -> void:
	# Implement death behavior here
	pass

func change_state(new_state: States) -> void:
	if new_state == current_state:
		return
		
	previous_state = current_state
	current_state = new_state
	
	# Initialize search state variables when entering search
	if new_state == States.SEARCH:
		initial_rotation = owner.rotation.y
		current_scan_angle = 0.0
		scan_direction = 1.0
	
	state_changed.emit(States.keys()[previous_state], States.keys()[current_state])

func get_distance_to_player() -> float:
	if not player or not is_instance_valid(player):
		return INF
	return owner.global_position.distance_to(player.global_position)

func start_attack_windup() -> void:
	is_winding_up = true
	windup_timer = 0.0
	if debug_label:
		print("Starting attack windup")

func update_attack_windup(delta: float) -> void:
	windup_timer += delta
	if windup_timer >= attack_windup_time:
		if debug_label:
			print("Windup complete, performing attack")
		perform_attack()
		is_winding_up = false

func perform_attack() -> void:
	if not can_attack or not player or not is_instance_valid(player):
		if debug_label:
			print("Attack failed - can_attack: ", can_attack, " player valid: ", is_instance_valid(player))
		return
		
	# Start the attack through the attack system
	if attack_system:
		attack_system.start_attack()
	
	# Start cooldown
	can_attack = false
	await get_tree().create_timer(attack_cooldown).timeout
	can_attack = true

func update_debug_info() -> void:
	if not debug_label:
		return
		
	debug_label.visible = debug_enabled
	if not debug_enabled:
		return
		
	var percentage = (current_awareness / awareness_threshold) * 100
	debug_label.text = "Awareness: %.1f%%\nState: %s" % [percentage, States.keys()[current_state]]
	
	# Change color based on awareness
	var color = Color(1, 1, 1, 1)  # White
	if player_in_range:
		color = Color(1, 0, 0, 1)  # Red when noticed
	elif current_awareness > 0:
		color = Color(1, 0.5, 0, 1)  # Orange when building awareness
	debug_label.modulate = color

func _on_awareness_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player = body
		player_in_range = true
		if debug_label:
			print("Player entered awareness area")
			print("Player position: ", player.global_position)
			print("Enemy position: ", owner.global_position)

func _on_awareness_area_body_exited(body: Node3D) -> void:
	if body == player:
		player = null
		player_in_range = false
		if debug_label:
			print("Player exited awareness area")

func face_player() -> void:
	if not player:
		return
		
	# Get direction to player, but only on the XZ plane
	var direction = (player.global_position - owner.global_position)
	direction.y = 0  # Keep the enemy upright
	direction = direction.normalized()
	
	if direction != Vector3.ZERO:
		# Calculate the angle to rotate to face the player
		var current_forward = -owner.global_transform.basis.z  # Current forward direction
		current_forward.y = 0
		current_forward = current_forward.normalized()
		
		# Calculate the angle between current forward and target direction
		var angle = current_forward.signed_angle_to(direction, Vector3.UP)
		
		# Only print debug if the angle is significant (more than 5 degrees)
		if abs(angle) > deg_to_rad(5.0):
			if debug_label:
				print("Rotating enemy by angle: ", rad_to_deg(angle))
		
		# Rotate around Y axis only
		owner.rotate_y(angle)

func get_movement_direction() -> Vector3:
	if current_state != States.CHASE or not player_in_range or not player:
		return Vector3.ZERO
		
	# Check if we have a navigation agent
	var nav_agent = owner.get_node_or_null("NavigationAgent3D")
	if nav_agent:
		# Use navigation agent for pathfinding
		if not nav_agent.is_target_reachable():
			# Target unreachable, stop moving
			return Vector3.ZERO
		
		if nav_agent.is_navigation_finished():
			# Navigation finished, stop moving
			return Vector3.ZERO
		
		var next_pos = nav_agent.get_next_path_position()
		if next_pos == Vector3.ZERO:
			# No valid path, stop moving
			return Vector3.ZERO
		
		# Move towards next navigation point
		var direction = (next_pos - owner.global_position).normalized()
		direction.y = 0  # Keep movement on the ground plane
		return direction
	else:
		# No navigation agent, use direct path but be more conservative
		var direction = (player.global_position - owner.global_position).normalized()
		direction.y = 0  # Keep movement on the ground plane
		
		# Only move if we're not too close to obstacles (simple distance check)
		var distance_to_player = owner.global_position.distance_to(player.global_position)
		if distance_to_player < 2.0:  # Stop if too close to avoid wall collisions
			return Vector3.ZERO
		
		return direction

func get_awareness_percentage() -> float:
	return current_awareness
