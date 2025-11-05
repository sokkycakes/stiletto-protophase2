extends Node
class_name BaseEnemyAttackSystem

# -----------------------------------------------------------------------------
#  Simple melee-attack helper that works with the new BaseEnemyAI
#  • Activates a hit-box for `attack_duration` seconds.
#  • When the player is touched it applies knock-back and optional stun.
#  • It does NOT deal direct HP damage (AI script already calls take_damage()).
# -----------------------------------------------------------------------------

@export_node_path("Area3D") var attack_hitbox_path: NodePath
@export_node_path("AudioStreamPlayer") var attack_sound_path: NodePath
@onready var attack_hitbox: Area3D = get_node(attack_hitbox_path)
@onready var attack_sound: AudioStreamPlayer = get_node(attack_sound_path)

# Tunables ---------------------------------------------------------------------
@export var launch_force: float = 11.0            # Horizontal impulse strength
@export var launch_angle: float = 45.0            # Vertical arc (degrees)
@export var stun_time: float = 0.4                # Seconds the player is stunned
@export var attack_duration: float = 0.5          # How long the hit-box is active
@export var attack_cooldown: float = 1.0          # Delay before next swing
@export var debug_enabled: bool = false

# Internal state ----------------------------------------------------------------
var _can_attack: bool = true

# -----------------------------------------------------------------------------
func _ready() -> void:
	if attack_hitbox == null:
		push_error("Attack hitbox not set on %s" % name)
		return
	if attack_sound == null:
		push_error("Attack sound node not set on %s" % name)
		return

	attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)

	# Disable hit-box by default
	attack_hitbox.monitoring = false
	attack_hitbox.monitorable = false

# -----------------------------------------------------------------------------
#  Public entry – call from BaseEnemyAI._attempt_melee()
# -----------------------------------------------------------------------------
func start_attack() -> void:
	if not _can_attack:
		return

	_can_attack = false

	# Enable hit-box and play SFX
	attack_hitbox.monitoring  = true
	attack_hitbox.monitorable = true
	attack_sound.play()

	if debug_enabled:
		print("[AttackSystem] Hit-box active")

	await get_tree().create_timer(attack_duration).timeout

	# Disable hit-box after active window
	attack_hitbox.monitoring  = false
	attack_hitbox.monitorable = false

	if debug_enabled:
		print("[AttackSystem] Hit-box off – cooldown start")

	await get_tree().create_timer(attack_cooldown).timeout
	_can_attack = true

# -----------------------------------------------------------------------------
#  Collision callback
# -----------------------------------------------------------------------------
func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return

	if debug_enabled:
		print("[AttackSystem] Player contacted – applying launch / stun")

	_apply_launch_and_stun(body as CharacterBody3D)

# -----------------------------------------------------------------------------
#  Effect helpers
# -----------------------------------------------------------------------------
func _apply_launch_and_stun(player: CharacterBody3D) -> void:
	if player == null:
		return

	# --- Knock-back -----------------------------------------------------------
	var horizontal_dir := (player.global_position - get_parent().global_position)
	horizontal_dir.y = 0.0
	horizontal_dir = horizontal_dir.normalized()

	var launch_vec := horizontal_dir * launch_force
	launch_vec.y   = sin(deg_to_rad(launch_angle)) * launch_force
	player.velocity = launch_vec

	# --- Optional stun --------------------------------------------------------
	if player.has_method("apply_stun") and stun_time > 0.0:
		player.apply_stun(stun_time)

	if debug_enabled:
		print("[AttackSystem] Applied velocity: ", launch_vec) 
