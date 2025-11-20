# Discussing multiplayer bot design
_Exported on 11/10/2025 at 03:46:47 CST from Cursor (1.7.54)_

---

**User**

I want to talk though making a multiplayer bot for this project. I'll ask questions to establish understanding. Based on how this project looks, how would a multiplayer bot appear to you?

---

**Cursor**

## Bot Shape In This Project

- **Player-facing node**: Everything networked funnels through `ss_player_multiplayer.tscn`, which wraps the playable pawn, HUD, and a `MultiplayerSynchronizer` so transforms/inputs replicate without extra glue. The script adds the instance to both `player` groups and configures visibility per peer, so anything flagged as “player” (AI perception, damage, HUD) will treat a bot the same way as a human-controlled pawn.  
```624:776:resource/entities/player/ss_player_multiplayer.tscn
[node name="PlayerMultiplayer" type="Node3D" ...]
script = ExtResource("1_pawn")
...
[node name="MultiplayerSynchronizer" type="MultiplayerSynchronizer" parent="."]
```

- **Authority & input surface**: `ss_player_multiplayer.gd` decides whether the factory instance is local or remote, toggles the input driver, and relies on the synchronizer for replication. Replacing the human input node with an AI controller (or feeding synthesized commands into the existing “User Input” node) would give you a bot that the rest of the scene still thinks is a normal player.  
```30:214:resource/entities/player/ss_player_multiplayer.gd
peer_id = player_root.get_multiplayer_authority()
is_local_player = (peer_id == multiplayer.get_unique_id())
...
if is_local_player:
    _setup_local_player()
else:
    _setup_remote_player()
```

- **Spawn pipeline**: `BaseGameMaster` watches for map loads, runs character selection, and spawns the chosen player scene into the map, defaulting to whatever `available_characters` resolves to. A multiplayer bot would appear as an extra spawn request—either the server instantiates a player scene directly (using the same packed scene as humans) or the GameMaster gets a hook to spawn one after the human roster is ready.  
```57:210:resource/scripts/gamemode/base/base_gamemaster.gd
if not _scene_has_custom_gamemaster():
    ...
    call_deferred("_start_character_selection")
...
func _spawn_player():
    var player_scene = load(selected_character.scene_path)
    active_player = player_scene.instantiate()
    get_tree().current_scene.call_deferred("add_child", active_player)
```

- **Networking context**: `MultiplayerManager` is the glue for ENet hosting/joining, tracks peers, and hands out spawn positions. A bot controlled by the host would likely use the host’s authority (peer 1) and simply register itself in the manager’s bookkeeping so downstream systems still see a “connected player”.  
```36:265:resource/scripts/generic/multiplayer_manager.gd
var peer = ENetMultiplayerPeer.new()
...
connected_players[peer_id] = { "name": "Player" + str(peer_id), "ready": false }
```

- **AI reuse**: The enemy “NextBot” system already provides modular locomotion/vision/intention components (`EnhancedNextBot` et al.) that could be repurposed as the decision layer for a multiplayer bot. Plugging those behaviors into the player scene (instead of the human input script) keeps with the project’s composition rules and makes the bot feel like another NextBot-powered entity, just using player weapons instead of NPC attacks.

So, visually and architecturally, a multiplayer bot would show up exactly like another `PlayerMultiplayer` node in the scene tree: same camera rig, same weapon sync, same replication config—just with its input driven by an AI controller running on the server.

```plaintext
[node name="PlayerMultiplayer" type="Node3D" ...]
script = ExtResource("1_pawn")
...
[node name="MultiplayerSynchronizer" type="MultiplayerSynchronizer" parent="."]
```

```plaintext
peer_id = player_root.get_multiplayer_authority()
is_local_player = (peer_id == multiplayer.get_unique_id())
...
if is_local_player:
    _setup_local_player()
else:
    _setup_remote_player()
```

```plaintext
if not _scene_has_custom_gamemaster():
    ...
    call_deferred("_start_character_selection")
...
func _spawn_player():
    var player_scene = load(selected_character.scene_path)
    active_player = player_scene.instantiate()
    get_tree().current_scene.call_deferred("add_child", active_player)
```

