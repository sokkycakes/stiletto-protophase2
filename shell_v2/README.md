# Stiletto Proto - Web Shell v2

A modern, full-featured web launcher for Godot web exports - inspired by Quake Live and InstantAction.

## Overview

This is a complete web application launcher that provides a full frontend interface before launching the game. It features multiple views, settings management, and a game-like application experience.

## Structure

### Files

- **index.html** - Main application structure with multiple views
- **styles.css** - Complete styling system with dark theme
- **app.js** - Application logic, view management, and game launcher
- **README.md** - This file

## Features

### Application Structure

- ✅ **Full Launcher Interface** - No auto-start, user-controlled game launch
- ✅ **Multi-View System** - Home, Play, Settings, Stats, About views
- ✅ **Sidebar Navigation** - Easy navigation between sections
- ✅ **Top Navigation Bar** - Window controls (minimize, maximize, close)
- ✅ **View Switching** - Smooth transitions between different screens

### Home View

- Quick Play button for instant game start
- Settings shortcut
- System status indicators
- Welcome messaging

### Play View

- Single Player option (functional)
- Multiplayer placeholder (coming soon)
- Clear game mode selection

### Settings View

- **Video Settings** - Resolution, quality, V-Sync
- **Audio Settings** - Master, music, and SFX volume controls
- **Controls Settings** - Mouse sensitivity, Y-axis inversion
- **Gameplay Settings** - FPS counter, crosshair options
- Settings persistence with LocalStorage
- Reset to defaults option

### Stats View

- Matches played counter
- Win/Loss tracking
- K/D ratio display
- Placeholder for future stat integration

### About View

- Version information
- Engine details
- Platform information

### Game Integration

- Hidden game container (shown on launch)
- Loading overlay with progress bar
- Error handling with back-to-menu option
- In-game overlay with exit button
- Escape key to exit game
- Smooth transitions between launcher and game

## Technology Stack

- **Bootstrap 5.3.3** - UI framework and components
- **Bootstrap Icons** - Comprehensive icon library
- **Vanilla JavaScript** - Modular application architecture
- **CSS3** - Advanced styling with gradients and animations
- **LocalStorage** - Settings persistence

## Architecture

Following SOLID principles and modular design:

### JavaScript Modules

1. **CONFIG** - Centralized configuration object
2. **AppState** - Application state management and settings
3. **ViewManager** - View switching and navigation
4. **GameManager** - Game lifecycle and integration
5. **UIHandlers** - Event handling and user interactions
6. **Application** - Main initialization and system checks

### Key Design Patterns

- **State Management** - Centralized application state
- **Module Pattern** - Separate concerns into focused modules
- **Event-Driven** - Responsive UI with proper event handling
- **Configuration-Based** - Easy to modify and extend
- **Error Handling** - Graceful error management

## Usage

### For Development

Open `index.html` in a modern browser to see the launcher interface. The game canvas is hidden until you click "Quick Play" or "Start Game".

### For Godot Integration

Replace the placeholder `initializeGameEngine()` function in `GameManager` with actual Godot engine initialization code from the web export template.

Key integration points:
- Canvas element: `#canvas`
- Progress callback: Update `#progress-bar` and `#progress-text`
- Status callback: Update `#status-text`
- Error callback: Call `GameManager.showError(message)`

## Browser Compatibility

Tested and designed for:
- Chrome/Edge 90+
- Firefox 88+
- Safari 14+
- Mobile browsers (iOS Safari, Chrome Mobile)

## Responsive Design

- Desktop: Full sidebar with text labels
- Tablet: Compact sidebar
- Mobile: Icon-only sidebar

## Keyboard Shortcuts

- **Escape** - Exit game (when running)
- Additional shortcuts can be added in the keyboard event handler

## Settings Persistence

Settings are automatically saved to LocalStorage and persist across sessions:
- Video preferences
- Audio levels
- Control sensitivity
- Gameplay options

## Future Expansion Points

The architecture is designed to easily add:
- Server browser (for multiplayer)
- Friend lists and social features
- News/update feeds
- Achievement system
- Replay system
- Custom keybinding UI
- Profile management

## Notes

- Uses CDN links for Bootstrap (can be replaced with local files for offline use)
- Tabs used for indentation (project standard)
- Dark theme inspired by GitHub's design system
- Smooth animations and transitions
- Fully modular and extensible
- Ready for Godot web export integration

