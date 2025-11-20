# FPS Multiplayer Template - Setup Guide

## 🚀 Quick Setup (5 Minutes)

### 1. Import the Template
1. Open Godot 4.3+
2. Import this project or copy to your existing project
3. Verify autoloads are configured in Project Settings

### 2. Test Locally
1. Press **F5** to run the project
2. Press **F1** to quick-host a game
3. Run a second instance and press **F2** to quick-join

That's it! You should have a working multiplayer FPS.

## 📋 Detailed Setup

### Prerequisites Checklist
- [ ] **Godot 4.3+** installed
- [ ] **Network permissions** (firewall configured for port 7000)
- [ ] **Multiple instances** capability for testing

### Project Configuration

#### 1. Autoloads (Automatic)
These are already configured in `project.godot`:
```
MultiplayerManager="*res://scripts/core/MultiplayerManager.gd"
GameRulesManager="*res://scripts/core/GameRulesManager.gd"
TeamManager="*res://scripts/core/TeamManager.gd"
```

#### 2. Input Map (Automatic)
Standard FPS controls are pre-configured:
- **WASD**: Movement
- **Mouse**: Camera control
- **Left Click**: Fire weapon
- **R**: Reload
- **T**: Chat
- **Tab**: Scoreboard
- **1,2,3**: Weapon switching

#### 3. Network Settings (Configurable)
Default settings in `MultiplayerManager.gd`:
```gdscript
const DEFAULT_PORT = 7000
const MAX_CLIENTS = 8
```

## 🔌 Integration with Existing Projects

### Step-by-Step Integration

#### 1. Copy Core Files
Copy these directories to your project:
```
scripts/core/        # Multiplayer managers
scripts/player/      # NetworkedPlayer
scripts/weapons/     # NetworkedWeaponManager  
scripts/ui/          # Menu systems
scenes/              # UI and game scenes
```

#### 2. Update Project Settings
Add to your `project.godot`:
```ini
[autoload]
MultiplayerManager="*res://scripts/core/MultiplayerManager.gd"
GameRulesManager="*res://scripts/core/GameRulesManager.gd"
TeamManager="*res://scripts/core/TeamManager.gd"

[input]
# Copy input actions from template project.godot
```

#### 3. Replace Player System
```gdscript
# OLD: Direct GoldGdt_Pawn usage
extends GoldGdt_Pawn

# NEW: Use NetworkedPlayer wrapper
extends NetworkedPlayer
# Access GoldGdt features through .pawn property
```

#### 4. Update Weapon System
```gdscript
# OLD: WeaponManager
extends WeaponManager

# NEW: NetworkedWeaponManager  
extends NetworkedWeaponManager
# All WeaponManager functionality preserved + networking
```

#### 5. Set Main Scene
Update your project to use the main menu:
```
Project Settings > Application > Run > Main Scene = "res://scenes/main_menu.tscn"
```

## 🎮 Testing Your Setup

### Local Testing Protocol

#### Test 1: Basic Functionality
1. **Run Project**: Press F5
2. **Host Game**: Enter name, click "Host Game"
3. **Join Game**: Run second instance, join 127.0.0.1
4. **Verify**: Both players should see each other

#### Test 2: Gameplay Features
1. **Movement**: Walk around, verify sync
2. **Chat**: Press T, send messages
3. **Weapons**: Left click to fire (if weapons configured)
4. **Teams**: Check team assignment in lobby

#### Test 3: Network Resilience
1. **Disconnect**: Close one instance
2. **Reconnect**: Join again
3. **Host Migration**: Close host, verify handling

### Network Testing Protocol

#### Test 1: LAN Testing
1. **Find Host IP**: Use `ipconfig` or `ifconfig`
2. **Configure Firewall**: Open port 7000
3. **Connect**: Join using host's LAN IP
4. **Verify Performance**: Check for lag/desync

#### Test 2: Internet Testing
1. **Port Forward**: Configure router for port 7000
2. **Public IP**: Use external IP address
3. **Connect**: Join from different network
4. **Monitor**: Check connection stability

## 🛠️ Customization Options

### Easy Customizations