```plaintext
var peer = ENetMultiplayerPeer.new()
...
connected_players[peer_id] = { "name": "Player" + str(peer_id), "ready": false }
```

---

**User**

I meant how would a multiplayer bot behave within the context of this project?

---

**Cursor**

A multiplayer “bot player” here would just be another `PlayerMultiplayer` pawn driven by AI logic instead of a human’s input device, so its moment-to-moment behaviour ends up being almost indistinguishable from a real client from the rest of the game’s perspective:

- **Spawning & Identity**: The host-side `BaseGameMaster` spawns player scenes through `_spawn_player()`, so a bot would be instantiated with the same packed scene (`ss_player_multiplayer.tscn`). It gains authority on the server, gets added to the `player`/`players` groups, and the `MultiplayerSynchronizer` inside the scene starts broadcasting its transforms just like any other pawn. No special network code is required—clients simply see it as another remote peer.  
```57:210:resource/scripts/gamemode/base/base_gamemaster.gd
var player_scene = load(selected_character.scene_path)
active_player = player_scene.instantiate()
get_tree().current_scene.call_deferred("add_child", active_player)
```

- **Movement & Physics**: The player scene is built around the GoldGdt stack (`GoldGdt_Body`, `GoldGdt_Move`, `GoldGdt_View`) and a `GoldGdt_Controls` node. Normally that node polls Godot input actions each physics tick, feeds the move module, and implements Quake-style air control, bunny-hopping, crouch logic, etc.  
```1:200:addons/GoldGdt/src/GoldGdt_Controls.gd
_gather_input()
_act_on_input()
...
Move._accelerate(...)
Move._airaccelerate(...)
```
For a bot, you’d bypass `_gather_input()` and write an AI driver that pushes desired movement vectors (and aim deltas) straight into `movement_input`, `move_dir`, or the downstream locomotion helpers. Because the motion module and body already handle friction, gravity, and stair stepping, the bot inherits all the same mobility behaviour as a skilled human player.

- **View & Aiming**: Camera rotation is routed through `GoldGdt_View`. Feeding artificial mouse deltas into `GoldGdt_Controls._handle_camera_input()` (or calling the view’s helper methods directly) keeps aim, recoil, and weapon sway consistent. Remote clients only receive the replicated transforms; they never know the inputs were synthetic.

- **Weapon & Ability Use**: The multiplayer script (`ss_player_multiplayer.gd`) exposes `sync_player_action()` RPC hooks for actions such as shooting/reloading. A bot would call those the same way the human-controlled pawn does—on the authority side it triggers weapon logic, and the RPC mirrors the event to everyone else.  
```238:264:resource/entities/player/ss_player_multiplayer.gd
@rpc("any_peer", "call_local", "unreliable")
func sync_player_action(action: String, data: Dictionary = {}):
    match action:
        "shoot":
            _handle_shoot_action(data)
```

- **Perception & Decision Making**: The project already has a componentised NextBot system (`EnhancedNextBot` plus vision/intention/locomotion components). When you run those on the server and have them manipulate the player controls instead of an enemy body, the bot gains threat tracking, path navigation, and state-driven decision logic that matches existing AI enemies while still presenting as a multiplayer peer.

- **Networking Semantics**: Because authority lives on the server, the bot behaves like a “local player” only on the host machine; `_setup_local_player()` will enable controls there, but you can immediately disable camera/mesh visibility so the server isn’t forced into first-person view. On all clients, the bot is treated as a remote player (`controls.movement_disabled = true`), and their `MultiplayerSynchronizer` simply streams whatever state the server produces.

In short, behaviourally the bot is just another authoritative `PlayerMultiplayer` instance that walks, strafes, aims, and fires using the same GoldGdt movement stack and weapon systems; the difference is that its input vectors are computed by the NextBot-style AI instead of Godot’s `Input` singleton, and the server keeps ownership so the replication layer continues to work unchanged.

```plaintext
var player_scene = load(selected_character.scene_path)
active_player = player_scene.instantiate()
get_tree().current_scene.call_deferred("add_child", active_player)
```

