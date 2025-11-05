extends Node
class_name BaseEnemyAILite

# ─────────────────────────────────────────────
#  Minimal Quake-style Enemy AI for Godot 4.4
#  – Controls parent CharacterBody3D to chase player
#    and perform melee attacks.
# ─────────────────────────────────────────────

@export var speed: float = 4.0                # Movement speed (m/s)
@export var melee_distance: float = 1.8       # Attack reach (metres)
@export var damage: int = 10                  # Damage dealt per hit
@export var attack_cooldown: float = 1.0      # Seconds between swings
@export var player_path: NodePath             # Assign player in the Inspector
@export var use_navigation: bool = true       # Toggle NavigationAgent3D usage
# Separation settings
@export var avoidance_radius: float = 1.2      # Minimum distance to maintain from other enemies (metres)
@export var avoidance_strength: float = 1.0    # Weight of avoidance vs chase

# Internal references ----------------------------------------------------------
var _player: Node3D
var _body: CharacterBody3D                    # Parent CharacterBody3D we're controlling
@onready var _nav_agent: NavigationAgent3D

# Attack state -----------------------------------------------------------------
var _can_attack: bool = true                  # Cooldown gate
# Track player death
var _player_dead: bool = false

# ─────────────────────────────────────────────
func _ready() -> void:
	# Get parent CharacterBody3D reference
	_body = get_parent() as CharacterBody3D
	if not _body:
		push_error("BaseEnemyAILite must be child of a CharacterBody3D!")
		return

	if has_node("../NavigationAgent3D"):
		_nav_agent = $"../NavigationAgent3D"
	else:
		_nav_agent = null

	# Resolve player reference (either via exported path or first node in group "player")
	_player = get_node_or_null(player_path)
	if _player == null and get_tree().get_nodes_in_group("player").size() > 0:
		_player = get_tree().get_nodes_in_group("player")[0]

	# Listen for player death signal if available
	if _player and _player.has_node("PlayerState"):
		var ps = _player.get_node("PlayerState")
		if ps and ps.has_signal("player_died"):
			ps.player_died.connect(_on_player_died)

	# Fallback: if player health emits died
	var health_node = _player.get_node_or_null("Health") if _player else null
	if health_node and health_node.has_signal("died"):
		health_node.died.connect(_on_player_died)

func _physics_process(delta: float) -> void:
	# Detect runtime death even if signal missed
	if not _player_dead and _player and _player.has_node("PlayerState"):
		var ps = _player.get_node("PlayerState")
		if ps and ps.has_variable("current_state") and ps.current_state == ps.PlayerState.DEAD:
			_player_dead = true

	if _player_dead or not is_instance_valid(_player) or not _body:
		return                                # No target or parent – nothing to do

	var distance := _body.global_position.distance_to(_player.global_position)

	if distance <= melee_distance:
		_attempt_melee()
		_body.velocity = Vector3.ZERO         # Hold position while swinging
		_body.move_and_slide()
	else:
		_chase_player(delta)

# Movement ---------------------------------------------------------------------
func _chase_player(_delta: float) -> void:
	var dir: Vector3
	if use_navigation and _nav_agent:
		_nav_agent.target_position = _player.global_position
		dir = (_nav_agent.get_next_path_position() - _body.global_position).normalized()
	else:
		dir = (_player.global_position - _body.global_position).normalized()

	dir.y = 0                                 # Stay horizontal

	# --- Simple separation -------------------------------------------------
	var avoid: Vector3 = Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == _body:
			continue
		if not e is Node3D:
			continue
		var delta := _body.global_position - (e as Node3D).global_position
		delta.y = 0
		var dist := delta.length()
		if dist > 0 and dist < avoidance_radius:
			avoid += delta.normalized() * ((avoidance_radius - dist) / avoidance_radius)
	if avoid != Vector3.ZERO:
		avoid = avoid.normalized() * avoidance_strength
	dir = (dir + avoid).normalized()

	_body.velocity.x = dir.x * speed
	_body.velocity.z = dir.z * speed
	_body.velocity.y = 0
	_body.move_and_slide()

# Combat -----------------------------------------------------------------------
func _attempt_melee() -> void:
	if not _can_attack:
		return

	_can_attack = false

	if _player.has_method("take_damage"):
		_player.take_hit()

	if has_node("../BaseEnemyAttackSystem"):  # Look for attack system in parent
		$"../BaseEnemyAttackSystem".start_attack()

	# Cooldown timer (async)
	await get_tree().create_timer(attack_cooldown).timeout
	_can_attack = true

# ---------------------------------------------------------------------------
func _on_player_died():
	_player_dead = true
