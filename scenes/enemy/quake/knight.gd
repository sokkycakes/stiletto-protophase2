extends "res://scenes/enemy/base_enemy_ai_lite.gd"
class_name Knight

# -----------------------------------------------------------------------------
#  Quake-style Knight (melee-only enemy)
#  • Chases the player using BaseEnemyAI movement.
#  • Performs sword swings via the attached BaseEnemyAttackSystem.
#  • No ranged attacks, no special abilities.
# -----------------------------------------------------------------------------

@export var max_health: int = 250          # Original Quake Knight HP

var _current_health: int = 0

# -----------------------------------------------------------------------------
func _ready() -> void:
	# Set Knight-specific values on parent class properties
	damage = 25           # Per-swing damage
	speed = 4.5          # Slightly faster than Grunt
	melee_distance = 1.7 # Reach of the sword
	
	_current_health = max_health
	super._ready()

# -----------------------------------------------------------------------------
#  Damage interface (so the player or other entities can hurt the Knight)
# -----------------------------------------------------------------------------
func take_damage(amount: int) -> void:
	_current_health -= amount
	if _current_health <= 0:
		queue_free() 