```plaintext
_gather_input()
_act_on_input()
...
Move._accelerate(...)
Move._airaccelerate(...)
```

```plaintext
@rpc("any_peer", "call_local", "unreliable")
func sync_player_action(action: String, data: Dictionary = {}):
    match action:
        "shoot":
            _handle_shoot_action(data)
```

---

**User**

Let's talk more specifically about the "indistinguishable from a human player" part. In terms of that context, what would the behaviors and states look like? What would the bot be trying to do? What actions would it be performing for these states?

---

**Cursor**

## Bot Behaviour States

- **Baseline goals**: Present as a normal `PlayerMultiplayer` node while pursuing the NextBot objectives—keep situational awareness, move with GoldGdt locomotion, fire weapons via `sync_player_action("shoot")`, and honour multiplayer authority checks so remote clients only see replicated transforms and RPCs.  
```30:214:resource/entities/player/ss_player_multiplayer.gd
peer_id = player_root.get_multiplayer_authority()
is_local_player = (peer_id == multiplayer.get_unique_id())
```

- **Idle**: Default “hands-off” stance. The bot stands in-place, occasionally turns its view, and reacts to vision or sound the way a cautious player would—swinging the camera toward noise, then stepping into Patrol or Seek when a threat is confirmed.  
```26:68:resource/scripts/enemy/actions/idle_action.gd
if look_around_timer >= look_around_interval:
    _look_around(bot)
...
if vision:
    var threat = vision.get_primary_known_threat(true)
    if threat:
        return ActionResult.change_to(SeekAndDestroyAction.new(), "threat detected")
```

- **Patrol**: Roams a loop of map-defined points (or procedurally sampled positions) with walking animation, pausing to look around. This mimics a human sweeping the map, ready to escalate if vision reports a threat or an odd sound needs checking.  
```34:146:resource/scripts/enemy/actions/patrol_action.gd
if patrol_points.size() > 0:
    var distance = bot.global_position.distance_to(target_point)
    if distance < 2.0:
        is_waiting = true
        _look_around(bot)
...
if vision:
    var threat = vision.get_primary_known_threat(true)
    if threat:
        return ActionResult.change_to(SeekAndDestroyAction.new(), "threat detected while patrolling")
```

- **Investigate**: When something suspicious happens, the bot walks to that spot, sweeps its view in a cardinal pattern, and searches nearby entities before either escalating or returning to its previous plan—just like a human checking a noise.  
```25:170:resource/scripts/enemy/actions/investigate_action.gd
if distance < investigation_radius:
    return _investigate_area(bot, delta)
...
if vision:
    var threat = vision.get_primary_known_threat(true)
    if threat:
        return ActionResult.change_to(SeekAndDestroyAction.new(), "threat found during investigation")
```

- **Seek & Destroy**: Sprint toward the last known location of a priority target, periodically re-pathing and refreshing the goal if vision reacquires the enemy. When close enough and in line of sight, it transitions into Attack; otherwise it keeps sweeping likely hiding spots.  
```37:167:resource/scripts/enemy/actions/seek_and_destroy_action.gd
if target and is_instance_valid(target):
    return _pursue_target(bot, delta)
...
if distance < 3.0 and vision and vision.is_able_to_see(target):
    return ActionResult.change_to(AttackAction.new(), "close enough to attack")
```

- **Attack**: Maintain optimal range (step in or back out), face the opponent, and trigger weapon usage through the player interface. Timeouts or losing sight cause a drop back to Seek, mirroring a human who repositions when they lose track of an enemy.  
```32:182:resource/scripts/enemy/actions/attack_action.gd
if distance > max_attack_range:
    locomotion.approach(target.global_position)
elif distance < min_attack_range:
    locomotion.approach(retreat_position)
...
if attack_timer >= attack_interval:
    attack_timer = 0.0
    _perform_attack(bot)
```

