extends Node

class_name KickbackModule

@export_group("Module Settings")
@export var enabled: bool = true

@export_group("Kickback variables")
@export var baseKickbackAmount : float = 10.0
@export var wallKickbackMultiplier : float = 2.0
@export var waitTimeBefCanUseKickAgain : float = 1.0
@export var onFloorKickbackDivider : float = 2.0
@export var wallDetectionDistance : float = 0.5  # Reduced to 50cm range

# --- Air-dodge configuration ---
@export_group("Air Dodge variables")
@export var airDodgeImpulse : float = 10.0 # Horizontal impulse applied during dodge
@export var maxAirDodges : int = 1        # How many dodges allowed before touching ground
@export var airDodgeVerticalBoost : float = 0.0 # Minimum upward velocity after dodge (0 = stall)
@export var airDodgeNoInputStallDuration : float = 0.2 # Seconds to null gravity when no input
@export var airDodgeSound : AudioStream # Optional distinct sound for air dodge

# --- Camera FOV Effect ---
@export_group("Air Dodge FOV Effect")
@export var fovDodgeChange : float = 8.0   # Degrees to add to FOV (zoom out)
@export var fovReturnDuration : float = 0.4 # Seconds to return to original FOV

@export_group("Sound Settings")
@export var kickbackSound: AudioStream
@export var audio_bus: String = "Master" # Audio bus to play sounds through

var waitTimeBefCanUseKickAgainRef : float
var player : CharacterBody3D
var camera : Camera3D
var debugLine : ImmediateMesh
var debugMesh : MeshInstance3D
var audioPlayer : AudioStreamPlayer
# Track remaining dodges during current airborne phase
var remainingAirDodges : int
var stallTimer : float = 0.0
var originalFOV : float = -1.0
var fovTween : Tween

func _ready():
	waitTimeBefCanUseKickAgainRef = waitTimeBefCanUseKickAgain
	# Get the player character by finding the Body node relative to this node
	player = get_node("../Body")
	# Get the camera
	camera = get_node("../Interpolated Camera/Arm/Arm Anchor/Camera")
	
	# Create debug visualization
	debugLine = ImmediateMesh.new()
	debugMesh = MeshInstance3D.new()
	debugMesh.mesh = debugLine
	debugMesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(debugMesh)
	
	# Setup audio player
	audioPlayer = AudioStreamPlayer.new()
	add_child(audioPlayer)
	if kickbackSound:
		audioPlayer.stream = kickbackSound
	audioPlayer.bus = audio_bus
	# Initialise air-dodge counter
	remainingAirDodges = maxAirDodges

	# Store original FOV
	if camera:
		originalFOV = camera.fov
	
	if player == null:
		push_error("KickbackModule: Could not find player Body node!")
	else:
		print("KickbackModule: Found player character")
	
	if camera == null:
		push_error("KickbackModule: Could not find camera!")

func _process(delta):
	if not enabled:
		return
		
	if player == null or camera == null:
		return
		
	if waitTimeBefCanUseKickAgain > 0.0:
		waitTimeBefCanUseKickAgain -= delta

	# Reset air-dodge charges and stall when player lands
	if player.is_on_floor():
		remainingAirDodges = maxAirDodges
		stallTimer = 0.0

	# Apply stall (cancel gravity) if active
	if stallTimer > 0.0:
		stallTimer -= delta
		# Cancel downward velocity to "freeze" vertical movement
		if player.velocity.y < 0:
			player.velocity.y = 0
	
	# Update debug visualization
	update_debug_line()
	
	# Don't handle input if player is dead (but allow during stunned state)
	var player_state = get_node_or_null("../Body/PlayerState")
	if player_state and player_state.is_in_dead_state():
		return
	
	if Input.is_action_just_pressed("pm_gunjump"):  # We'll keep the same input for now
		print("KickbackModule: Kick button pressed")
		use_kickback()

func update_debug_line():
	debugLine.clear_surfaces()
	debugLine.surface_begin(Mesh.PRIMITIVE_LINES)
	
	# Draw the detection line
	var color = Color.RED if player.is_on_floor() else Color.GREEN
	debugLine.surface_set_color(color)
	debugLine.surface_add_vertex(Vector3.ZERO)
	debugLine.surface_add_vertex(Vector3(0, 0, -wallDetectionDistance))
	
	debugLine.surface_end()

