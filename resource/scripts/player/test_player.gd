extends CharacterBody3D
class_name TestPlayer

@export var speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var max_health: int = 100

var current_health: int = 100
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	print("[TestPlayer] Test player ready with health: ", current_health)
	add_to_group("player")

func _physics_process(delta):
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	# Get input direction
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input_dir != Vector2.ZERO:
		velocity.x = input_dir.x * speed
		velocity.z = input_dir.y * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)

	move_and_slide()

func take_damage(amount: float):
	current_health -= int(amount)
	print("[TestPlayer] Took ", amount, " damage! Health: ", current_health, "/", max_health)
	
	if current_health <= 0:
		print("[TestPlayer] Player died!")
		# Could add death logic here

func take_hit():
	take_damage(25)  # Default damage amount

func get_health() -> int:
	return current_health

func heal(amount: int):
	current_health = min(current_health + amount, max_health)
	print("[TestPlayer] Healed ", amount, " health! Health: ", current_health, "/", max_health)
