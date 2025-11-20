# Source Engine-Style State Replication Integration Guide

## Overview

This system implements Source Engine-inspired networking features for your Godot multiplayer game:

- **Full State Snapshots**: Late joiners receive complete game state
- **Delta Compression**: Only changed properties are sent after baseline
- **Priority System**: Closer/more active entities update more frequently
- **Lag Compensation**: State history buffer for server-side rewind
- **Client Interpolation**: Smooth movement even with packet loss

## Architecture

### Core Components

1. **NetworkStateSnapshot** (`scripts/networking/NetworkStateSnapshot.gd`)
   - Captures and serializes entity states
   - Calculates deltas between snapshots
   - Handles serialization/deserialization for RPC

2. **StateReplicationManager** (`scripts/networking/StateReplicationManager.gd`)
   - Manages all networked entities
   - Sends snapshots at configured rate (20-66 Hz)
   - Implements priority-based updates
   - Handles late-joiner baseline sync

3. **NetworkedEntity** (`scripts/networking/NetworkedEntity.gd`)
   - Base class for replicable entities
   - Automatic position/rotation/velocity sync
   - Built-in interpolation
   - State history for lag compensation

4. **GameWorldStateSync** (`scripts/core/GameWorldStateSync.gd`)
   - Integrates state replication with GameWorld
   - Handles player registration/unregistration
   - Manages late-joiner synchronization

## Integration Steps

### Step 1: Add StateReplicationManager as Autoload (Recommended)

In Project Settings > Autoload:
- **Node Name**: `StateReplicationManager`
- **Path**: `res://scripts/networking/StateReplicationManager.gd`
- **Enable**: Yes

Alternatively, it can be instantiated in GameWorld (see GameWorldStateSync).

### Step 2: Add GameWorldStateSync to Your GameWorld Scene

Option A - Via Script:
```gdscript
# In GameWorld.gd _ready():
var state_sync = GameWorldStateSync.new()
state_sync.name = "StateSync"
state_sync.enable_state_replication = true
state_sync.snapshot_rate = 20.0  # 20 snapshots per second
add_child(state_sync)
```

Option B - Via Scene Editor:
1. Open `scenes/mp_framework/game_world.tscn`
2. Add child node to GameWorld root
3. Select Script > Attach > Load: `GameWorldStateSync.gd`
4. Configure exported variables in inspector

### Step 3: Register Players with State Replication

Modify `GameWorld._spawn_player()`:

```gdscript
func _spawn_player(peer_id: int) -> void:
	# ... existing spawn code ...
	
	# After adding player to scene:
	players[peer_id] = networked_player
	
	# Register with state replication (if using GameWorldStateSync)
	var state_sync = $StateSync as GameWorldStateSync
	if state_sync:
		state_sync.register_player(networked_player)
	
	# ... rest of function ...
```

### Step 4: Handle Late Joiners

Modify `GameWorld._on_player_connected_to_game()`:

```gdscript
func _on_player_connected_to_game(peer_id: int, player_info: Dictionary) -> void:
	# Spawn the newly connected player
	_spawn_player(peer_id)
	
	# If we're the server, sync full game state to late joiner
	if MultiplayerManager.is_server():
		var state_sync = $StateSync as GameWorldStateSync
		if state_sync:
			# This sends baseline snapshot + all player states
			state_sync.sync_late_joiner(peer_id)
		else:
			# Fallback to existing sync method
			call_deferred("_spawn_existing_players_for_new_client", peer_id)
```

### Step 5: (Optional) Use NetworkedPlayerExtended

For enhanced features, replace NetworkedPlayer with NetworkedPlayerExtended:

```gdscript
# In GameWorld.gd
var networked_player_scene: PackedScene = preload("res://scripts/player/NetworkedPlayerExtended.gd")

func _spawn_player(peer_id: int) -> void:
	# Create extended networked player
	var networked_player = NetworkedPlayerExtended.new()
	# ... rest of spawn logic ...
```

Or modify NetworkedPlayer scene to use the extended script.

### Step 6: Unregister Players on Disconnect

