extends Node

class_name KickbackModulev2

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
## Horizontal impulse in Hammer Units (1 HU = 1 inch, 39.37 HU = 1 meter)
@export var airDodgeImpulseHU : float = 393.7 # Horizontal impulse applied during dodge
@export var maxAirDodges : int = 1        # How many dodges allowed before touching ground
@export var airDodgeVerticalBoost : float = 0.0 # Minimum upward velocity after dodge (0 = stall)
@export var airDodgeSound : AudioStream # Optional distinct sound for air dodge
@export var airDodgeMinDuration : float = 0.2 # Minimum time at full speed before decay starts
@export var airDodgeDecayDuration : float = 1.0 # Total time for velocity to decay back to ground velocity
@export var airDodgeDecayCurve : Curve # Controls how the dodge speed decays (0=ground velocity, 1=dodge velocity)
## Speed cap in Hammer Units (1 HU = 1 inch, 39.37 HU = 1 meter). Above this, decay accelerates
@export var airDodgeSpeedCapHU : float = 787.4 # Speed above which decay accelerates to prevent runaway speed
## Minimum speed in Hammer Units (1 HU = 1 inch, 39.37 HU = 1 meter). Prevents complete stop during decay
@export var airDodgeMinDecaySpeedHU : float = 220.0 # Minimum speed during decay (prevents coming to complete stop)
## Enable accelerated decay when moving faster than speed cap
@export var airDodgeEnableSpeedCapDecay : bool = true # Whether to accelerate decay when exceeding speed cap
## Controls how aggressively decay accelerates above speed cap. 1.0 = linear increase, higher = more aggressive
@export var airDodgeDecayAccelerationFactor : float = 1.0 # Multiplier for decay acceleration (1.0 = excess_speed/cap, 2.0 = 2x that rate)

# --- Air-stall configuration (no input) ---
@export_group("Air Stall variables")
@export var maxAirStalls : int = 1        # How many stalls allowed before touching ground
@export var airStallDuration : float = 0.2 # Seconds to null gravity when no input
@export var airStallSound : AudioStream # Optional distinct sound for air stall

# --- Air Stall Camera Effect ---
@export_group("Air Stall Camera Effect")
@export var stallCameraTiltAngle : float = -5.0  # Degrees to tilt down (negative = down)
@export var stallCameraReturnDuration : float = 0.3  # Seconds to return to normal rotation
@export var stallCameraEaseType : Tween.EaseType = Tween.EASE_OUT  # Easing type for return

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
# Track remaining dodges and stalls during current airborne phase
var remainingAirDodges : int
var remainingAirStalls : int
var stallTimer : float = 0.0
var originalFOV : float = -1.0
var fovTween : Tween
var cameraTiltTween : Tween
var originalCameraRotation : Vector3 = Vector3.ZERO
# Air dodge decay system
var groundVelocity : Vector3 = Vector3.ZERO  # Velocity when player was last on ground
var dodgeStartVelocity : Vector3 = Vector3.ZERO  # Velocity right after dodge impulse
var dodgeTimer : float = 0.0  # Time since dodge started
var isDodging : bool = false  # Whether we're currently in a dodge decay state

# Conversion constants (Hammer Units to Godot meters)
const HU_TO_METERS : float = 1.0 / 39.37  # 1 HU = 1 inch, 39.37 inches = 1 meter

# Computed properties - convert from Hammer Units to Godot meters
var airDodgeImpulse : float:
	get:
		return airDodgeImpulseHU * HU_TO_METERS

var airDodgeSpeedCap : float:
	get:
		return airDodgeSpeedCapHU * HU_TO_METERS

var airDodgeMinDecaySpeed : float:
	get:
		return airDodgeMinDecaySpeedHU * HU_TO_METERS

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
	# Initialise air-dodge and air-stall counters
	remainingAirDodges = maxAirDodges
	remainingAirStalls = maxAirStalls

	# Store original FOV and camera rotation
	if camera:
		originalFOV = camera.fov
		originalCameraRotation = camera.rotation
	
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
		remainingAirStalls = maxAirStalls
		stallTimer = 0.0
		isDodging = false
		dodgeTimer = 0.0
		# Store ground velocity (excluding vertical component)
		groundVelocity = Vector3(player.velocity.x, 0, player.velocity.z)

	# Apply stall (cancel gravity) if active
	if stallTimer > 0.0:
		stallTimer -= delta
		# Cancel downward velocity to "freeze" vertical movement
		if player.velocity.y < 0:
			player.velocity.y = 0
	
	# Apply dodge velocity decay
	if isDodging:
		dodgeTimer += delta
		apply_dodge_decay()
	
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

	# Determine desired dodge direction based on current movement input
	var ix = Input.get_action_strength("pm_moveright") - Input.get_action_strength("pm_moveleft")
	var iy = Input.get_action_strength("pm_moveforward") - Input.get_action_strength("pm_movebackward")
	var input_vec2 = Vector2(ix, iy)

	var has_input = input_vec2.length() > 0.1

	if has_input:
		# Air dodge with directional input
		if remainingAirDodges <= 0:
			print("KickbackModule: No air dodges remaining")
			return false

		remainingAirDodges -= 1
		print("KickbackModule: Performing air dodge (remaining: %d)" % remainingAirDodges)

		# Convert 2D input to world space relative to camera orientation
		var right_dir = camera.global_transform.basis.x.normalized()
		var forward_dir = -camera.global_transform.basis.z.normalized()
		var dodge_dir = (right_dir * input_vec2.x + forward_dir * input_vec2.y).normalized()
		var horiz_impulse = dodge_dir * airDodgeImpulse

		# Apply horizontal impulse
		player.velocity.x += horiz_impulse.x
		player.velocity.z += horiz_impulse.z

		# Stall or boost vertical component
		player.velocity.y = max(player.velocity.y, airDodgeVerticalBoost)

		# Start dodge decay system
		isDodging = true
		dodgeTimer = 0.0
		dodgeStartVelocity = Vector3(player.velocity.x, 0, player.velocity.z)

		# Play dodge-specific sound if provided
		if airDodgeSound:
			audioPlayer.stream = airDodgeSound
		elif kickbackSound:
			audioPlayer.stream = kickbackSound
		audioPlayer.play()

		# Trigger FOV effect
		perform_fov_dodge()
		
		return true
	else:
		# Air stall (no directional input)
		if remainingAirStalls <= 0:
			print("KickbackModule: No air stalls remaining")
			return false

		remainingAirStalls -= 1
		print("KickbackModule: Performing air stall (remaining: %d)" % remainingAirStalls)

		# Stall vertical descent for a short period
		stallTimer = airStallDuration

		# Play stall-specific sound if provided
		if airStallSound:
			audioPlayer.stream = airStallSound
		elif kickbackSound:
			audioPlayer.stream = kickbackSound
		audioPlayer.play()

		# Trigger camera tilt effect for stall
		perform_camera_tilt_stall()
		
		return true

