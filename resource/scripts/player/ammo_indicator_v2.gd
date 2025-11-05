extends Control

# AmmoIndicatorV2.gd – visual ammo counter
# Works with WeaponManager to display ammo count.

@export var max_ammo: int = 6
@export var ammo_pip_paths: Array[NodePath] = []
@export var full_alpha: float = 1.0
@export var empty_alpha: float = 0.3

var ammo_pips: Array[Control] = []

func _ready():
    # Validate and collect ammo pip nodes
    if ammo_pip_paths.size() != max_ammo:
        push_error("AmmoIndicatorV2: ammo_pip_paths must have exactly ", max_ammo, " entries")
        return
    
    for i in range(max_ammo):
        var path = ammo_pip_paths[i]
        if path != NodePath("") and has_node(path):
            var pip = get_node(path) as Control
            if pip:
                ammo_pips.append(pip)
            else:
                push_error("AmmoIndicatorV2: node at path ", path, " is not a Control")
        else:
            push_error("AmmoIndicatorV2: invalid path at index ", i)
    
    if ammo_pips.size() != max_ammo:
        push_error("AmmoIndicatorV2: failed to collect all ammo pips")
        return

func update_ammo(current_ammo: int, _total_ammo: int):
    # This function is called by the WeaponManager
    var clamped_ammo = clamp(current_ammo, 0, max_ammo)
    _update_display(clamped_ammo)

func _update_display(ammo: int):
    for i in range(max_ammo):
        if i < ammo_pips.size():
            var pip = ammo_pips[i]
            if i < ammo:
                # Full ammo - full opacity
                pip.modulate.a = full_alpha
            else:
                # Empty ammo - reduced opacity
                pip.modulate.a = empty_alpha 