- **Retreat**: When health is low or the bot is outnumbered it sprints away, picks cover points, and checks periodically whether the area is safe before dropping back to Idle/Seek—matching a player who disengages to heal or regroup.  
```15:198:resource/scripts/enemy/actions/retreat_action.gd
if _is_safe(bot):
    return ActionResult.change_to(IdleAction.new(), "reached safety")
...
if not _is_position_safe(bot, retreat_position):
    _find_retreat_position(bot)
```

- **Utility pivots**: Stuck resolution, sound/vision callbacks, loot checks, and threat scoring all keep the bot’s reactions human-like (e.g., pausing to unstuck, ignoring pickups mid-fight, prioritising the most dangerous opponent).  
```116:255:resource/scripts/enemy/components/enhanced_intention_component.gd
if decision_timer >= decision_interval:
    _make_tactical_decision()
...
if threat and health_percentage < 0.3:
    if not current_action.is_named("Retreat"):
        change_action(RetreatAction.new())
```

### What the Bot Is Actively Doing

- Driving GoldGdt locomotion per state: sprinting, strafing, bunny-hopping if desired (`Move._accelerate`, `_airaccelerate`) while keeping camera deltas flowing to `GoldGdt_View`.
- Emitting player RPCs for weapons (`sync_player_action("shoot")`, reloads, ability triggers) so remote clients see muzzle flashes, damage, and ammo sync exactly like a human.
- Managing perception through the enhanced vision component so aim snaps toward seen threats and threat history informs target selection.
- Coordinating group-level behaviours (cover usage, prioritised threats, investigation) via the intention component so the multiplayer bot moves and reacts with the same cadence a human teammate would expect.

Net effect: every visible choice—where it stands, how it clears corners, when it pushes or retreats, when it fires—is backed by the same player controller and replicated state as a human, with the NextBot action stack deciding which “human-like” behaviour block to run at any moment.

```plaintext
peer_id = player_root.get_multiplayer_authority()
is_local_player = (peer_id == multiplayer.get_unique_id())
```

```plaintext
if look_around_timer >= look_around_interval:
    _look_around(bot)
...
if vision:
    var threat = vision.get_primary_known_threat(true)
    if threat:
        return ActionResult.change_to(SeekAndDestroyAction.new(), "threat detected")
```

```plaintext
if patrol_points.size() > 0:
    var distance = bot.global_position.distance_to(target_point)
    if distance < 2.0:
        is_waiting = true
        _look_around(bot)
...
if vision:
    var threat = vision.get_primary_known_threat(true)
    if threat:
        return ActionResult.change_to(SeekAndDestroyAction.new(), "threat detected while patrolling")
```

```plaintext
if distance < investigation_radius:
    return _investigate_area(bot, delta)
...
if vision:
    var threat = vision.get_primary_known_threat(true)
    if threat:
        return ActionResult.change_to(SeekAndDestroyAction.new(), "threat found during investigation")
```

```plaintext
if target and is_instance_valid(target):
    return _pursue_target(bot, delta)
...
if distance < 3.0 and vision and vision.is_able_to_see(target):
    return ActionResult.change_to(AttackAction.new(), "close enough to attack")
```

```plaintext
if distance > max_attack_range:
    locomotion.approach(target.global_position)
elif distance < min_attack_range:
    locomotion.approach(retreat_position)
...
if attack_timer >= attack_interval:
    attack_timer = 0.0
    _perform_attack(bot)
```

```plaintext
if _is_safe(bot):
    return ActionResult.change_to(IdleAction.new(), "reached safety")
...
if not _is_position_safe(bot, retreat_position):
    _find_retreat_position(bot)
```

```plaintext
if decision_timer >= decision_interval:
    _make_tactical_decision()
...
if threat and health_percentage < 0.3:
    if not current_action.is_named("Retreat"):
        change_action(RetreatAction.new())
```

---

**User**

I imagine the multiplayer bots being a bit more designed similarly to a fighting game where there are unique "Hero" characters with unique movesets, as well as universal tools like the kickback, wall jump, air stall and air dodge. How would the bot decide to use these resources?

---

**Cursor**

## Ability Decision Model

