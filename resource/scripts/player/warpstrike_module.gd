extends Node
class_name WarpstrikeModule

signal warp_started(target: Vector3, normal: Vector3)
signal warp_released()
signal anchor_locked(target: Vector3, normal: Vector3)
signal warp_failed(target: Vector3)

enum WarpState { IDLE, AIMING, THROWING, ANCHOR_SET, LATCHED }

@export_group("Dependencies")
@export var player_path: NodePath = ^"../Body"
@export var camera_path: NodePath = ^"../Interpolated Camera/Arm/Arm Anchor/Camera"

@export_group("General")
@export var enabled: bool = true
@export var input_action: StringName = &"pc_warpstrike"
@export var hold_to_aim_threshold: float = 0.18
@export var aim_max_distance: float = 40.0
@export var aim_collision_mask: int = 1
@export var warp_surface_offset: float = 0.3
@export var warp_search_radius: float = 0.75
@export var warp_search_rings: int = 3
@export var warp_search_steps: int = 12
@export var stick_release_actions: Array[StringName] = [
	&"pm_moveforward",
	&"pm_movebackward",
	&"pm_moveleft",
	&"pm_moveright",
	&"pm_jump",
	&"pm_gunjump"
]

@export_group("Visuals")
@export var aim_indicator_scene: PackedScene
@export var latch_vfx_scene: PackedScene
@export var indicator_lerp_speed: float = 18.0

@export_group("Knife Anchor")
@export var knife_projectile_scene: PackedScene = preload("res://scenes/weapons/throwable_knife_projectile.tscn")
@export var knife_speed: float = 48.0
@export var knife_gravity: float = 0.0

const EPSILON := 0.0001

var _state: WarpState = WarpState.IDLE
var _player: CharacterBody3D
var _camera: Camera3D
var _aim_indicator: Node3D
var _knife_instance: Node3D
var _anchor_global: Transform3D = Transform3D.IDENTITY
var _stick_normal: Vector3 = Vector3.UP
var _anchor_position: Vector3 = Vector3.ZERO
var _latch_position: Vector3 = Vector3.ZERO
var _hold_timer: float = 0.0
var _fallback_point: Vector3 = Vector3.ZERO
var _last_delta: float = 0.0

func _ready() -> void:
	if not enabled:
		set_process(false)
		return
	_player = get_node_or_null(player_path) as CharacterBody3D
	_camera = get_node_or_null(camera_path) as Camera3D
	if _player == null or _camera == null:
		push_warning("WarpstrikeModule: missing player or camera reference.")
		enabled = false
		set_process(false)
		return
	if not InputMap.has_action(input_action):
		InputMap.add_action(input_action)

func _exit_tree() -> void:
	_despawn_indicator()
	_clear_knife_instance()

func _process(delta: float) -> void:
	if not enabled:
		return
	_last_delta = delta
	match _state:
		WarpState.IDLE:
			_handle_idle()
		WarpState.AIMING:
			_handle_aiming(delta)
		WarpState.THROWING:
			_handle_throwing()
		WarpState.ANCHOR_SET:
			_handle_anchor_ready()
		WarpState.LATCHED:
			_handle_latched()

func _handle_idle() -> void:
	if Input.is_action_just_pressed(input_action):
		_hold_timer = 0.0
		_state = WarpState.AIMING
		_spawn_indicator()

func _handle_aiming(delta: float) -> void:
	_hold_timer += delta
	var hit: Dictionary = _query_aim_point()
	_update_indicator(hit)
	if Input.is_action_just_released(input_action):
		if _hold_timer >= hold_to_aim_threshold and hit.has("position"):
			_begin_warp(hit.get("position", _fallback_point), hit.get("normal", Vector3.UP))
		else:
			_fire_anchor(hit)
	elif _hold_timer >= hold_to_aim_threshold:
		_update_indicator(hit, true)

func _handle_throwing() -> void:
	if not is_instance_valid(_knife_instance):
		_clear_knife_instance()
		_state = WarpState.IDLE