Modify `GameWorld._on_player_disconnected()`:

```gdscript
func _on_player_disconnected(peer_id: int) -> void:
	if peer_id in players:
		var player = players[peer_id]
		
		# Unregister from state replication
		var state_sync = $StateSync as GameWorldStateSync
		if state_sync:
			state_sync.unregister_player(player)
		
		player.queue_free()
		players.erase(peer_id)
		print("Removed disconnected player: ", peer_id)
```

## Configuration

### StateReplicationManager Settings

```gdscript
# Adjust snapshot rate (Hz)
StateReplicationManager.set_snapshot_rate(30.0)  # 30 updates/second

# Enable/disable features
StateReplicationManager.enable_delta_compression = true  # Saves bandwidth
StateReplicationManager.enable_priority_updates = true   # Smart update ordering
StateReplicationManager.bandwidth_limit = 128000         # 128 KB/s per client
```

### NetworkedEntity Settings

For custom entities, extend NetworkedEntity:

```gdscript
extends NetworkedEntity

func _ready():
	super._ready()
	
	# Configure replication
	replicate_position = true
	replicate_rotation = true
	replicate_velocity = true
	network_priority = 2.0  # Higher = more updates
	enable_interpolation = true
	interpolation_speed = 10.0

# Capture custom state
func _capture_custom_state() -> Dictionary:
	return {
		"custom_property": my_property,
		"another_value": another_value
	}

# Apply custom state
func _apply_custom_state(state: Dictionary) -> void:
	if "custom_property" in state:
		my_property = state["custom_property"]
	if "another_value" in state:
		another_value = state["another_value"]
```

## Lag Compensation

### Server-Side Hit Detection with Rewind

```gdscript
# In weapon hit detection:
func process_hitscan_shot(shooter_peer_id: int, target_peer_id: int):
	# Get shooter's ping
	var ping = MultiplayerManager.get_peer_ping(shooter_peer_id)
	
	# Calculate rewind time
	var rewind_time = Time.get_unix_time_from_system() - (ping / 1000.0)
	
	# Get target player
	var target_player = GameWorld.get_player_by_peer_id(target_peer_id)
	if not target_player:
		return
	
	# Rewind target to shooter's view
	var saved_state = target_player.rewind_to_time(rewind_time)
	
	# Perform hit detection at rewound position
	var hit = perform_raycast(shooter_position, target_player.global_position)
	
	# Restore target to current state
	target_player.restore_state(saved_state)
	
	# Apply damage if hit
	if hit:
		target_player.take_damage(damage, shooter_peer_id)
```

## Monitoring & Debugging

### Bandwidth Statistics

```gdscript
# Get current bandwidth usage
var stats = StateReplicationManager.get_bandwidth_stats()
print("Bandwidth: %d / %d bytes/sec (%.1f%%)" % [
	stats.bytes_sent_this_second,
	stats.bandwidth_limit,
	stats.utilization
])
print("Entities: %d, History: %d snapshots" % [
	stats.registered_entities,
	stats.snapshot_history_size
])
```

### Debug Overlay (Optional)

```gdscript
# Add to your debug UI
func _process(delta):
	if show_debug_overlay:
		var stats = StateReplicationManager.get_bandwidth_stats()
		$DebugLabel.text = "Snapshot Rate: %.1f Hz\nBandwidth: %.1f%%\nEntities: %d" % [
			StateReplicationManager.get_snapshot_rate(),
			stats.utilization,
			stats.registered_entities
		]
```

## Performance Tuning

### Low Bandwidth Connections

```gdscript
# Reduce snapshot rate for mobile/slow connections
StateReplicationManager.set_snapshot_rate(15.0)  # 15 Hz instead of 20
StateReplicationManager.bandwidth_limit = 64000  # 64 KB/s
```

### High Performance Servers

```gdscript
# Increase for competitive games
StateReplicationManager.set_snapshot_rate(66.0)  # Source Engine competitive rate
StateReplicationManager.bandwidth_limit = 256000  # 256 KB/s
```

### Priority Tweaking