func apply_dodge_decay():
	# If we haven't met minimum duration yet, maintain full dodge velocity
	if dodgeTimer < airDodgeMinDuration:
		return
	
	# Calculate how far we are into the decay phase
	var decay_time = dodgeTimer - airDodgeMinDuration
	
	# Speed up decay if moving too fast (prevents runaway speed from bhop chaining)
	var current_speed = Vector3(player.velocity.x, 0, player.velocity.z).length()
	var speed_multiplier = 1.0
	if airDodgeEnableSpeedCapDecay and current_speed > airDodgeSpeedCap:
		# Accelerate decay based on how much we exceed the cap
		var excess_ratio = (current_speed - airDodgeSpeedCap) / airDodgeSpeedCap
		speed_multiplier = 1.0 + (excess_ratio * airDodgeDecayAccelerationFactor)
	
	var total_decay_time = airDodgeDecayDuration / speed_multiplier
	
	# If we've completed the decay, stop processing
	if decay_time >= total_decay_time:
		isDodging = false
		return
	
	# Calculate normalized time (0 to 1) through the decay phase
	var normalized_time = clamp(decay_time / total_decay_time, 0.0, 1.0)
	
	# Get the blend factor from the curve (1 = dodge velocity, 0 = ground velocity)
	var blend_factor = 1.0
	if airDodgeDecayCurve != null:
		# Curve should go from 1.0 (full dodge) to 0.0 (ground velocity)
		blend_factor = airDodgeDecayCurve.sample(normalized_time)
	else:
		# Fallback to linear decay if no curve is set
		blend_factor = 1.0 - normalized_time
	
	# Get current horizontal velocity to preserve direction
	var current_horiz_vel = Vector3(player.velocity.x, 0, player.velocity.z)
	
	# Only decay back to ground velocity if we're moving in a similar direction
	# Otherwise, decay toward zero to prevent backwards acceleration
	var dot_product = current_horiz_vel.normalized().dot(groundVelocity.normalized()) if current_horiz_vel.length() > 0.1 and groundVelocity.length() > 0.1 else -1.0
	
	# Ensure ground velocity meets minimum speed requirement
	var min_ground_velocity = groundVelocity
	if min_ground_velocity.length() < airDodgeMinDecaySpeed and min_ground_velocity.length() > 0.01:
		min_ground_velocity = min_ground_velocity.normalized() * airDodgeMinDecaySpeed
	elif min_ground_velocity.length() < 0.01 and current_horiz_vel.length() > 0.1:
		# If ground velocity was zero, use current direction at minimum speed
		min_ground_velocity = current_horiz_vel.normalized() * airDodgeMinDecaySpeed
	
	var target_velocity : Vector3
	if dot_product > 0.5:  # Moving in similar direction (within ~60 degrees)
		# Safe to decay back to ground velocity (with minimum enforced)
		target_velocity = dodgeStartVelocity.lerp(min_ground_velocity, 1.0 - blend_factor)
	else:
		# Different direction - decay toward minimum speed in current direction
		var min_velocity_in_current_dir = current_horiz_vel.normalized() * airDodgeMinDecaySpeed if current_horiz_vel.length() > 0.1 else Vector3.ZERO
		target_velocity = dodgeStartVelocity.lerp(min_velocity_in_current_dir, 1.0 - blend_factor)
	
	# Enforce minimum speed floor (maintain direction but ensure minimum magnitude)
	if target_velocity.length() < airDodgeMinDecaySpeed and target_velocity.length() > 0.1:
		target_velocity = target_velocity.normalized() * airDodgeMinDecaySpeed
	
	# Apply the calculated velocity (preserve vertical component)
	player.velocity.x = target_velocity.x
	player.velocity.z = target_velocity.z

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

func perform_camera_tilt_stall():
	if camera == null:
		return

	# Store original rotation if not already stored
	if originalCameraRotation == Vector3.ZERO:
		originalCameraRotation = camera.rotation

	# Kill existing tween if active
	if cameraTiltTween and cameraTiltTween.is_valid():
		cameraTiltTween.kill()

	# Calculate target rotation with downward tilt
	var target_rotation = originalCameraRotation + Vector3(deg_to_rad(stallCameraTiltAngle), 0, 0)

	# Immediately apply the tilted rotation
	camera.rotation = target_rotation

	# Tween back to original rotation
	cameraTiltTween = create_tween()
	cameraTiltTween.tween_property(camera, "rotation", originalCameraRotation, stallCameraReturnDuration).set_trans(Tween.TRANS_SINE).set_ease(stallCameraEaseType) 