func _handle_anchor_ready() -> void:
	if not is_instance_valid(_knife_instance):
		_clear_anchor()
		_state = WarpState.IDLE
		return
	var anchor_info: Dictionary = {
		"position": _anchor_global.origin,
		"normal": _stick_normal
	}
	_update_indicator(anchor_info, true)
	if Input.is_action_just_pressed(input_action):
		_begin_warp(_anchor_global.origin, _stick_normal)

func _handle_latched() -> void:
	if _player == null:
		return
	_player.velocity = Vector3.ZERO
	var transform: Transform3D = _player.global_transform
	transform.origin = _latch_position
	_player.global_transform = transform
	if _should_release():
		_end_latch()

func _fire_anchor(hit: Dictionary) -> void:
	_despawn_indicator()
	if not knife_projectile_scene:
		return
	if is_instance_valid(_knife_instance):
		return
	var projectile: Node3D = knife_projectile_scene.instantiate() as Node3D
	if projectile == null:
		return
	projectile.global_transform = _camera.global_transform
	var direction: Vector3 = -_camera.global_transform.basis.z.normalized()
	if direction.length() < EPSILON:
		direction = Vector3.FORWARD
	var velocity: Vector3 = direction * knife_speed
	if projectile.has_method("throw"):
		projectile.call("throw", velocity, _player)
	if projectile is RigidBody3D:
		(projectile as RigidBody3D).gravity_scale = knife_gravity
	projectile.connect("tree_exited", Callable(self, "_on_projectile_freed"))
	if projectile.has_signal("stuck"):
		projectile.connect("stuck", Callable(self, "_on_knife_stuck"))
	knife_parent().add_child(projectile)
	_knife_instance = projectile
	_fallback_point = _camera.global_transform.origin + direction * aim_max_distance
	_state = WarpState.THROWING

func knife_parent() -> Node:
	return get_tree().current_scene

func _on_projectile_freed() -> void:
	_clear_knife_instance()
	if _state == WarpState.THROWING:
		_state = WarpState.IDLE

func _on_knife_stuck(location: Transform3D, normal: Vector3) -> void:
	var normalised: Vector3 = normal.normalized()
	_anchor_global = _build_indicator_transform(location.origin, normalised)
	_stick_normal = normalised
	_anchor_position = location.origin
	_state = WarpState.ANCHOR_SET
	_spawn_indicator()
	var anchor_info: Dictionary = {
		"position": _anchor_global.origin,
		"normal": _stick_normal
	}
	_update_indicator(anchor_info, true)
	emit_signal("anchor_locked", _anchor_global.origin, _stick_normal)

func _begin_warp(target: Vector3, normal: Vector3) -> void:
	var safe_position: Variant = _find_safe_position(target, normal)
	if safe_position == null:
		emit_signal("warp_failed", target)
		return
	_latch_position = safe_position
	_anchor_global = _build_indicator_transform(target, normal)
	_despawn_indicator()
	_player.velocity = Vector3.ZERO
	var transform: Transform3D = _player.global_transform
	transform.origin = _latch_position
	_player.global_transform = transform
	_spawn_latch_vfx()
	_state = WarpState.LATCHED
	emit_signal("warp_started", target, normal)

func _end_latch() -> void:
	_restore_gravity()
	_clear_anchor()
	_state = WarpState.IDLE
	emit_signal("warp_released")

func _should_release() -> bool:
	for action in stick_release_actions:
		if Input.is_action_pressed(action):
			return true
	return false

func _cache_and_disable_gravity() -> void:
	pass

func _restore_gravity() -> void:
	pass

func _build_indicator_transform(target: Vector3, normal: Vector3) -> Transform3D:
	var up: Vector3 = normal.normalized()
	if up.length() < EPSILON:
		up = Vector3.UP
	var forward: Vector3 = -_camera.global_transform.basis.z
	forward = (forward - forward.project(up)).normalized()
	if forward.length() < EPSILON:
		forward = Vector3.FORWARD.cross(up).normalized()
	if forward.length() < EPSILON:
		forward = Vector3.FORWARD
	var right: Vector3 = up.cross(forward).normalized()
	forward = right.cross(up).normalized()
	return Transform3D(Basis(right, up, forward), target)

