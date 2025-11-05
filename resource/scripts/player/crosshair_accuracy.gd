extends Control

# This script controls the dynamic crosshair notches.
# It adjusts their position based on the weapon's current accuracy.

# No notch nodes needed – we draw everything in _draw()

# --- Config ---------------------------------------------------------------
@export var dynamic_enabled: bool = true             # If false we stay at base_spread.
@export var base_spread: float = 8.0                 # Pixel gap when perfectly accurate (at reference 1080p height).
@export var max_spread: float  = 50.0                # Absolute cap.
@export var spread_factor: float = 40.0              # Multiplier for accuracy_penalty -> pixels (matches CS logic).
@export var smooth_speed: float = 10.0               # How fast (units per second) we approach target gap.

# Appearance
@export var line_thickness := 2.0                    # Width/height for bar images
@export var notch_color: Color = Color.WHITE         # Tint applied to notch Controls

# Length of each bar (pixels at reference resolution)
@export var notch_length: float = 10.0

# --- Internal state -------------------------------------------------------
var _target_spread: float = 0.0
var _current_spread: float = 0.0

# Reference resolution to make gap size resolution-independent
const REF_SCREEN_HEIGHT: float = 1080.0

func _ready():
	set_process(true)
	queue_redraw() # trigger initial draw

func _process(delta):
	# Interpolate towards target for smooth animation
	_current_spread = lerp(_current_spread, _target_spread, clamp(delta * smooth_speed, 0, 1))
	queue_redraw()   # ask Control to redraw with new spread

func update_spread(accuracy_penalty: float):
	# Called by weapon manager every frame with the weapon's current penalty.
	if dynamic_enabled:
		var screen_scale := float(get_viewport_rect().size.y) / REF_SCREEN_HEIGHT
		_target_spread = clamp(base_spread + accuracy_penalty * spread_factor * screen_scale,
							   base_spread, max_spread)
	else:
		_target_spread = base_spread

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
func _draw():
	var center := get_size() * 0.5
	var spread := _current_spread

	# Scale notch_length with resolution like spread does.
	var screen_scale := float(get_viewport_rect().size.y) / REF_SCREEN_HEIGHT
	var length := notch_length * screen_scale
	var half_len := length * 0.5
	var half_th := line_thickness * 0.5

	# Top bar (horizontal)
	draw_rect(Rect2(Vector2(center.x - half_len, center.y - spread - half_th),
					Vector2(length, line_thickness)),
			  notch_color)

	# Bottom bar
	draw_rect(Rect2(Vector2(center.x - half_len, center.y + spread - half_th),
					Vector2(length, line_thickness)),
			  notch_color)

	# Right bar (vertical)
	draw_rect(Rect2(Vector2(center.x + spread - half_th, center.y - half_len),
					Vector2(line_thickness, length)),
			  notch_color)

	# Left bar
	draw_rect(Rect2(Vector2(center.x - spread - half_th, center.y - half_len),
					Vector2(line_thickness, length)),
			  notch_color) 
