extends CharacterBody3D

# Node references
@onready var state_module = %PlayerState
@onready var wall_movement = $WallMovement

# Movement parameters
@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 20.0

# Get the gravity from the project settings to be synced with RigidBody nodes
var gravity_scale = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	# Add to player groups for enemy detection
	add_to_group("player")
	add_to_group("players")
	
	# Connect state module signals
	if state_module:
		state_module.state_changed.connect(_on_state_changed)
		state_module.hit_taken.connect(_on_hit_taken)
		state_module.stunned_state_changed.connect(_on_stunned_state_changed)

func _physics_process(delta):
	# Add the gravity
	if not is_on_floor():
		velocity.y -= gravity_scale * delta

	# Handle movement only if not stunned or dead
	if not state_module or (not state_module.is_in_stunned_state() and not state_module.is_in_dead_state()):
		# Get the input direction and handle the movement/deceleration
		var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
		else:
			velocity.x = move_toward(velocity.x, 0, move_speed)
			velocity.z = move_toward(velocity.z, 0, move_speed)

		# Handle jump
		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = jump_velocity
	else:
		# Apply friction when stunned
		velocity.x = move_toward(velocity.x, 0, move_speed)
		velocity.z = move_toward(velocity.z, 0, move_speed)

	move_and_slide()

func take_hit() -> void:
	if state_module:
		state_module.take_hit()

func _on_state_changed(old_state: String, new_state: String) -> void:
	print("Player state changed from %s to %s" % [old_state, new_state])

func _on_hit_taken(current_hits: int, max_hits: int) -> void:
	print("Player took hit: %d/%d" % [current_hits, max_hits])

func _on_stunned_state_changed(is_stunned: bool) -> void:
	print("Player stunned state changed: %s" % is_stunned) 
