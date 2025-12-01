extends Node3D

@export var enemy_scene: PackedScene

# Explicit scene references for composition (optional; falls back to enemy_scene)
@export var knight_scene: PackedScene
@export var archer_scene: PackedScene

# Wave/area composition controls (configured by GameMaster)
@export var force_knights_only: bool = false
@export var archer_only_area: bool = false
@export_range(0.0, 1.0, 0.01) var mixed_knight_ratio: float = 0.7 # 0.7 knights / 0.3 archers

@export var spawn_count: int = 5
@export var spawn_radius: float = 5.0
@export var spawn_interval: float = 40.0
@export var max_health: int = 100
var _health: int
@export var wave_pool: Resource
var _rng := RandomNumberGenerator.new()

@onready var _timer: Timer = $Timer

# Keeps weak references to the enemies this spawner is responsible for
var _spawned_enemies: Array = []

func _ready():
	# Add this spawner to the "enemy" group so that grappling hooks and other systems can treat it like an enemy target.
	add_to_group("enemy")
	# Additional group used by GameMaster to count active spawners
	add_to_group("enemy_spawner")
	randomize()
	_health = max_health
	_timer.wait_time = spawn_interval
	_timer.timeout.connect(_on_timer_timeout)
	_timer.start()
	call_deferred("_spawn_group")  # Defer initial spawn until tree is ready

func _on_timer_timeout():
	print("EnemySpawner: timer timeout - spawning check")
	_spawn_group()

func _choose_enemy_scene() -> PackedScene:
	# If a wave pool is provided, prefer it
	if wave_pool and wave_pool.has_method("is_empty") and not wave_pool.is_empty():
		var ps = wave_pool.pick_scene(_rng) if wave_pool.has_method("pick_scene") else null
		if ps:
			return ps
	var knight_ps: PackedScene = knight_scene if knight_scene != null else enemy_scene
	var archer_ps: PackedScene = archer_scene

	if force_knights_only:
		return knight_ps

	if archer_only_area:
		if archer_ps == null:
			push_warning("Archer scene not assigned for archer-only area. Falling back to knight.")
			return knight_ps
		return archer_ps

	if archer_ps == null:
		return knight_ps

	var roll: float = randf()
	if roll < mixed_knight_ratio:
		return knight_ps
	return archer_ps

func _spawn_group():
	if enemy_scene == null and knight_scene == null:
		push_warning("Enemy scene not assigned for EnemySpawner.")
		return

	print("EnemySpawner: running spawn group")

	# Remove any invalid or freed references first
	_spawned_enemies = _spawned_enemies.filter(func(e): return is_instance_valid(e))

	var alive: int = _spawned_enemies.size()
	var to_spawn: int = max(spawn_count - alive, 0)

	for i in range(to_spawn):
		var scene_to_spawn: PackedScene = _choose_enemy_scene()
		var enemy: Node3D = scene_to_spawn.instantiate()
		var angle: float = randf() * TAU
		var radius: float = randf() * spawn_radius
		var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * radius
		# Add to root so it doesn't inherit spawner transforms
		get_tree().get_current_scene().call_deferred("add_child", enemy)

		# Ensure enemy is independent of parent transforms
		enemy.set_as_top_level(true)

		var desired_pos: Vector3 = global_position + offset
		enemy.call_deferred("set_global_position", desired_pos)

		_spawned_enemies.append(enemy)
		# Automatically clean up list when enemy leaves the scene tree
		enemy.tree_exited.connect(_on_enemy_tree_exited.bind(enemy))

func _on_enemy_tree_exited(enemy: Node):
	_spawned_enemies.erase(enemy) 

func take_damage(amount: int):
	_health -= amount
	if _health <= 0:
		_on_destroyed()

func _on_destroyed():
	# Optional: play effects here
	# Clean up spawned enemies list (they will continue existing)
	queue_free() 
