class_name AdvancedGrapplingHook3D_V2
extends "res://addons/grappling_hook_3d/src/hook_controller.gd"

# -----------------------------------------------------------------------------
#  AdvancedGrapplingHook3D – *V2*
# -----------------------------------------------------------------------------
#  This script is a light-weight extension of the original AdvancedGrapplingHook3D
#  that focuses on *feel* rather than on introducing completely new behaviour.
#
#  1.  Momentum Smoothing
#      – The abrupt velocity set that occurred when the hook latched is replaced
#        with a blended acceleration so the player keeps some of their current
#        speed & direction before gradually being redirected towards the hook.
#
#  2.  Kick-Boost while Reeling
#      – Pressing the existing "pm_gunjump" / kick-back action **while still
#        holding the grapple button and being in the GRAPPLE_PULLING_PLAYER
#        state** will grant an extra burst of velocity.  The impulse is biased
#        upward so it can be used to clear vertical gaps or gain height.
#
#  All of the heavy logic (charge handling, enemy interaction, etc.) stays in
#  the base script – we only override the specific pieces we need to tweak.
# -----------------------------------------------------------------------------

# --- Tweaking knobs -----------------------------------------------------------
@export_group("Pull Smoothing")
@export var pull_acceleration : float = 25.0   # How quickly we approach the target pull speed (m/s^2)
@export var initial_velocity_blend : float = 0.35 # 0 = keep original velocity, 1 = fully replace
@export var hook_direction_blend : float = 0.65 # How much to blend toward hook direction (0.65 = 65% hook, 35% original)

@export_group("Kick-Boost Settings")
@export var kickboost_vertical : float = 8.0           # Pure upward velocity that gets added
@export var kickboost_forward_multiplier : float = 0.6 # Additional velocity along hook direction
@export var kickboost_charge_refill_time : float = 0.8 # Time to refill charges after kickboost (faster than normal)

# --- Internal -----------------------------------------------------------------
var _pre_transition_velocity : Vector3 = Vector3.ZERO
var _target_pull_direction  : Vector3 = Vector3.ZERO

# -----------------------------------------------------------------------------
#  State handling – we intercept the transition into GRAPPLE_PULLING_PLAYER so
#  we can smooth the initial velocity rather than replacing it outright.
# -----------------------------------------------------------------------------
func set_state(new_state : GrappleState) -> void:
    # Cache velocity before the base method potentially overwrites it.
    if player_body and player_body is CharacterBody3D:
        _pre_transition_velocity = player_body.velocity
    else:
        _pre_transition_velocity = Vector3.ZERO

    # Call the original implementation (does all the heavy lifting).
    super.set_state(new_state)

    # If we've just started pulling the player, blend velocity instead of hard set.
    if new_state == GrappleState.GRAPPLE_PULLING_PLAYER and player_body and player_body is CharacterBody3D:
        # Direction towards hook has already been calculated inside the base call
        # and the velocity has been set to that direction * pull_speed.  We'll
        # retrieve that velocity and blend it with the velocity we had before.
        var current_pull_velocity : Vector3 = player_body.velocity
        player_body.velocity = _pre_transition_velocity.lerp(current_pull_velocity, hook_direction_blend)
        _target_pull_direction  = (grapple_target_point - player_body.global_position).normalized()

# -----------------------------------------------------------------------------
#  Player pull processing – we override just enough to introduce acceleration
#  towards the desired velocity (momentum smoothing) and hook-kick boost.
# -----------------------------------------------------------------------------
func process_player_pull(delta : float) -> void:
    # 1.  If the player releases the grapple we fall back to the base logic.
    if not is_grapple_button_held:
        initiate_retraction()
        return

    if not player_body or player_body == null or not (player_body is CharacterBody3D):
        # Fallback to original implementation for non-CharacterBody players.
        super.process_player_pull(delta)
        return

    # Anchor point = where the rope is truly attached (with optional wall offset).
    var anchor_pos : Vector3 = grapple_target_point - (grapple_target_normal * snap_offset) if grapple_target_normal != Vector3.ZERO else grapple_target_point

    # Re-calculate direction every frame (rope can move slightly if target moves).
    var dir_to_hook : Vector3 = (anchor_pos - player_body.global_position).normalized()
    _target_pull_direction = dir_to_hook # store for kick-boost

    # Desired velocity we ultimately want to reach.
    var desired_velocity : Vector3 = dir_to_hook * pull_speed

    # Blend / accelerate current velocity towards desired velocity.
    var step : float = pull_acceleration * delta
    player_body.velocity = player_body.velocity.move_toward(desired_velocity, step)

    # Minimum speed clamp (reuse from base).
    if player_body.velocity.length() < grapple_min_velocity:
        player_body.velocity = dir_to_hook * grapple_min_velocity

    # Extra decay so it still "feels" like the original controller.
    player_body.velocity *= grapple_velocity_decay

    # Kick-boost – just-pressed event for pm_gunjump while still reeling.
    if Input.is_action_just_pressed("pm_gunjump"):
        _apply_kickboost()

    # Move the player
    player_body.move_and_slide()

    # Snap when close enough.
    if player_body.global_position.distance_to(anchor_pos) < 0.5:
        player_body.global_position = anchor_pos
        player_body.velocity       = Vector3.ZERO
        is_player_stuck_to_wall    = true

# -----------------------------------------------------------------------------
#  Kick-boost helper
# -----------------------------------------------------------------------------
func _apply_kickboost() -> void:
    if not player_body or not (player_body is CharacterBody3D):
        return

    # Get camera for look direction
    var camera = get_viewport().get_camera_3d()
    if not camera:
        return

    # Check leash distance - don't allow boost if it would exceed max hook distance
    var current_distance = player_body.global_position.distance_to(grapple_target_point)
    var max_hook_distance = get_dynamic_distance()
    
    if current_distance >= max_hook_distance:
        # Already at max distance, don't boost
        return

    # Build boost vector – upward plus a portion along the camera's forward direction.
    var look_direction = -camera.global_transform.basis.z.normalized()
    var boost : Vector3 = look_direction * (pull_speed * kickboost_forward_multiplier)
    boost.y += kickboost_vertical

    # Check if this boost would exceed the leash distance
    var projected_position = player_body.global_position + boost * 0.1 # Small step to check
    var projected_distance = projected_position.distance_to(grapple_target_point)
    
    if projected_distance > max_hook_distance:
        # Scale down the boost to stay within leash distance
        var scale_factor = (max_hook_distance - current_distance) / (projected_distance - current_distance)
        boost *= scale_factor

    player_body.velocity += boost

    # Consume all charges and set faster refill
    current_charges = 0
    charges_changed.emit(current_charges)
    
    # Set all timers to the faster kickboost refill time
    for i in range(MAX_CHARGES):
        charge_timers[i] = kickboost_charge_refill_time

    # Optional: reuse hook_pull_sound for audible feedback.
    play_sound(hook_pull_sound, 1.15)
