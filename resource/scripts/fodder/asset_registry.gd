extends Node

## Central registry of all game assets for shader prewarming
## Update this list as you add new enemies, weapons, effects, etc.

# Enemy scenes that can spawn in any map
const ENEMY_SCENES = [
	"res://scenes/enemies/KnightV2.tscn",
	"res://scenes/enemies/ArcherEnemy.tscn",
	"res://assets/enemy/bouncer_model.tscn",
	"res://assets/enemy/enemy_model.tscn",
]

# Weapon scenes (viewmodels and projectiles)
const WEAPON_SCENES = [
	"res://scenes/weapons/vagrant_knife_test1.tscn",
	"res://scenes/weapons/vagrant_knife_test2.tscn",
	"res://scenes/weapons/vagrant_knife_test3.tscn",
	"res://scenes/weapons/v_revolver3.tscn",
	"res://scenes/weapons/v_revolver3alt.tscn",
]

# Effect scenes (particles, trails, etc.)
const EFFECT_SCENES = [
	"res://scenes/effects/bullet_trail.tscn",
	"res://scenes/effects/spark_effect.tscn",
	"res://assets/effect/particles/node_3d.tscn",
]

# UI elements that might be spawned
const UI_SCENES = [
	"res://scenes/ui/pause_menu.tscn",
]

# Get all asset paths as a flat array
static func get_all_asset_paths() -> Array[String]:
	var all_paths: Array[String] = []
	all_paths.append_array(ENEMY_SCENES)
	all_paths.append_array(WEAPON_SCENES)
	all_paths.append_array(EFFECT_SCENES)
	all_paths.append_array(UI_SCENES)
	return all_paths

# Get all assets as packed scenes
static func get_all_game_assets() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	
	for path in get_all_asset_paths():
		var scene = load(path) as PackedScene
		if scene:
			scenes.append(scene)
		else:
			push_warning("AssetRegistry: Failed to load %s" % path)
	
	return scenes

# Get specific category
static func get_enemies() -> Array[PackedScene]:
	return _load_scenes(ENEMY_SCENES)

static func get_weapons() -> Array[PackedScene]:
	return _load_scenes(WEAPON_SCENES)

static func get_effects() -> Array[PackedScene]:
	return _load_scenes(EFFECT_SCENES)

static func get_ui() -> Array[PackedScene]:
	return _load_scenes(UI_SCENES)

static func _load_scenes(paths: Array) -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	for path in paths:
		var scene = load(path) as PackedScene
		if scene:
			scenes.append(scene)
	return scenes