func _spawn_indicator() -> void:
	if aim_indicator_scene == null:
		return
	if is_instance_valid(_aim_indicator):
		return
	_aim_indicator = aim_indicator_scene.instantiate() as Node3D
	if _aim_indicator == null:
		return
	add_child(_aim_indicator)

func _update_indicator(hit: Dictionary, force_visible: bool = false) -> void:
	if not is_instance_valid(_aim_indicator):
		return
	var position: Vector3 = hit.get("position", _fallback_point)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var should_show: bool = force_visible or hit.has("position")
	_aim_indicator.visible = should_show
	if not should_show:
		return
	var target_transform: Transform3D = _build_indicator_transform(position, normal)
	var current: Transform3D = _aim_indicator.global_transform
	var lerp_weight: float = clamp(indicator_lerp_speed * _last_delta, 0.0, 1.0)
	_aim_indicator.global_transform = current.interpolate_with(target_transform, lerp_weight)

func _despawn_indicator() -> void:
	if not is_instance_valid(_aim_indicator):
		return
	_aim_indicator.queue_free()
	_aim_indicator = null

func _spawn_latch_vfx() -> void:
	if latch_vfx_scene == null:
		return
	var vfx: Node3D = latch_vfx_scene.instantiate() as Node3D
	if vfx == null:
		return
	knife_parent().add_child(vfx)
	vfx.global_transform = _anchor_global

func _query_aim_point() -> Dictionary:
	if _camera == null or _camera.get_world_3d() == null:
		return {}
	var from: Vector3 = _camera.global_transform.origin
	var to: Vector3 = from + (-_camera.global_transform.basis.z) * aim_max_distance
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	params.from = from
	params.to = to
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = aim_collision_mask
	var space_state: PhysicsDirectSpaceState3D = _camera.get_world_3d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(params)
	if result.is_empty():
		_fallback_point = to
	return result

func _find_safe_position(target: Vector3, normal: Vector3) -> Variant:
	if _player == null:
		return null
	var direction: Vector3 = normal.normalized()
	if direction.length() < EPSILON:
		direction = Vector3.UP
	var desired: Vector3 = target + direction * warp_surface_offset
	if _is_position_clear(desired):
		return desired
	var candidates: Array = _generate_search_positions(desired, direction)
	for candidate in candidates:
		if _is_position_clear(candidate):
			return candidate
	return null

func _is_position_clear(position: Vector3) -> bool:
	if _player == null:
		return false
	var current: Transform3D = _player.global_transform
	var motion: Vector3 = position - current.origin
	if motion.length() <= EPSILON:
		return true
	return not _player.test_move(current, motion)

func _generate_search_positions(center: Vector3, normal: Vector3) -> Array:
	var positions: Array = []
	var direction: Vector3 = normal.normalized()
	if direction.length() < EPSILON:
		direction = Vector3.UP
	var rings: int = max(1, warp_search_rings)
	var steps: int = max(4, warp_search_steps)
	for depth in range(1, 4):
		positions.append(center + direction * (warp_surface_offset + 0.2 * depth))
		positions.append(center - direction * (0.2 * depth))
	var up: Vector3 = Vector3.UP
	if abs(direction.dot(up)) > 0.9:
		up = Vector3.RIGHT
	var right: Vector3 = direction.cross(up).normalized()
	if right.length() < EPSILON:
		right = Vector3.FORWARD
	var forward: Vector3 = right.cross(direction).normalized()
	for ring in range(1, rings + 1):
		var radius: float = warp_search_radius * float(ring) / float(rings)
		for step in range(steps):
			var angle: float = TAU * float(step) / float(steps)
			var radial: Vector3 = (right * cos(angle) + forward * sin(angle)) * radius
			positions.append(center + radial)
	return positions

func _clear_anchor() -> void:
	_despawn_indicator()
	_clear_knife_instance()
	_anchor_global = Transform3D.IDENTITY
	_stick_normal = Vector3.UP
	_anchor_position = Vector3.ZERO
	_latch_position = Vector3.ZERO

func _clear_knife_instance() -> void:
	if is_instance_valid(_knife_instance):
		_knife_instance.queue_free()
	_knife_instance = null