- **Hero loadout layer**: Treat each `CharacterDefinition` as mapping to a “hero kit” resource: one primary script for the core weapon (still using standard RPCs), plus plug-in modules like `KickbackModule`, `WarpstrikeModule`, `WallMovement`, hero‑specific ability nodes, etc. The bot’s controller reads those modules’ public API (`use_kickback()`, `use_air_dodge()`, `warpstrike_module._begin_warp(...)`, etc.) and their cooldown/state hooks.  
```125:226:resource/scripts/player/kickback_module.gd
func use_kickback():
    ...
    apply_kickback(kickbackAmount, kickbackOrientation)

func use_air_dodge() -> bool:
    if remainingAirDodges <= 0:
        return false
    ...
    return true
```

- **State integration**: Extend the `EnhancedIntentionComponent` so hero kits register custom evaluators when it calls `_make_tactical_decision()`. The base evaluation already scores threats and health; add hero-specific context (combos available, resources, positioning) before selecting or switching `NextBotAction`s.

## Universal Tools

- **Kickback / Gun-jump**: Treated as a burst-mobility option. Trigger when (a) need to close gap quickly (offensive), (b) avoid area denial (defensive), or (c) chain a wall-jump. Check `waitTimeBefCanUseKickAgain <= 0` and whether the vector to the target aligns with the kickback orientation before calling `use_kickback()`.  
    - Offensive heuristic: target within `6–12m`, line of sight, bot health > 40%, and combo window (e.g., planning to follow with hero special).  
    - Defensive heuristic: incoming projectile, low health, or threat flank detection triggers “escape” action that sets desired movement vector opposite threat and uses kickback if cooldown ready.

- **Wall jump / wall slide** (`WallMovement`): Whenever `wall_movement.can_wall_jump` is true and the bot is pursuing or escaping along surfaces, fire `wall_movement.wall_jump()` if it keeps velocity aligned with objective. Incorporate into movement planner so `NextBotAction` can temporarily favour hugging geometry to set up jumps.

- **Air dodge / stall**: When airborne and `KickbackModule.remainingAirDodges > 0`, calculate risk:  
    - Neutral dodge to adjust spacing mid-air (e.g., approaching enemy hero with aerial hitbox).  
    - Stall to bait enemy shots (no directional input sets `stallTimer` to freeze descent).  
    - Defensive emergency when prediction sees lethal damage (use to dodge and re-aim camera).  

- **Air stall chain**: After `use_air_dodge()` with no input, schedule a follow-up like `kickback_module.use_kickback()` once gravity resumes, providing fighting-game style double-movement mixups.

## Hero-Specific Movesets

- **Ability scoring**: Each hero ability exposes: cooldown remaining, resource cost, preferred target state (distance, enemy vulnerability), and self-state (grounded/airborne, facing). The AI computes a utility score from those factors + tactical state (aggressive/defensive, advantage). Example heuristics:
    - `WarpstrikeModule`: high utility when threat behind cover, hold-to-aim threshold reached, and anchor raycast finds surface (`_query_aim_point()` returns hit). Use to teleport behind target or reposition defensively.  
```93:214:resource/scripts/player/warpstrike_module.gd
if Input.is_action_just_pressed(input_action):
    _begin_warp(target, normal)
```
      Replace the direct input checks with AI calls that set `_state` transitions manually (call `_handle_idle()` semantics when the bot decides to warp).

    - Hero “EX” moves: tie to resource meter; only trigger when resource >= threshold, combo state flagged, and KO expectancy high.

- **Combo planner**: Build short scripted sequences per hero (openers, confirms, escape routes). Each sequence is a `NextBotAction` subclass storing step-by-step invocations (dash → special → kickback). The intention component picks sequences based on situation (advantage, punish opportunity). Once running, the action uses time windows and event callbacks (damage landed, enemy stunned) to branch to follow-ups.

## Decision Flow Example

1. **Perception**: `EnhancedVision` updates threat list; top threat at 8m, partially behind cover.
2. **Evaluation**: `EnhancedIntentionComponent` considers current action Idle → new threat; hero is “Warp Blade”.
3. **Sequence choice**: Offense tree sees “gap close + surprise” high score; selects `Warp Ambush Action`.
4. **Execution**:
    - Ensures `WarpstrikeModule` anchor available; uses `_query_aim_point()` to pick surface behind enemy, calls `_begin_warp(...)`.
    - On latch, triggers `use_kickback()` to exit warp with velocity, chains into primary attack RPC.
    - If enemy counters, defensive branch triggers `use_air_dodge()` plus `wall_movement.wall_jump()` to reset height.

