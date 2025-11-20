extends Resource
class_name GameModeDefinition

## Describes how a game mode should behave when referenced by a MapConfig.
## This resource lets individual maps declare their required rules, limits,
## and any mode-specific logic scenes to instantiate at runtime.

@export var display_name: String = "Deathmatch"
@export var description: String = ""

@export_enum(
	"Deathmatch",
	"Team Deathmatch",
	"Cooperative",
	"Duel"
)
var mode: int = 0

@export_range(1, 16, 1)
var min_players: int = 2

@export_range(1, 16, 1)
var max_players: int = 8

@export_range(1.0, 60.0, 0.5, "suffix:min")
var default_time_limit_minutes: float = 5.0

@export_range(1, 500, 1)
var default_score_limit: int = 25

@export var logic_scene: PackedScene

## Character selection for this game mode
@export var character_select_ui_scene: PackedScene
@export var available_characters: Array[CharacterDefinition] = []

func get_mode_name() -> String:
	return display_name if not display_name.is_empty() else "Game Mode"

