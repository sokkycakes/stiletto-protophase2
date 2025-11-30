extends Control

# HP HUD Element Script
# Handles health display with shake effects and icon changes

@export var shake_intensity: float = 10.0  # Increased for better visibility
@export var shake_duration: float = 0.5   # Increased duration
@export var shake_decay: float = 0.8

# Icon textures for different health states
@export var full_health_texture: Texture2D
@export var hurt_texture: Texture2D
@export var dead_texture: Texture2D

# Node references
@onready var icon: TextureRect = $icon2
@onready var shadow: TextureRect = $shadow

# Manual PlayerState assignment (optional)
@export var manual_player_state: NodePath

# Shake variables
var shake_timer: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var original_position: Vector2

# Health tracking
var current_health: int = 3
var max_health: int = 3
var is_dead: bool = false

# Player and health component references
var player: CharacterBody3D = null
var health_component: Node = null
var player_state: Node = null

func _ready() -> void:
	# Store original position for shake calculations
	original_position = position
	
	# Find the player in the "player" group
	await get_tree().process_frame  # Wait one frame to ensure all nodes are ready
	_find_player()
	
	# Set initial icon
	_update_icon()

func _find_player() -> void:
	# Attempt 0: Use manually assigned PlayerState (highest priority)
	if manual_player_state:
		var manual_ps = get_node_or_null(manual_player_state)
		if manual_ps:
			player_state = manual_ps
			player = manual_ps.get_parent() as CharacterBody3D
			health_component = manual_ps.get_node_or_null("Health")
			if player and health_component:
				_connect_to_components()
				return
	
	# Attempt 1: Find the player via the "player" group (preferred)
	var players = get_tree().get_nodes_in_group("player")
	
	# Attempt 2: Search the entire scene tree for a PlayerState node (recursive)
	if players.size() == 0:
		var ps_node: Node = get_tree().current_scene.find_child("PlayerState", true, false)
		if ps_node:
			var parent_candidate = ps_node.get_parent()
			if parent_candidate is CharacterBody3D:
				players.append(parent_candidate)

	if players.size() > 0:
		player = players[0] as CharacterBody3D
		if player:
			# Locate PlayerState (holds Health as a child)
			player_state = player.get_node_or_null("PlayerState")
			# Prefer Health under PlayerState; fallback to direct child for legacy setups
			if player_state:
				health_component = player_state.get_node_or_null("Health")
			else:
				health_component = player.get_node_or_null("Health")
			
			_connect_to_components()

func _connect_to_components() -> void:
	# Connect to both health component and player state if they exist
	var connected_to_health = false
	var connected_to_state = false
	
	# Try to connect to health component
	if health_component:
		if health_component.has_signal("health_changed"):
			health_component.health_changed.connect(_on_health_changed)
			connected_to_health = true
		if health_component.has_signal("damage_taken"):
			health_component.damage_taken.connect(_on_damage_taken)
			connected_to_health = true
		if health_component.has_signal("died"):
			health_component.died.connect(_on_player_died)
			connected_to_health = true
		
		# Get initial health values from health component
		if health_component.has_method("get_current_health"):
			current_health = health_component.get_current_health()
			max_health = health_component.max_health
			_update_icon()
	
	# Try to connect to player state
	if player_state:
		if player_state.has_signal("hit_taken"):
			player_state.hit_taken.connect(_on_hit_taken)
			connected_to_state = true
		if player_state.has_signal("player_died"):
			player_state.player_died.connect(_on_player_died)
			connected_to_state = true
	
	# Connection status tracking (for debugging if needed)
	# if connected_to_health:
	# 	print("HP HUD: Connected to health component")
	# if connected_to_state:
	# 	print("HP HUD: Connected to player state")
	# if not connected_to_health and not connected_to_state:
	# 	print("HP HUD: No signals found on health component or player state")