## Resource Awareness

- Track cooldown timers (e.g., `KickbackModule.get_remaining_cooldown()`, hero ability timers).  
- Maintain hero state machine (grounded, wall-contact, airborne, anchored) to know which universals are legal.  
- Tie into health/armor/energy modules so the bot avoids burning powerful cooldowns when the payoff is low (e.g., hold warpstrike if team already has advantage).

## Implementation Summary

- **Ability registry**: Data class per hero listing abilities, cooldown getters, state checks, and scoring delegates.
- **Action specialisations**: Extend existing `NextBotAction`s (Seek, Attack, Retreat) with hero hooks—e.g., `AttackAction` consults hero’s “burst” ability to insert specials mid-combo, `RetreatAction` uses warp or air dodge.
- **Utility-based scheduling**: For each tick, evaluate utilities for (neutral tool, hero special, defensive option). Pick highest scoring that meets legality.  
- **Feedback**: After each ability, feed results (hit confirm, escape success) into `behavior_history` to bias future choices, keeping patterns human-like instead of perfectly optimal.

With this, the bot chooses universal tools as mobility/defense conditioners and fires hero-specific moves when their tactical utility peaks, mirroring how fighting-game players manage unique kits and shared mechanics.

```plaintext
func use_kickback():
    ...
    apply_kickback(kickbackAmount, kickbackOrientation)

func use_air_dodge() -> bool:
    if remainingAirDodges <= 0:
        return false
    ...
    return true
```

```plaintext
if Input.is_action_just_pressed(input_action):
    _begin_warp(target, normal)
```

---

**User**

Can we compare TF2 bot code to this?

---

**Cursor**

## TF2 Comparison

- **Action Stack Architecture**: TF2 bots inherit from `Action<CTFBot>` and rely on stackable behaviors (`OnStart`, `Update`, event hooks, and tactical queries like `ShouldAttack`, `ShouldRetreat`, `SelectMoreDangerousThreat`). This mirrors our GDScript `NextBotAction` pipeline—`EnhancedIntentionComponent` updates the current action, reacts to `ActionResult` transitions, and performs periodic threat assessments before deciding whether to change, suspend, or resume behaviors, giving us the same event-driven control surface inside Godot.  
```11:74:reference_sourcesdk/source-sdk-2013/src/game/server/tf/bot/behavior/tf_bot_behavior.h
class CTFBotMainAction : public Action< CTFBot >
{
	virtual ActionResult< CTFBot >	OnStart( CTFBot *me, Action< CTFBot > *priorAction );
	virtual ActionResult< CTFBot >	Update( CTFBot *me, float interval );
	...
	virtual QueryResultType ShouldAttack( const INextBot *me, const CKnownEntity *them ) const;
	virtual QueryResultType	ShouldRetreat( const INextBot *me ) const;
```
```112:175:resource/scripts/enemy/components/enhanced_intention_component.gd
func on_update(delta: float) -> void:
	var result = current_action.update(bot, delta)
	_handle_action_result(result)
	decision_timer += delta
	...
	match result.type:
		NextBotAction.ActionResultType.CHANGE_TO:
			if result.action:
				change_action(result.action)
```