func use_kickback():
	if not enabled:
		return false
		
	if player == null or camera == null:
		print("KickbackModule: Cannot use kickback - player or camera is null")
		return false
		
	# If on the ground, attempt normal kickback
	if player.is_on_floor():
		if waitTimeBefCanUseKickAgain <= 0.0:
			waitTimeBefCanUseKickAgain = waitTimeBefCanUseKickAgainRef
			var kickbackOrientation = -camera.global_transform.basis.z.normalized()
			var kickbackAmount = baseKickbackAmount * wallKickbackMultiplier
			# Add a small upward boost when kicking off the floor
			kickbackOrientation.y += 0.2
			apply_kickback(kickbackAmount, kickbackOrientation)
			return true
		else:
			print("KickbackModule: On cooldown - ", waitTimeBefCanUseKickAgain)
			return false
	else:
		# In the air → try an air-dodge instead
		return use_air_dodge()

# Helper --------------------------------------------------------------
func _is_hook_active() -> bool:
	var nodes = get_tree().get_nodes_in_group("hook_controller")
	if nodes.size() > 0:
		var hc = nodes[0]
		var state = hc.get("current_state")
		if state != null and state != hc.GrappleState.IDLE:
			return true
	return false

# --- New: air-dodge logic -----------------------------------------------------
func use_air_dodge() -> bool:
	# Do not allow air-dodge while grappling / kickboost is active
	if _is_hook_active():
		return false
	
	if remainingAirDodges <= 0:
		print("KickbackModule: No air dodges remaining")
		return false

	remainingAirDodges -= 1
	print("KickbackModule: Performing air dodge (remaining: %d)" % remainingAirDodges)

	# Determine desired dodge direction based on current movement input
	var ix = Input.get_action_strength("pm_moveright") - Input.get_action_strength("pm_moveleft")
	var iy = Input.get_action_strength("pm_moveforward") - Input.get_action_strength("pm_movebackward")
	var input_vec2 = Vector2(ix, iy)

	var horiz_impulse : Vector3 = Vector3.ZERO
	if input_vec2.length() > 0.1:
		# Convert 2D input to world space relative to camera orientation
		var right_dir = camera.global_transform.basis.x.normalized()
		var forward_dir = -camera.global_transform.basis.z.normalized()
		var dodge_dir = (right_dir * input_vec2.x + forward_dir * input_vec2.y).normalized()
		horiz_impulse = dodge_dir * airDodgeImpulse
	else:
		# No input → stall vertical descent for a short period
		stallTimer = airDodgeNoInputStallDuration

	# Apply horizontal impulse (if any)
	player.velocity.x += horiz_impulse.x
	player.velocity.z += horiz_impulse.z

	# Stall or boost vertical component
	player.velocity.y = max(player.velocity.y, airDodgeVerticalBoost)

	# Play dodge-specific sound if provided
	if airDodgeSound:
		audioPlayer.stream = airDodgeSound
	elif kickbackSound:
		audioPlayer.stream = kickbackSound
	audioPlayer.play()

	# Trigger FOV effect
	perform_fov_dodge()
	
	return true

func apply_kickback(kickbackAmount : float, kickbackOrientation : Vector3):
	if player == null:
		return
		
	var kickbackForce = -kickbackOrientation * kickbackAmount
	print("KickbackModule: Kickback force = ", kickbackForce)
	
	if player.is_on_floor():
		player.velocity += kickbackForce / onFloorKickbackDivider
		print("KickbackModule: Applied ground kickback")
	else:
		player.velocity += kickbackForce
		print("KickbackModule: Applied air kickback")
	
	# Play kickback sound
	if kickbackSound:
		audioPlayer.stream = kickbackSound
		audioPlayer.play()

func get_remaining_cooldown() -> float:
	return waitTimeBefCanUseKickAgain 

# Reindent function with tabs
func perform_fov_dodge():
	if camera == null:
		return

	if originalFOV < 0:
		originalFOV = camera.fov

	# Kill existing tween if active
	if fovTween and fovTween.is_valid():
		fovTween.kill()

	# Immediately apply the reduced FOV
	camera.fov = originalFOV + fovDodgeChange

	# Tween back to original
	fovTween = create_tween()
	fovTween.tween_property(camera, "fov", originalFOV, fovReturnDuration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) 
