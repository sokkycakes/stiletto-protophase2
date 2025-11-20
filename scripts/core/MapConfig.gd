extends Resource
class_name MapConfig

## Defines default match settings that a map can opt into.
## Attach instances of this resource to `GameWorld.map_config` inside your map scene.

@export_enum("Deathmatch", "Team Deathmatch", "Cooperative", "Duel")
var game_mode: int = 0

@export var game_mode_definition: GameModeDefinition

@export_range(1.0, 60.0, 0.5, "suffix:min")
var time_limit_minutes: float = 5.0

@export_range(1, 500, 1)
var score_limit: int = 25

@export var description: String = ""