- **Seek & Destroy Loop**: TF2’s roaming behavior constantly reevaluates nav goals, checks capture progress, suspends for attack actions, and recomputes its path when stuck. Our `SeekAndDestroyAction` follows the same pattern—refreshing targets via the vision interface, repathing, issuing locomotion commands, and toggling into `AttackAction` or `PatrolAction` based on distance or timeouts.  
```34:118:reference_sourcesdk/source-sdk-2013/src/game/server/tf/bot/behavior/tf_bot_seek_and_destroy.cpp
ActionResult< CTFBot > CTFBotSeekAndDestroy::Update( CTFBot *me, float interval )
{
	if ( m_giveUpTimer.HasStarted() && m_giveUpTimer.IsElapsed() )
		return Done( "Behavior duration elapsed" );
	...
	const CKnownEntity *threat = me->GetVisionInterface()->GetPrimaryKnownThreat();
	if ( threat && me->IsRangeLessThan( threat->GetLastKnownPosition(), engageRange ) )
		return SuspendFor( new CTFBotAttack, "Going after an enemy" );
	m_path.Update( me );
	if ( !m_path.IsValid() && m_repathTimer.IsElapsed() )
		RecomputeSeekPath( me );
```
```37:128:resource/scripts/enemy/actions/seek_and_destroy_action.gd
func update(bot_ref, delta: float) -> ActionResult:
	search_timer += delta
	repath_timer += delta
	_update_target(bot)
	if target and is_instance_valid(target):
		return _pursue_target(bot, delta)
	else:
		return _search_for_target(bot, delta)
...
	if repath_timer >= repath_interval:
		locomotion.approach(last_known_position)
	if search_timer > max_search_time:
		return ActionResult.change_to(PatrolAction.new(), "search timeout")
```

- **Class / Hero Specialisation**: TF2 keeps an extensive catalog of class-specific actions (e.g., the Engineer’s build state selects teleporter/sentry tasks, grants infinite metal in PvE, and overrides hurry queries). That is the template for our “hero” kits: each hero should register its own action modules and query overrides that plug into the shared intention stack, just as TF2 swaps in `CTFBotEngineerBuild` during Engineer play.  
```26:75:reference_sourcesdk/source-sdk-2013/src/game/server/tf/bot/behavior/engineer/tf_bot_engineer_build.cpp
Action< CTFBot > *CTFBotEngineerBuild::InitialContainedAction( CTFBot *me )
{
	if ( TFGameRules()->IsPVEModeActive() )
		return new CTFBotEngineerMoveToBuild;
	return new CTFBotEngineerBuildTeleportEntrance;
}
...
QueryResultType CTFBotEngineerBuild::ShouldHurry( const INextBot *meBot ) const
{
	CTFBot *me = (CTFBot *)meBot->GetEntity();
	CObjectSentrygun *mySentry = (CObjectSentrygun *)me->GetObjectOfType( OBJ_SENTRYGUN );
	...
}
```
```218:359:resource/scripts/enemy/components/enhanced_intention_component.gd
func _make_tactical_decision() -> void:
	var threat = vision.get_primary_known_threat(true)
	var health_percentage = _get_health_percentage()
	...
	if threat and health_percentage < 0.3:
		if not current_action.is_named("Retreat"):
			var retreat_action = RetreatAction.new()
			change_action(retreat_action)
```

- **Ability / Mobility Resources**: TF2 class behaviors trigger abilities when preconditions are met (e.g., Pyro reflects, Medic heals) by consulting timers and environment data. Our universal movement tools already expose similar hooks—`KickbackModule` handles cooldowns and switches to air-dodge logic when airborne, so hero-specific actions can call these as tactical responses just like TF2’s specialized actions do.  
```125:225:resource/scripts/player/kickback_module.gd
func use_kickback():
	if player.is_on_floor():
		if waitTimeBefCanUseKickAgain <= 0.0:
			apply_kickback(...)
			return true
	else:
		return use_air_dodge()
...
func use_air_dodge() -> bool:
	if remainingAirDodges <= 0:
		return false
	...
	player.velocity.x += horiz_impulse.x
	player.velocity.y = max(player.velocity.y, airDodgeVerticalBoost)
```

### What This Means For Hero Bots