func _process(delta: float) -> void:
	# Handle shake effect
	if shake_timer > 0:
		shake_timer -= delta
		
		# Calculate shake offset
		var shake_progress = shake_timer / shake_duration
		var current_intensity = shake_intensity * shake_progress
		
		shake_offset = Vector2(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)
		
		# Apply shake offset
		position = original_position + shake_offset
		
		# Add visual feedback during shake (temporarily change color)
		if icon:
			icon.modulate = Color.RED if shake_timer > shake_duration * 0.8 else Color.WHITE
		
		# Stop shake when timer expires
		if shake_timer <= 0:
			position = original_position
			shake_offset = Vector2.ZERO
			if icon:
				# Restore appropriate color based on health state
				if current_health == max_health:
					icon.modulate = Color(0.3, 0.6, 1.0, 1.0)  # Blue at full health
				else:
					icon.modulate = Color.WHITE

func _on_health_changed(new_health: int, health_max: int) -> void:
	print("[HP HUD] _on_health_changed called - new_health: ", new_health, ", max: ", health_max, ", was_dead: ", is_dead)
	current_health = new_health
	max_health = health_max
	# Reset dead state if health is restored
	if new_health > 0:
		print("[HP HUD] Resetting is_dead from ", is_dead, " to false")
		is_dead = false
	_update_icon()

func _on_damage_taken(amount: int, new_health: int, health_max: int) -> void:
	# Trigger shake effect when taking damage
	_start_shake()
	
	# Update health values
	current_health = new_health
	max_health = health_max
	_update_icon()

func _on_hit_taken(current_hits: int, max_hits: int) -> void:
	# Trigger shake effect when taking damage
	_start_shake()
	
	# Update health values (convert hits to health)
	current_health = max_hits - current_hits
	max_health = max_hits
	_update_icon()

func _on_player_died() -> void:
	print("[HP HUD] _on_player_died called - setting is_dead to true")
	is_dead = true
	_update_icon()

func _start_shake() -> void:
	shake_timer = shake_duration

func _update_icon() -> void:
	if not icon:
		return
	
	# Determine which texture to use based on health state
	var target_texture: Texture2D
	
	if is_dead or current_health <= 0:
		print("[HP HUD] _update_icon - Showing DEAD texture (is_dead: ", is_dead, ", health: ", current_health, ")")
		target_texture = dead_texture
	elif current_health == 1:
		# Show hurt texture only when at exactly 1 HP
		print("[HP HUD] _update_icon - Showing HURT texture (health: ", current_health, "/", max_health, ")")
		target_texture = hurt_texture
	else:
		print("[HP HUD] _update_icon - Showing FULL texture (health: ", current_health, "/", max_health, ")")
		target_texture = full_health_texture
	
	# Update both icon and shadow textures
	if target_texture:
		icon.texture = target_texture
		if shadow:
			shadow.texture = target_texture
	
	# Apply blue color when at full health (only to icon, not shadow)
	if current_health == max_health:
		icon.modulate = Color(0.3, 0.6, 1.0, 1.0)  # Blue color
	else:
		# Reset to white for other states
		icon.modulate = Color.WHITE

# Public methods for external control
func set_health(health: int, max_hp: int) -> void:
	current_health = health
	max_health = max_hp
	is_dead = (health <= 0)
	_update_icon()

func trigger_shake() -> void:
	_start_shake()

func set_dead(dead: bool) -> void:
	is_dead = dead
	_update_icon()

# Test functions for manual testing (debugging disabled)
func test_take_damage() -> void:
	if current_health > 0:
		current_health -= 1
		_start_shake()
		_update_icon()

func test_shake_only() -> void:
	_start_shake()

func test_heal() -> void:
	if current_health < max_health:
		current_health += 1
		_update_icon()

func test_die() -> void:
	is_dead = true
	current_health = 0
	_start_shake()
	_update_icon()

func test_resurrect() -> void:
	is_dead = false
	current_health = max_health
	_update_icon() 
