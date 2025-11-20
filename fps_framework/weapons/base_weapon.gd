extends Node3D
class_name BaseWeapon

# --- Core shared weapon properties -------------------------------------------------
@export var clip_size: int = 6        # Max rounds in magazine
@export var ammo_in_clip: int = 6     # Current rounds
@export var fire_rate: float = 0.25   # Seconds between shots
@export var reload_time: float = 1.5  # Time to refill magazine
@export var bullet_damage: int = 10   # Damage dealt per hit
@export var maximum_distance: float = 1000.0
@export var spread_degrees: float = 1.0  # Cone half-angle in degrees

# Scenes for visual FX ---------------------------------------------------------
@export var muzzle_flash_scene: PackedScene
@export var impact_effect_scene: PackedScene
@export var bullet_trail_scene: PackedScene

# Where bullets originate (usually a BoneAttachment or Marker3D called "muzzle")
@export var muzzle_path: NodePath

# ------------------------------------------------------------------------------
signal fired                                # Emitted after each successful shot
signal reload_started                       # Emitted when reload begins
signal reload_finished                      # Emitted when reload completes
signal ammo_changed(current:int, max:int)   # Emitted whenever ammo changes

var _can_fire: bool = true
var _fire_timer: Timer
var _reload_timer: Timer

func _ready() -> void:
	# Timers for fire-rate limiting and reload handling
	_fire_timer = Timer.new()
	_fire_timer.one_shot = true
	_fire_timer.timeout.connect(_on_fire_timeout)
	add_child(_fire_timer)

	_reload_timer = Timer.new()
	_reload_timer.one_shot = true
	_reload_timer.timeout.connect(_on_reload_timeout)
	add_child(_reload_timer)

	emit_signal("ammo_changed", ammo_in_clip, clip_size)

# ------------------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------------------
func shoot() -> void:
	# Attempt to fire a single round (hitscan by default)
	if not _can_fire or ammo_in_clip <= 0:
		return

	ammo_in_clip -= 1
	emit_signal("ammo_changed", ammo_in_clip, clip_size)

	_spawn_muzzle_flash()
	_fire_hitscan()

	_can_fire = false
	_fire_timer.start(fire_rate)

	emit_signal("fired")

func start_reload() -> void:
	if ammo_in_clip == clip_size or _reload_timer.time_left > 0:
		return
	_can_fire = false
	_reload_timer.start(reload_time)
	emit_signal("reload_started")

# ------------------------------------------------------------------------------
# Internal helpers
# ------------------------------------------------------------------------------
func _on_fire_timeout() -> void:
	_can_fire = true

func _on_reload_timeout() -> void:
	ammo_in_clip = clip_size
	_can_fire = true
	emit_signal("ammo_changed", ammo_in_clip, clip_size)
	emit_signal("reload_finished")

func _fire_hitscan() -> void:
	var muzzle: Node3D = get_node_or_null(muzzle_path)
	if muzzle == null:
		muzzle = self

	var origin: Vector3 = muzzle.global_position
	var basis: Basis = muzzle.global_transform.basis
	var direction: Vector3 = -basis.z

	# Apply simple cone spread
	if spread_degrees > 0.0:
		direction = direction.rotated(basis.x, deg_to_rad(randf_range(-spread_degrees, spread_degrees)))
		direction = direction.rotated(basis.y, deg_to_rad(randf_range(-spread_degrees, spread_degrees)))
		direction = direction.normalized()

	var to: Vector3 = origin + direction * maximum_distance

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, to)
	query.exclude = [self]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result: Dictionary = space_state.intersect_ray(query)

	var hit_pos: Vector3 = to
	var hit_normal: Vector3 = Vector3.UP

	if result:
		hit_pos = result.position
		hit_normal = result.normal

		var target: Object = result.collider
		if target and target.has_method("take_damage"):
			target.take_damage(bullet_damage)

	_spawn_bullet_trail(origin, hit_pos)
	_spawn_impact(hit_pos, hit_normal)

func _spawn_muzzle_flash() -> void:
	if muzzle_flash_scene == null:
		return
	var flash := muzzle_flash_scene.instantiate()
	get_tree().current_scene.add_child(flash)
	var muzzle: Node3D = get_node_or_null(muzzle_path)
	if muzzle:
		flash.global_transform = muzzle.global_transform

func _spawn_impact(pos: Vector3, normal: Vector3) -> void:
	if impact_effect_scene == null:
		return
	var impact := impact_effect_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = pos
	if impact is Node3D:
		impact.look_at(pos + normal, Vector3.UP)

func _spawn_bullet_trail(from: Vector3, to: Vector3) -> void:
	if bullet_trail_scene == null:
		return
	var trail := bullet_trail_scene.instantiate()
	get_tree().current_scene.add_child(trail)
	if trail.has_method("create_trail"):
		trail.create_trail(from, to)
	else:
		trail.global_position = from
		trail.look_at(to, Vector3.UP) 