- You already have the Source-style “main action + subordinate action stack” in GDScript; lean on it the way TF2 does by creating hero-specific `NextBotAction` classes (e.g., `HeroWarpAmbushAction`, `HeroGuardPointAction`) and plugging them into the intention’s tactical decision block.
- Use TF2’s class directories as a checklist—give each hero unique action modules that override shared queries (`should_attack`, `should_retreat`, resource meters) while still falling back to the universal Seek/Attack/Retreat loops when nothing special is available.
- For universal tools (kickback, wall jump, air dodge), treat them like TF2’s mobility/reflex abilities: expose quick utility functions on the hero action that call into `KickbackModule`, let the intention query whether cooldowns/charges are available, and schedule them during combo sequences or defensive interrupts.
- Build higher-level planners the same way TF2 suspends for targeted actions (`SuspendFor(new CTFBotAttack, ...)`): your `ActionResult.suspend_for` is already there, so chaining hero combos or defensive cancels only needs additional action classes plus the decision logic in `EnhancedIntentionComponent`.

Following the TF2 pattern keeps the bots readable, debuggable, and extensible while giving you a clear roadmap for hero-specific move logic on top of the shared multiplayer pawn.

```plaintext
class CTFBotMainAction : public Action< CTFBot >
{
	virtual ActionResult< CTFBot >	OnStart( CTFBot *me, Action< CTFBot > *priorAction );
	virtual ActionResult< CTFBot >	Update( CTFBot *me, float interval );
	...
	virtual QueryResultType ShouldAttack( const INextBot *me, const CKnownEntity *them ) const;
	virtual QueryResultType	ShouldRetreat( const INextBot *me ) const;
```

```plaintext
func on_update(delta: float) -> void:
	var result = current_action.update(bot, delta)
	_handle_action_result(result)
	decision_timer += delta
	...
	match result.type:
		NextBotAction.ActionResultType.CHANGE_TO:
			if result.action:
				change_action(result.action)
```

```cpp
ActionResult< CTFBot > CTFBotSeekAndDestroy::Update( CTFBot *me, float interval )
{
	if ( m_giveUpTimer.HasStarted() && m_giveUpTimer.IsElapsed() )
		return Done( "Behavior duration elapsed" );
	...
	const CKnownEntity *threat = me->GetVisionInterface()->GetPrimaryKnownThreat();
	if ( threat && me->IsRangeLessThan( threat->GetLastKnownPosition(), engageRange ) )
		return SuspendFor( new CTFBotAttack, "Going after an enemy" );
	m_path.Update( me );
	if ( !m_path.IsValid() && m_repathTimer.IsElapsed() )
		RecomputeSeekPath( me );
```

```plaintext
func update(bot_ref, delta: float) -> ActionResult:
	search_timer += delta
	repath_timer += delta
	_update_target(bot)
	if target and is_instance_valid(target):
		return _pursue_target(bot, delta)
	else:
		return _search_for_target(bot, delta)
...
	if repath_timer >= repath_interval:
		locomotion.approach(last_known_position)
	if search_timer > max_search_time:
		return ActionResult.change_to(PatrolAction.new(), "search timeout")
```

```cpp
Action< CTFBot > *CTFBotEngineerBuild::InitialContainedAction( CTFBot *me )
{
	if ( TFGameRules()->IsPVEModeActive() )
		return new CTFBotEngineerMoveToBuild;
	return new CTFBotEngineerBuildTeleportEntrance;
}
...
QueryResultType CTFBotEngineerBuild::ShouldHurry( const INextBot *meBot ) const
{
	CTFBot *me = (CTFBot *)meBot->GetEntity();
	CObjectSentrygun *mySentry = (CObjectSentrygun *)me->GetObjectOfType( OBJ_SENTRYGUN );
	...
}
```

```plaintext
func _make_tactical_decision() -> void:
	var threat = vision.get_primary_known_threat(true)
	var health_percentage = _get_health_percentage()
	...
	if threat and health_percentage < 0.3:
		if not current_action.is_named("Retreat"):
			var retreat_action = RetreatAction.new()
			change_action(retreat_action)
```

```plaintext
func use_kickback():
	if player.is_on_floor():
		if waitTimeBefCanUseKickAgain <= 0.0:
			apply_kickback(...)
			return true
	else:
		return use_air_dodge()
...
func use_air_dodge() -> bool:
	if remainingAirDodges <= 0:
		return false
	...
	player.velocity.x += horiz_impulse.x
	player.velocity.y = max(player.velocity.y, airDodgeVerticalBoost)
```

