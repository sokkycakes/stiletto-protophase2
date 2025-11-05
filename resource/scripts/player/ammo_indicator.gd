extends Control

# AmmoIndicator.gd – visual ammo counter for 6-shot revolver
# Drop this on a Control node with 6 child nodes (ammo pips) that have modulate properties

signal ammo_changed(current_ammo, max_ammo)

@export var max_ammo: int = 6
@export var ammo_pip_paths: Array[NodePath] = []  # Paths to the 6 ammo pip nodes
@export var full_alpha: float = 1.0
@export var empty_alpha: float = 0.3

var current_ammo: int = 6
var ammo_pips: Array[Control] = []
var emptyglow_node: TextureRect = null
var pulse_tween: Tween = null
var pulse_timer: Timer = null
var pulse_count: int = 0

func _ready():
	# Validate and collect ammo pip nodes
	if ammo_pip_paths.size() != max_ammo:
		push_error("AmmoIndicator: ammo_pip_paths must have exactly ", max_ammo, " entries")
		return
	
	for i in range(max_ammo):
		if ammo_pip_paths[i] != NodePath("") and has_node(ammo_pip_paths[i]):
			var pip = get_node(ammo_pip_paths[i]) as Control
			if pip:
				ammo_pips.append(pip)
			else:
				push_error("AmmoIndicator: node at path ", ammo_pip_paths[i], " is not a Control")
		else:
			push_error("AmmoIndicator: invalid path at index ", i)
	
	if ammo_pips.size() != max_ammo:
		push_error("AmmoIndicator: failed to collect all ammo pips")
		return
	
	# Find the emptyglow node
	var transparentmask = get_node("transparentmask")
	if transparentmask:
		emptyglow_node = transparentmask.get_node("emptyglow") as TextureRect
		if not emptyglow_node:
			push_error("AmmoIndicator: could not find emptyglow node")
	
	# Create pulse timer
	pulse_timer = Timer.new()
	pulse_timer.one_shot = true
	pulse_timer.timeout.connect(_on_pulse_timer_timeout)
	add_child(pulse_timer)
	
	# Initialize display
	current_ammo = max_ammo
	_update_display()

# Public API
func fire_shot():
	if current_ammo > 0:
		current_ammo -= 1
		_update_display()
		emit_signal("ammo_changed", current_ammo, max_ammo)
		return true
	return false

func reload():
	current_ammo = max_ammo
	_update_display()
	emit_signal("ammo_changed", current_ammo, max_ammo)

func set_ammo(ammo: int):
	current_ammo = clamp(ammo, 0, max_ammo)
	_update_display()
	emit_signal("ammo_changed", current_ammo, max_ammo)

func get_ammo() -> int:
	return current_ammo

func is_empty() -> bool:
	return current_ammo <= 0

# Trigger empty weapon pulse effect
func trigger_empty_pulse():
	if emptyglow_node:
		_start_pulse_sequence()

# Internal display update
func _update_display():
	for i in range(max_ammo):
		if i < ammo_pips.size():
			var pip = ammo_pips[i]
			if i < current_ammo:
				# Full ammo - full opacity
				pip.modulate.a = full_alpha
				# pip.modulate.a direct may not propagate; use copy
				var col = pip.modulate
				col.a = full_alpha
				pip.modulate = col
			else:
				# Empty ammo - reduced opacity
				var col_empty = pip.modulate
				col_empty.a = empty_alpha
				pip.modulate = col_empty 

# Start the pulse sequence
func _start_pulse_sequence():
	if not emptyglow_node:
		return
	
	# Stop any existing pulse
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
	
	# Reset pulse count and start first pulse
	pulse_count = 0
	_do_single_pulse()

# Do a single pulse
func _do_single_pulse():
	if not emptyglow_node:
		return
	
	# Create tween for single pulse
	pulse_tween = create_tween()
	pulse_tween.tween_property(emptyglow_node, "modulate:a", 1.0, 0.1)
	pulse_tween.tween_property(emptyglow_node, "modulate:a", 0.0, 0.1)
	
	# Start timer for next pulse or end sequence
	pulse_timer.wait_time = 0.15  # 0.1s fade + 0.05s delay
	pulse_timer.start()

# Timer callback for pulse sequence
func _on_pulse_timer_timeout():
	pulse_count += 1
	if pulse_count < 2:  # Do second pulse
		_do_single_pulse()
	# If pulse_count >= 2, sequence is complete 