```gdscript
# Adjust entity priorities based on gameplay
player.network_priority = 5.0      # Players always high priority
important_npc.network_priority = 3.0
decoration.network_priority = 0.5   # Static objects low priority
```

## Migration from Existing System

### Gradual Migration

1. Keep existing sync system running
2. Add StateReplicationManager alongside
3. Enable on test server
4. Monitor bandwidth and performance
5. Gradually move entities to new system
6. Remove old sync code once stable

### Compatibility Mode

The new system is designed to work alongside your existing NetworkedPlayer sync:

```gdscript
# In NetworkedPlayer, you can keep both systems:
@export var use_legacy_sync: bool = false
@export var use_state_replication: bool = true

func _ready():
	if use_state_replication:
		_setup_entity_adapter()
	
	if use_legacy_sync:
		sync_timer.start()  # Keep old system running
```

## Troubleshooting

### Issue: Late joiners see frozen players

**Solution**: Ensure `state_sync.sync_late_joiner()` is called after player spawn:
```gdscript
await get_tree().create_timer(0.5).timeout
state_sync.sync_late_joiner(peer_id)
```

### Issue: High bandwidth usage

**Solutions**:
- Reduce snapshot rate: `set_snapshot_rate(15.0)`
- Enable delta compression: `enable_delta_compression = true`
- Lower priority on non-critical entities
- Increase position/rotation thresholds

### Issue: Jerky movement for remote players

**Solutions**:
- Enable interpolation in NetworkedEntity
- Increase `interpolation_speed` (10.0 - 20.0)
- Ensure snapshot rate is high enough (20+ Hz)

## Advanced Features

### Custom Entity Types

```gdscript
# Projectile with state replication
extends NetworkedEntity
class_name NetworkedProjectile

var damage: float = 50.0
var owner_peer_id: int = -1

func _capture_custom_state() -> Dictionary:
	return {
		"damage": damage,
		"owner_peer_id": owner_peer_id
	}

func _apply_custom_state(state: Dictionary) -> void:
	if "damage" in state:
		damage = state["damage"]
	if "owner_peer_id" in state:
		owner_peer_id = state["owner_peer_id"]
```

### Dynamic Snapshot Rate

```gdscript
# Adjust snapshot rate based on player count
func _on_player_connected(peer_id: int):
	var player_count = GameWorld.players.size()
	
	if player_count <= 4:
		StateReplicationManager.set_snapshot_rate(30.0)  # High rate for few players
	elif player_count <= 8:
		StateReplicationManager.set_snapshot_rate(20.0)  # Standard rate
	else:
		StateReplicationManager.set_snapshot_rate(15.0)  # Lower rate for many players
```

## Best Practices

1. **Always register entities on server only**
   - State replication is server-authoritative

2. **Use reliable RPCs for critical events**
   - Snapshots are unreliable for bandwidth
   - Important events (spawn/death) should use reliable RPCs

3. **Test with artificial lag**
   - Use Godot's network profiler
   - Test with 100-200ms latency

4. **Monitor bandwidth**
   - Check stats regularly
   - Adjust snapshot rate as needed

5. **Profile before optimizing**
   - Measure actual impact
   - Don't over-optimize prematurely

## Comparison: Old vs New System

| Feature | Old System | New System |
|---------|-----------|------------|
| Late Join Sync | Manual per-entity RPCs | Automatic baseline snapshot |
| Bandwidth | Full state every update | Delta compression |
| Priority | All entities equal | Distance/importance based |
| Lag Compensation | None | State history rewind |
| Interpolation | Manual per-entity | Built-in NetworkedEntity |
| Snapshot Rate | Fixed 20 Hz | Configurable 1-128 Hz |

## References

- Source Engine Networking: https://developer.valvesoftware.com/wiki/Source_Multiplayer_Networking
- Godot MultiplayerAPI: https://docs.godotengine.org/en/stable/classes/class_multiplayerapi.html
- Gabriel Gambetta - Fast-Paced Multiplayer: https://www.gabrielgambetta.com/client-server-game-architecture.html

