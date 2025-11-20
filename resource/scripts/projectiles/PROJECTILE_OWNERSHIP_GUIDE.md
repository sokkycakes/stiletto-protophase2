# Projectile Ownership Tracking System

## Overview

This universal ownership tracking system ensures that projectiles never damage their owners in multiplayer, even when multiple players use the same character class. It solves the ownership confusion that occurs when object references become ambiguous across network boundaries.

## Architecture

### Core Components

1. **`NetworkedProjectileOwnership`** - Utility class with static helper functions for finding owners
2. **`NetworkedProjectile`** - Base class for networked projectiles with built-in ownership tracking
3. **`NetworkedPlayer.get_projectile_owner_info()`** - Helper method to get owner information when spawning

### Key Features

- **Peer ID Tracking**: Uses network peer IDs instead of object references for ownership
- **Automatic Owner Resolution**: Finds the correct owner even when spawned on remote clients
- **Collision Exception Setup**: Automatically excludes owner from physics collisions
- **Universal Pattern**: Works with any projectile type (RigidBody3D, Area3D, CharacterBody3D)

## Usage

### For New Projectiles

#### Option 1: Extend NetworkedProjectile (Recommended)

```gdscript
extends NetworkedProjectile
class_name MyProjectile

func _ready():
    # Ownership is handled by base class
    # Override collision handlers to check is_owner(body) before applying damage
    pass

func _on_body_entered(body: Node):
    if is_owner(body):
        return  # Don't damage owner
    
    # Apply damage to non-owners
    if body.has_method("take_damage"):
        body.take_damage(damage)
```

#### Option 2: Use Ownership Utilities Directly

```gdscript
extends RigidBody3D
class_name MyProjectile

var owner_node: Node3D = null
var owner_peer_id: int = -1

func initialize(velocity: Vector3, owner_ref: Node3D = null, owner_id: int = -1):
    owner_node = owner_ref
    owner_peer_id = owner_id
    linear_velocity = velocity

func _on_body_entered(body: Node):
    # Use utility functions to check ownership
    if NetworkedProjectileOwnership.get_owner_networked_player(body)?.peer_id == owner_peer_id:
        return  # Don't damage owner
    
    # Apply damage
```

### For Weapon Systems

#### When Spawning Projectiles Locally

```gdscript
# In your weapon script
func fire_projectile():
    var networked_player = _get_networked_player()
    if not networked_player:
        return
    
    # Get owner information
    var owner_info = networked_player.get_projectile_owner_info()
    
    # Spawn projectile
    var projectile = projectile_scene.instantiate()
    projectile.global_position = muzzle_position
    get_tree().current_scene.add_child(projectile)
    
    # Set owner using universal pattern
    if projectile.has_method("set_owner"):
        projectile.set_owner(owner_info.owner_ref, owner_info.owner_peer_id)
    elif projectile.has_method("throw"):
        projectile.throw(velocity, owner_info.owner_ref, owner_info.owner_peer_id)
    elif projectile.has_method("set_owner_info"):
        projectile.set_owner_info(owner_info.owner_ref, owner_info.owner_peer_id)
    elif projectile.has_method("initialize"):
        projectile.initialize(start_pos, direction, owner_info.owner_ref, owner_info.owner_peer_id)
```

#### When Broadcasting Projectiles via RPC

```gdscript
# On authority (local spawn)
func _fire_projectile():
    var owner_info = networked_player.get_projectile_owner_info()
    
    # Spawn locally
    var projectile = projectile_scene.instantiate()
    projectile.set_owner(owner_info.owner_ref, owner_info.owner_peer_id)
    # ... setup projectile ...
    
    # Broadcast to remote clients with owner_peer_id
    spawn_projectile_rpc(projectile.global_position, velocity, projectile.resource_path, owner_info.owner_peer_id)

@rpc("authority", "call_remote", "reliable")
func spawn_projectile_rpc(origin: Vector3, velocity: Vector3, projectile_path: String, owner_peer_id: int):
    # Don't spawn on authority (already spawned)
    if is_multiplayer_authority():
        return
    
    # Spawn on remote client
    var projectile = load(projectile_path).instantiate()
    projectile.global_position = origin
    
    # IMPORTANT: Pass null for owner_ref on remote clients, use peer_id only
    projectile.set_owner(null, owner_peer_id)  # Will find owner by peer_id
    
    get_tree().current_scene.add_child(projectile)
```

## Integration Points

### NetworkedWeaponManager

The `NetworkedWeaponManager` now includes `_set_projectile_owner()` which automatically detects and calls the appropriate ownership method:

- `set_owner()` - NetworkedProjectile base class
- `throw()` - ThrowableKnifeProjectile pattern
- `set_owner_info()` - Generic pattern
- `initialize()` - Fallback pattern

### Existing Projectiles

- **`Projectile` (Area3D)**: Updated with `set_owner_info()` and `is_owner()` methods
- **`ThrowableKnifeProjectile`**: Already has full ownership tracking, uses utilities
- **New projectiles**: Should extend `NetworkedProjectile` or implement `set_owner()` method

## Best Practices

1. **Always pass peer_id on RPCs**: Object references don't work across network
2. **Use null for owner_ref on remote clients**: Let the system find the owner by peer_id
3. **Check ownership before damage**: Use `is_owner(body)` or `should_apply_damage_to(body)`
4. **Use get_projectile_owner_info()**: Standardized way to get owner information
5. **Extend NetworkedProjectile**: Simplest way to get ownership tracking

## Troubleshooting

### Projectiles still hitting their owners
- Check that `set_owner()` or equivalent is being called
- Verify `owner_peer_id` is being passed on RPCs
- Ensure collision exceptions are being set up

### Ownership not working across network
- Make sure you're passing `owner_peer_id` in RPCs, not just object references
- On remote clients, pass `null` for owner_ref and let system find by peer_id
- Verify NetworkedPlayer nodes have correct peer_id values

### Multiple players same class causing issues
- This system specifically solves this! Ensure all projectiles use it
- Make sure all weapon spawning code uses `get_projectile_owner_info()`
- Verify RPC functions include `owner_peer_id` parameter

