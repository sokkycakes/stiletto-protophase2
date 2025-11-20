# FPS Multiplayer Template

A **game-agnostic** multiplayer FPS framework for Godot 4.3+ that extends existing systems with networking capabilities while maintaining backwards compatibility.

## 🎯 Overview

This template provides a complete foundation for creating multiplayer FPS games, built around the **GoldGdt** player controller system. It includes:

- **Server-authoritative** multiplayer with client prediction
- **Team-based** game modes (Deathmatch, Team Deathmatch, Cooperative)
- **Extensible architecture** that wraps existing systems
- **Drop-in compatibility** with your current FPS projects
- **Built-in UI** for lobbies, menus, and game HUD

## 🚀 Quick Start

### 1. Host a Game
1. Run the project
2. Enter your player name
3. Click "Host Game"
4. Configure game settings in the lobby
5. Click "Start Game" when ready

### 2. Join a Game
1. Run the project
2. Enter your player name  
3. Click "Join Game"
4. Enter server IP address (or use 127.0.0.1 for local)
5. Click "OK" to connect

### 3. Debug Controls (Development)
- **F1**: Quick host game
- **F2**: Quick join localhost
- **T**: Open chat in-game
- **Tab**: Show scoreboard (hold)
- **Esc**: Pause/close chat

## 🏗️ Architecture

### Core Systems

```
MultiplayerManager (Autoload)
├── Handles hosting/joining
├── Player connection management  
└── Game state coordination

GameRulesManager (Autoload)
├── Match flow and timing
├── Scoring and win conditions
└── Game mode logic

TeamManager (Autoload)
├── Team assignment and balancing
├── Team-based spawning
└── Team scoring
```

### Player Architecture

```
NetworkedPlayer
├── GoldGdt_Pawn (existing)
│   ├── Movement and camera
│   ├── Input handling
│   └── Physics
├── NetworkedWeaponManager
│   ├── Server-authoritative shooting
│   ├── Client prediction
│   └── Weapon synchronization  
├── PlayerState
│   ├── Health management
│   ├── Team assignment
│   └── Respawn logic
└── NetworkSync
    ├── Position synchronization
    ├── Animation sync
    └── State replication
```

## 🔧 Configuration

### Game Modes

The framework supports multiple game modes out of the box:

```gdscript
enum GameMode {
    DEATHMATCH,      # Free-for-all
    TEAM_DEATHMATCH, # Team vs team  
    COOPERATIVE      # PvE mode
}
```

### Network Settings

Default configuration in `project.godot`:
- **Port**: 7000
- **Max Players**: 8  
- **Server Authority**: Enabled
- **Client Prediction**: Enabled

### Team Configuration

Teams are auto-assigned and balanced:
- **Team 0**: Blue Team
- **Team 1**: Red Team
- **Team 2**: Green Team (6+ players)
- **Team 3**: Yellow Team (8+ players)

## 🎮 Adding Custom Content

### 1. Adding New Weapons

Extend the existing `BaseWeapon` class:

```gdscript
extends BaseWeapon
class_name MyCustomWeapon

func _ready():
    super._ready()
    # Your custom weapon logic
    
func _fire_hitscan():
    # Override for custom shooting behavior
    super._fire_hitscan()
```

Add to the weapon manager in your player scene.

### 2. Creating New Game Modes

Extend `GameRulesManager`:

```gdscript
# In GameRulesManager.gd
enum GameMode {
    DEATHMATCH,
    TEAM_DEATHMATCH,  
    COOPERATIVE,
    CAPTURE_THE_FLAG  # Your new mode
}

func start_match(mode: GameMode = GameMode.DEATHMATCH):
    match mode:
        GameMode.CAPTURE_THE_FLAG:
            _setup_ctf_mode()
        _:
            # Default behavior
            pass
```

### 3. Custom Maps

Create new scenes based on `game_world.tscn`:

1. Copy the base game world scene
2. Modify the level geometry
3. Adjust spawn points for your layout
4. Add to the map list in `LobbyMenu.gd`:

```gdscript
var available_maps: Array[Dictionary] = [
    {"name": "Default Arena", "path": "res://scenes/game_world.tscn"},
    {"name": "Your Custom Map", "path": "res://scenes/your_map.tscn"}
]
```

### 4. Adding Player Abilities

