extends Node3D
class_name WeaponManager

# --- Weapon Management --------------------------------------------------------
@export var current_weapon: BaseWeapon
@export var weapons: Array[BaseWeapon] = []

# --- Input Actions -----------------------------------------------------------
@export var fire_action: String = "fire"
@export var reload_action: String = "reload"
@export var weapon_switch_actions: Array[String] = ["weapon_1", "weapon_2", "weapon_3"]

# --- References --------------------------------------------------------------
@export var camera: Camera3D
@export var muzzle_path: NodePath
@export var ammo_indicator_path: NodePath
@export var crosshair_accuracy_path: NodePath

# --- Internal State ---------------------------------------------------------
var _current_weapon_index: int = 0
var _muzzle_node: Node3D
var _ammo_indicator: Node = null
var _crosshair_accuracy: Node = null

func _ready() -> void:
	# Find muzzle node if path is provided
	if muzzle_path:
		_muzzle_node = get_node(muzzle_path)
	
	# Get ammo indicator if path is provided
	if ammo_indicator_path and has_node(ammo_indicator_path):
		_ammo_indicator = get_node(ammo_indicator_path)

	# Get crosshair accuracy node if path is provided
	if crosshair_accuracy_path and has_node(crosshair_accuracy_path):
		_crosshair_accuracy = get_node(crosshair_accuracy_path)
	
	# Auto-detect weapons in children
	_auto_detect_weapons()
	
	# Set up initial weapon
	if weapons.size() > 0:
		current_weapon = weapons[0]
		_setup_weapon(current_weapon)
	
	# Connect weapon signals
	_connect_weapon_signals()

func _process(delta: float) -> void:
	if current_weapon and _crosshair_accuracy:
		if current_weapon.has_method("get_current_accuracy_penalty"):
			var penalty = current_weapon.get_current_accuracy_penalty()
			if _crosshair_accuracy.has_method("update_spread"):
				_crosshair_accuracy.update_spread(penalty)

func _auto_detect_weapons() -> void:
	# Find all BaseWeapon instances in children
	for child in get_children():
		if child is BaseWeapon:
			weapons.append(child)
			print("Auto-detected weapon: ", child.name)

func _input(event: InputEvent) -> void:
	# Handle firing
	if Input.is_action_just_pressed(fire_action):
		_fire_current_weapon()
	
	# Handle reloading
	if Input.is_action_just_pressed(reload_action):
		_reload_current_weapon()
	
	# Handle weapon switching
	for i in range(weapon_switch_actions.size()):
		if Input.is_action_just_pressed(weapon_switch_actions[i]):
			_switch_weapon(i)
			break

func _fire_current_weapon() -> void:
	if current_weapon and _can_fire_weapon(current_weapon):
		current_weapon.shoot()

func _reload_current_weapon() -> void:
	if current_weapon and _can_reload_weapon(current_weapon):
		current_weapon.start_reload()

func _can_fire_weapon(weapon: BaseWeapon) -> bool:
	return weapon.ammo_in_clip > 0 and not weapon._reload_timer.time_left > 0

func _can_reload_weapon(weapon: BaseWeapon) -> bool:
	return weapon.ammo_in_clip < weapon.clip_size and not weapon._reload_timer.time_left > 0

func _switch_weapon(weapon_index: int) -> void:
	if weapon_index >= 0 and weapon_index < weapons.size():
		_current_weapon_index = weapon_index
		current_weapon = weapons[weapon_index]
		_setup_weapon(current_weapon)
		print("Switched to weapon: ", current_weapon.name)

func _setup_weapon(weapon: BaseWeapon) -> void:
	if not weapon:
		return
	
	# Set up weapon muzzle path if not already set
	if weapon.muzzle_path.is_empty() and _muzzle_node:
		weapon.muzzle_path = _muzzle_node.get_path()
	elif not weapon.muzzle_path.is_empty():
		# If weapon has its own muzzle path, use that instead
		_muzzle_node = weapon.get_node_or_null(weapon.muzzle_path)
	
	# Connect weapon signals
	_connect_weapon_signals()

func _connect_weapon_signals() -> void:
	if not current_weapon:
		return
	
	# Connect weapon signals if not already connected
	if not current_weapon.ammo_changed.is_connected(_on_weapon_ammo_changed):
		current_weapon.ammo_changed.connect(_on_weapon_ammo_changed)
	
	if not current_weapon.fired.is_connected(_on_weapon_fired):
		current_weapon.fired.connect(_on_weapon_fired)
	
	if not current_weapon.reload_finished.is_connected(_on_weapon_reloaded):
		current_weapon.reload_finished.connect(_on_weapon_reloaded)

func _on_weapon_ammo_changed(ammo_in_clip: int, total_ammo: int) -> void:
	# Update ammo indicator if available
	if _ammo_indicator and _ammo_indicator.has_method("update_ammo"):
		_ammo_indicator.update_ammo(ammo_in_clip, total_ammo)
	
	# Emit signal for UI updates
	ammo_changed.emit(ammo_in_clip, total_ammo)

func _on_weapon_fired() -> void:
	# Handle weapon fired event
	fired.emit()

func _on_weapon_reloaded() -> void:
	# Handle weapon reloaded event
	reload_finished.emit()

# --- Public API --------------------------------------------------------------
func add_weapon(weapon: BaseWeapon) -> void:
	weapons.append(weapon)
	if not current_weapon:
		current_weapon = weapon
		_setup_weapon(weapon)

func remove_weapon(weapon: BaseWeapon) -> void:
	weapons.erase(weapon)
	if current_weapon == weapon:
		if weapons.size() > 0:
			current_weapon = weapons[0]
		else:
			current_weapon = null

func get_current_weapon() -> BaseWeapon:
	return current_weapon

func get_weapon_count() -> int:
	return weapons.size()

# --- Signals -----------------------------------------------------------------
signal ammo_changed(ammo_in_clip: int, total_ammo: int)
signal fired()
signal reload_finished() 
