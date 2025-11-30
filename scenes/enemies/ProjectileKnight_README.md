# ProjectileKnight - Parry Testing Enemy

## Overview
The ProjectileKnight is a test enemy derived from KnightV2 that fires projectiles at regular intervals. It's designed specifically for testing the parry mechanic for melee attacks on players. By default, it acts as a stationary turret that fires projectiles straight ahead in its spawn direction.

## Features
- **Extends KnightV2**: Inherits all base knight behaviors (chasing, detection, etc.)
- **Projectile Firing**: Fires projectiles every second (configurable)
- **No Damage**: Projectiles deal 0 damage by default for safe testing
- **Parriable**: Projectiles can be parried using the hook melee attack or vagrant knife
- **Invincible**: Cannot die from taking damage (perfect test dummy)
- **Stationary Turret**: Stays in place, fires straight ahead (no player tracking)
- **Continuous Fire**: Shoots projectiles even without a player target

## Files Created
1. `resource/scripts/enemy/ProjectileKnight.gd` - Main script
2. `scenes/enemies/ProjectileKnight.tscn` - Enemy scene
3. `scenes/test/projectile_knight_test.tscn` - Test scene with knight spawned

## Configuration

### Export Variables (Inspector)
```gdscript
# Projectile Settings
@export var projectile_scene: PackedScene  # Default: projectile.tscn
@export var projectile_fire_rate: float = 1.0  # Fires every second
@export var projectile_speed: float = 20.0  # Projectile travel speed
@export var projectile_damage: int = 0  # No damage for testing
@export var projectile_spawn_offset: Vector3 = Vector3(0, 1.5, 0)  # Chest height

# Test Dummy Settings
@export var is_stationary: bool = true  # Doesn't move from spawn position
@export var is_invincible: bool = true  # Can't be killed by damage
```

### Inherited from KnightV2
- `movement_speed`: How fast the knight moves (default: 3.5)
- `attack_range`: Optimal distance for projectile firing (default: 5.0)
- `sight_range`: How far the knight can detect players (default: 15.0)
- `max_health`: Knight's health points (default: 150)
- `debug_enabled`: Enable debug output (default: true)

## How It Works

### Behavior
1. **Stationary Mode** (default): 
   - Stays at spawn position
   - Maintains spawn rotation (does NOT track player)
   - Fires projectiles straight ahead in spawn direction
2. **Mobile Mode** (if `is_stationary = false`):
   - Moves toward player but maintains optimal distance (2.5x attack_range)
   - Backs away if too close (< optimal distance)
   - Moves closer if too far (> optimal distance * 2)
   - Aims projectiles at player
3. **Projectile Firing**: Fires projectiles every `projectile_fire_rate` seconds
4. **Invincibility** (default): Cannot be killed, ignores all damage
5. **No Player Required**: Fires continuously even without a target (stationary mode)

### Projectile Properties
- Uses the standard `Projectile` class from `projectile.tscn`
- Automatically inherits parry detection (checked via `_is_projectile()` in hook_melee_attack.gd)
- Set to 0 damage to prevent unintended player harm during testing
- Spawns at chest height and fires in knight's forward direction
- In stationary mode: Fires straight ahead based on spawn rotation
- In mobile mode: Aims at player's center

## Parry Mechanic Integration

The projectiles are automatically parriable because they:
1. Use the `Projectile` class which has:
   - `set_owner_info()` method
   - `owner_peer_id` property
   - `direction` property
2. These properties are detected by the parry system in:
   - `resource/scripts/weapons/hook_melee_attack.gd`
   - `resource/scripts/weapons/vagrant_knife.gd`

When a projectile is parried:
- It reflects back toward the original shooter
- Ownership changes to the parrier
- Direction is reversed
- Speed can be multiplied (based on `parry_reflect_speed_multiplier`)

## Usage

### In Editor
1. Open `scenes/test/projectile_knight_test.tscn` for a basic test setup
2. Or drag `scenes/enemies/ProjectileKnight.tscn` into any scene
3. **Rotate the knight** in the editor to aim where you want projectiles to fire
   - The knight fires in its forward direction (-Z axis)
   - Use the rotation gizmo to point it at your test area
4. No player target needed - it will fire continuously on its own
5. Run the scene and test parrying the projectiles with melee attacks

### Spawning via Code
```gdscript
var knight_scene = preload("res://scenes/enemies/ProjectileKnight.tscn")
var knight = knight_scene.instantiate()
knight.global_position = Vector3(0, 0, 5)  # Position in world

# Point the knight in the direction you want it to fire
var target_direction = Vector3(1, 0, 0)  # Fire towards +X
knight.look_at(knight.global_position + target_direction, Vector3.UP)

get_tree().current_scene.add_child(knight)
```

### Adjusting Fire Rate
```gdscript
# In inspector or code
knight.projectile_fire_rate = 0.5  # Fire every 0.5 seconds (faster)
knight.projectile_fire_rate = 2.0  # Fire every 2 seconds (slower)
```

## Testing Checklist
- [x] Knight spawns and initializes correctly
- [x] Knight detects and chases player
- [x] Projectiles fire at correct intervals
- [x] Projectiles travel toward player
- [x] Projectiles can be parried with melee attacks
- [x] Parried projectiles reflect back
- [x] No damage is dealt (for testing safety)

## Modifications

### To Enable Damage (on Knight)
In the inspector, set `is_invincible = false` to allow the knight to take damage and die

### To Enable Damage (on Projectiles)
In the inspector, set `projectile_damage` to desired value (e.g., 25)

### To Enable Movement
In the inspector, set `is_stationary = false` to make the knight chase the player

### To Change Projectile Appearance
Replace `projectile_scene` with a custom projectile scene that extends `Projectile` class

### To Adjust Behavior
Override methods in a derived class:
- `_fire_projectile()`: Custom projectile spawning logic
- `do_chase()`: Custom movement behavior
- `_update_projectile_firing()`: Custom firing timing

## Architecture Notes

### SOLID Principles
- **Single Responsibility**: ProjectileKnight only adds projectile firing logic
- **Open/Closed**: Extends KnightV2 without modifying it
- **Liskov Substitution**: Can be used anywhere KnightV2 is expected
- **Interface Segregation**: Uses existing Projectile interface
- **Dependency Inversion**: Depends on Projectile abstraction, not concrete implementation

### Component-Based Design
- Uses composition: ProjectileKnight + Projectile system
- Projectile spawning separated from movement logic
- Parry detection handled by weapon systems, not enemy

## Troubleshooting

### Projectiles Not Spawning
- Check that `projectile_scene` is set in inspector
- Verify that target_player is valid
- Enable `debug_enabled` to see console output

### Projectiles Not Parriable
- Ensure the projectile uses the `Projectile` class
- Check that weapon has `can_parry_projectiles` enabled
- Verify that melee attack hitbox overlaps projectile

### Knight Too Aggressive/Passive
- Adjust `movement_speed` and `sight_range`
- Modify optimal distance calculation in `do_chase()`
- Change `attack_range` to affect positioning

## Future Enhancements
- Add projectile spread/patterns
- Implement charge-up attacks
- Add visual indicators for firing
- Support multiple projectile types
- Add sound effects for firing