#### Change Network Port
```gdscript
# In MultiplayerManager.gd
const DEFAULT_PORT = 8080  # Your custom port
```

#### Modify Player Count
```gdscript
# In MultiplayerManager.gd
const MAX_CLIENTS = 16  # Support more players
```

#### Add Custom Game Modes
```gdscript
# In GameRulesManager.gd
enum GameMode {
    DEATHMATCH,
    TEAM_DEATHMATCH,
    COOPERATIVE,
    YOUR_CUSTOM_MODE  # Add here
}
```

#### Create Custom Maps
1. Copy `scenes/game_world.tscn`
2. Modify level geometry
3. Add to map list in `LobbyMenu.gd`

### Advanced Customizations

#### Custom Player Abilities
```gdscript
# Extend NetworkedPlayer
extends NetworkedPlayer

func _input(event):
    super._input(event)
    
    if Input.is_action_just_pressed("special_ability"):
        use_special_ability.rpc()

@rpc("call_local", "reliable")
func use_special_ability():
    # Your custom ability
    pass
```

#### Custom Weapon Types
```gdscript
# Extend BaseWeapon
extends BaseWeapon

func _fire_hitscan():
    # Your custom firing logic
    super._fire_hitscan()
```

## 🐛 Troubleshooting

### Common Issues

#### "Can't Connect to Server"
**Symptoms**: Join fails, timeout errors
**Solutions**:
- Check firewall settings (port 7000)
- Verify IP address is correct
- Test with localhost (127.0.0.1) first
- Ensure host is actually running

#### "Players Not Syncing"
**Symptoms**: Players don't see each other move
**Solutions**:
- Check network connectivity
- Verify MultiplayerSynchronizer setup
- Check for script errors in console
- Restart both instances

#### "Weapons Not Working"
**Symptoms**: Shooting doesn't work
**Solutions**:
- Ensure NetworkedWeaponManager is used
- Check weapon setup in player scene
- Verify muzzle_path is configured
- Check for BaseWeapon script errors

#### "Poor Performance"
**Symptoms**: Low FPS, lag, stuttering
**Solutions**:
- Reduce MAX_CLIENTS if needed
- Check network bandwidth
- Monitor memory usage
- Optimize custom scripts

### Debug Tools

#### Enable Debug Logging
```gdscript
# In any script, add debug prints
if OS.is_debug_build():
    print("Debug info: ", data)
```

#### Network Statistics
Monitor these values during testing:
- **Frame Rate**: Should maintain 60 FPS
- **Network Latency**: <100ms on LAN
- **Packet Loss**: Should be 0%
- **Bandwidth**: <100 KB/s per player

#### Console Commands
Development shortcuts:
- **F1**: Quick host
- **F2**: Quick join localhost
- **F5**: Refresh UI elements
- **F10**: Show debug info (if implemented)

## 📦 Deployment Preparation

### For Development
1. **Export Settings**: Configure for your target platform
2. **Network Permissions**: Test firewall rules
3. **Multiple Builds**: Create separate host/client builds if needed

### For Distribution
1. **Headless Server**: Export server without graphics
2. **Client Builds**: Include connection UI
3. **Documentation**: Provide user setup instructions
4. **Testing**: Verify on clean machines

## 🎯 Next Steps

### Immediate Actions
1. **Test Template**: Run through testing protocols
2. **Customize Settings**: Adjust for your game
3. **Add Content**: Implement your weapons/maps/modes
4. **Performance Test**: Verify with target player count

### Development Path
1. **Art Assets**: Replace placeholder graphics
2. **Audio**: Add sound effects and music
3. **Game Modes**: Implement custom gameplay
4. **UI Polish**: Enhance menus and HUD
5. **Anti-Cheat**: Strengthen server validation

### Production Readiness
1. **Stress Testing**: Test with maximum players
2. **Security Audit**: Validate anti-cheat measures
3. **Performance Optimization**: Profile and optimize
4. **User Testing**: Get feedback from players

---

**Need Help?** Check the other documentation files:
- **README.md**: Feature overview and usage
- **IMPLEMENTATION_NOTES.md**: Technical details
- **CHANGELOG.md**: Version history and features

**Happy multiplayer development!** 🎮