Extend `NetworkedPlayer`:

```gdscript
extends NetworkedPlayer
class_name CustomPlayer

# Add your abilities
var dash_cooldown: float = 0.0
var can_double_jump: bool = true

func _input(event):
    super._input(event)
    
    if Input.is_action_just_pressed("dash") and dash_cooldown <= 0:
        perform_dash.rpc()
        
@rpc("call_local", "reliable")
func perform_dash():
    # Dash logic here
    pass
```

## 🔌 Extending Existing Projects

### Integration Steps

1. **Copy Core Scripts**: Copy the `scripts/core/` folder to your project
2. **Update Project Settings**: Add autoloads for the managers
3. **Replace Player**: Use `NetworkedPlayer` instead of your current player
4. **Add UI**: Copy menu scenes and scripts
5. **Update Weapons**: Replace `WeaponManager` with `NetworkedWeaponManager`

### Backwards Compatibility

The framework maintains compatibility with existing GoldGdt projects:

- ✅ **GoldGdt_Pawn**: Works unchanged, wrapped by NetworkedPlayer
- ✅ **BaseWeapon**: Extended, not replaced  
- ✅ **WeaponManager**: Wrapped by NetworkedWeaponManager
- ✅ **Existing scenes**: Can be used with minimal changes

## 🌐 Networking Details

### Server Authority

The framework uses **server authority** for critical game state:

- **Health and damage**: Server validates all damage
- **Weapon firing**: Server confirms all shots
- **Player position**: Server has final say on positions
- **Game rules**: Server controls match flow

### Client Prediction

For responsive gameplay, clients predict:

- **Movement**: Local movement with server correction
- **Weapon firing**: Visual feedback before server confirmation  
- **Hit effects**: Immediate visual effects

### Network Optimization

- **Position sync**: 20 FPS for smooth movement
- **Weapon state**: 10 FPS for weapon info
- **Reliable events**: Health, damage, chat
- **Unreliable updates**: Position, rotation

## 🐛 Troubleshooting

### Common Issues

**"Players can't connect"**
- Check firewall settings
- Verify port 7000 is open
- Test with localhost (127.0.0.1) first

**"Weapons not firing"**  
- Ensure `NetworkedWeaponManager` is used
- Check weapon authority setup
- Verify muzzle_path is set correctly

**"Players not spawning"**
- Check spawn points are in "spawn_points" group
- Verify `SpawnPoint` script is attached
- Ensure spawn points have correct team assignments

**"Lag/desync issues"**
- Check network conditions
- Adjust sync rates in scripts
- Verify server authority settings

### Debug Commands

Enable debug builds for additional features:
- Console logging for network events
- Performance metrics
- Connection diagnostics

## 📁 Project Structure

```
fps_framework/
├── scenes/
│   ├── main_menu.tscn          # Main menu
│   ├── lobby.tscn              # Multiplayer lobby
│   ├── game_world.tscn         # Basic arena
│   └── NetworkedPlayer.tscn    # Networked player
├── scripts/
│   ├── core/
│   │   ├── MultiplayerManager.gd
│   │   ├── GameRulesManager.gd
│   │   ├── TeamManager.gd
│   │   ├── GameWorld.gd
│   │   └── SpawnPoint.gd
│   ├── player/
│   │   └── NetworkedPlayer.gd
│   ├── weapons/
│   │   └── NetworkedWeaponManager.gd
│   └── ui/
│       ├── MainMenu.gd
│       └── LobbyMenu.gd
├── GoldGdt/                    # Player controller
├── weapons/                    # Weapon system
└── player/                     # Player scenes
```

## 🎯 Best Practices

### Performance
- Limit networked properties to essential data
- Use `rpc_unreliable` for frequent updates
- Batch state changes when possible

### Security  
- Always validate input on server
- Use server authority for critical systems
- Implement basic anti-cheat measures

### Scalability
- Design systems to support 2-16 players
- Use object pooling for projectiles
- Optimize network bandwidth usage

## 🤝 Contributing

This is a template for your own projects. Feel free to:

- Modify systems to fit your game
- Add new game modes and features
- Optimize for your specific needs
- Share improvements with the community

## 📄 License

This template is provided as-is for game development. Use it freely in your projects, commercial or otherwise.

---

**Built with ❤️ for the Godot community**

Happy game development! 🎮
