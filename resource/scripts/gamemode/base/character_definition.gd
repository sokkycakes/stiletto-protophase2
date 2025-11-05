extends Resource
class_name CharacterDefinition

# Resource for defining playable characters
# Used by BaseGameMaster for character selection

@export var id: String = "character"
@export var display_name: String = "Character"
@export var scene_path: String = ""
@export var icon: Texture2D = null
@export var description: String = ""
@export var is_unlocked: bool = true

# Helper method to create a definition quickly
static func create(char_id: String, char_display_name: String, char_scene_path: String, char_icon: Texture2D = null, char_description: String = "", char_is_unlocked: bool = true) -> CharacterDefinition:
	var def = CharacterDefinition.new()
	def.id = char_id
	def.display_name = char_display_name
	def.scene_path = char_scene_path
	def.icon = char_icon
	def.description = char_description
	def.is_unlocked = char_is_unlocked
	return def

func get_icon_or_default() -> Texture2D:
	if icon:
		return icon
	# Could return a default icon texture here
	return null

func is_valid() -> bool:
	return not id.is_empty() and not display_name.is_empty() and not scene_path.is_empty()
