# Enemy AI Agents

This folder contains 3 enemy AI agents created as derivatives from LimboAI's included examples. Each enemy uses the original LimboAI behavior trees and assets without modification.

## Enemy Types

### 1. Melee Enemy (`melee_enemy.tscn`)
- **Based on**: `Demo/agents/01_agent_melee_simple.tscn`
- **Behavior Tree**: `Demo/ai/trees/01_agent_melee_simple.tres`
- **Health**: 3 HP
- **Behavior**: Simple melee combat AI that pursues the player and attacks when in range
- **Key Features**:
  - Finds and targets the player
  - Pursues the target directly
  - Faces the target when attacking
  - Simple and aggressive behavior

### 2. Charger Enemy (`charger_enemy.tscn`)
- **Based on**: `Demo/agents/02_agent_charger.tscn`
- **Behavior Tree**: `Demo/ai/trees/02_agent_charger.tres`
- **Health**: 8 HP
- **Damage**: 2.0 (higher than melee)
- **Behavior**: Charging AI that flanks and rushes the player
- **Key Features**:
  - Finds flanking positions around the target
  - Charges forward with momentum
  - Higher health and damage than melee type
  - More tactical positioning

### 3. Ranged Enemy (`ranged_enemy.tscn`)
- **Based on**: `Demo/agents/05_agent_ranged.tscn`
- **Behavior Tree**: `Demo/ai/trees/05_agent_ranged.tres`
- **Health**: 6 HP
- **Behavior**: Ranged combat AI that maintains distance and shoots projectiles
- **Key Features**:
  - Maintains optimal range from target
  - Shoots projectiles (ninja stars)
  - Repositions to maintain line of sight
  - Balanced health between melee and charger

## Test Scene

Use `enemy_test_scene.tscn` to test all three enemy types together. The scene includes:
- A player character for the enemies to target
- One instance of each enemy type positioned around the player
- A camera focused on the action

## Usage

These enemies are ready to use in your game scenes. Simply instantiate the `.tscn` files where needed. The AI will automatically:
- Target players in the "player" group
- Execute their respective behavior patterns
- Handle damage and death states
- Play appropriate animations

## Dependencies

These enemies require:
- LimboAI plugin (included in the demo)
- The original LimboAI demo assets and behavior trees
- The `agent_base.tscn` from the demo project

All behavior trees and custom tasks from the original LimboAI demo are used without modification.
