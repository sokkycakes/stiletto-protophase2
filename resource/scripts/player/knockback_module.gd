extends Node

class_name KnockbackModule

@export_group("Module Settings")
@export var enabled: bool = true

@export_group("Knockback variables")
@export var knockbackAmount : float = 10.0
@export var waitTimeBefCanUseKnobaAgain : float = 1.0
@export var onFloorKnockbackDivider : float = 2.0

var waitTimeBefCanUseKnobaAgainRef : float
var player : CharacterBody3D
var camera : Camera3D

func _ready():
	waitTimeBefCanUseKnobaAgainRef = waitTimeBefCanUseKnobaAgain
	# Get the player character by finding the node named "Body"
	player = get_node("/root/Node3D/ss_player/Body")
	# Get the camera
	camera = get_node("/root/Node3D/ss_player/Interpolated Camera/Arm/Arm Anchor/Camera")
	
	if player == null:
		push_error("KnockbackModule: Could not find player Body node!")
	else:
		print("KnockbackModule: Found player character")
	
	if camera == null:
		push_error("KnockbackModule: Could not find camera!")

func _process(delta):
	if not enabled:
		return
	
	if player == null or camera == null:
		return
	
	if waitTimeBefCanUseKnobaAgain > 0.0:
		waitTimeBefCanUseKnobaAgain -= delta
	
	# Don't handle input if player is dead (but allow during stunned state)
	var player_state = get_node_or_null("/root/Node3D/ss_player/Body/PlayerState")
	if player_state and player_state.is_in_dead_state():
		return
	
	if Input.is_action_just_pressed("pm_gunjump"):
		print("KnockbackModule: Gunjump button pressed")
		use_knockback()

func use_knockback():
	if not enabled:
		return false
	
	if player == null or camera == null:
		print("KnockbackModule: Cannot use knockback - player or camera is null")
		return false
	
	if waitTimeBefCanUseKnobaAgain <= 0.0:
		print("KnockbackModule: Applying knockback")
		waitTimeBefCanUseKnobaAgain = waitTimeBefCanUseKnobaAgainRef
		var knockbackOrientation = -camera.global_transform.basis.z.normalized()
		apply_knockback(knockbackAmount, knockbackOrientation)
		return true
	else:
		print("KnockbackModule: On cooldown - ", waitTimeBefCanUseKnobaAgain)
	return false

func apply_knockback(knockbackAmount : float, knockbackOrientation : Vector3):
	if player == null:
		return
	
	var knockbackForce = -knockbackOrientation * knockbackAmount
	print("KnockbackModule: Knockback force = ", knockbackForce)
	
	if player.is_on_floor():
		player.velocity += knockbackForce / onFloorKnockbackDivider
		print("KnockbackModule: Applied ground knockback")
	else:
		player.velocity += knockbackForce
		print("KnockbackModule: Applied air knockback")

func get_remaining_cooldown() -> float:
	return waitTimeBefCanUseKnobaAgain 
