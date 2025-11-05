extends Node3D

# Bell Controller Script
# Handles bell behavior, interactions, and effects
signal bell_rang

@export var shot_sound: AudioStream # Sound played when the bell is shot
@export var melee_sound: AudioStream # Sound played when the bell is struck/melee'd
@export var ring_force: float = 1.0 # Reduced from 10.0 to be more sensitive
@export var ring_duration: float = 2.0
@export var bell_body_path: NodePath = NodePath("bell/StaticBody3D") # Configurable path

# Background-music handling -----------------------------
# Path to the AudioStreamPlayer (or AudioStreamPlayer3D/2D) that currently plays map music.
# In `maps/belltower.tscn` this is the node named "bgm" under the "env" node – assign that node here in the inspector.
# The script will swap its stream 0.5 s after the bell rings.
@export var bgm_player_path: NodePath = NodePath("../env/bgm")
# New music to switch to after the bell rings.
# Defaults to the requested BGM_00000006.mp3 – adjust if you prefer a different track.
@export var new_bgm_stream: AudioStream = preload("res://assets/snd/music/BGM_00000006.mp3")

var audio_player: AudioStreamPlayer
var is_ringing: bool = false
var ring_timer: Timer
var bell_body: Node # Could be Area3D, StaticBody3D, etc.
var _bgm_changed: bool = false # ensure we swap only once

func _ready():
	# Create audio player for bell sound
	audio_player = AudioStreamPlayer.new()
	# Stream will be assigned dynamically depending on hit type
	audio_player.stream = null
	# max_distance is only for 3D players; not needed for 2D AudioStreamPlayer
	add_child(audio_player)
	
	# Create timer for ring duration
	ring_timer = Timer.new()
	ring_timer.wait_time = ring_duration
	ring_timer.one_shot = true
	ring_timer.timeout.connect(_on_ring_finished)
	add_child(ring_timer)
	
	# Find and connect to bell collision body
	bell_body = get_node_or_null(bell_body_path)
	if not bell_body:
		# Try alternative paths
		bell_body = get_node_or_null("StaticBody3D")
		if not bell_body:
			bell_body = get_node_or_null("bell")
			if not bell_body:
				# Look for any StaticBody3D in children
				for child in get_children():
					if child is StaticBody3D:
						bell_body = child
						break
	
	if bell_body:
		# Connect to body_entered signal if the node supports it
		if bell_body.has_signal("body_entered"):
			bell_body.connect("body_entered", Callable(self, "_on_bell_hit"))
			print("Connected to body_entered signal on", bell_body)
		else:
			print("Warning: Node does not support body_entered signal. Consider using an Area3D with a body_entered signal for collision detection.")
	else:
		print("Warning: No StaticBody3D found for bell collision detection")

	emit_signal("bell_rang")
		

func ring_bell(sound: AudioStream):
	if is_ringing:
		return
		
	is_ringing = true
	# Notify listeners (e.g. GameMaster) that the bell has been rung
	emit_signal("bell_rang")
	
	# Play bell sound
	if audio_player and sound:
		audio_player.stream = sound
		audio_player.play()
	
	# BGM switching now handled by GameMaster
	# Schedule background-music change 0.5 s later (only the first time we ring)
	# if not _bgm_changed and new_bgm_stream and bgm_player_path != NodePath(""):
	# 	_bgm_changed = true
	# 	call_deferred("_schedule_bgm_change")
	
	# Add some visual feedback (rotation)
	var tween = create_tween()
	tween.tween_property(self, "rotation", rotation + Vector3(0.1, 0, 0), 0.1)
	tween.tween_property(self, "rotation", rotation, 0.1)
	
	# Start ring timer
	ring_timer.start()

func _on_bell_hit(body):
	print("Bell hit by: ", body.name)
	
	# Determine whether this is a projectile (shot) or melee hit
	var selected_sound: AudioStream = melee_sound
	var is_projectile = false
	
	# Check if it's a projectile by group
	if body.is_in_group("Projectile") or body.is_in_group("projectile") or body.is_in_group("Bullet"):
		is_projectile = true
		selected_sound = shot_sound
		print("Detected as projectile by group")
	
	# Check if it's a projectile by class name
	elif body.get_class() == "Bullet" or "bullet" in body.name.to_lower() or "projectile" in body.name.to_lower():
		is_projectile = true
		selected_sound = shot_sound
		print("Detected as projectile by name/class")
	
	# Check velocity for melee hits
	var should_ring = false
	if body.has_method("get_linear_velocity"):
		var velocity = body.get_linear_velocity()
		if velocity.length() > ring_force:
			should_ring = true
			print("Hit with sufficient velocity: ", velocity.length())
	else:
		# If no velocity method, assume it's a valid hit
		should_ring = true
		print("Hit by object without velocity method")
	
	# For projectiles, always ring regardless of velocity
	if is_projectile:
		should_ring = true
		print("Projectile hit - ringing bell")
	
	if should_ring:
		ring_bell(selected_sound)

func _on_ring_finished():
	is_ringing = false

# Public method to ring bell from external scripts
func ring(sound: AudioStream = shot_sound):
	ring_bell(sound)

func take_damage(damage_amount := 0, attacker: Variant = null):
	# Called by weapon_system.gd via apply_damage_to_target when bell is hit by a raycast/hitscan weapon.
	# We ignore damage amount and just ring with shot_sound.
	print("Bell took damage: ", damage_amount)
	if shot_sound:
		ring_bell(shot_sound)
	else:
		print("Warning: shot_sound not assigned on bell_controller") 

# Coroutine helper – waits 0.5 s, then swaps the music stream
func _schedule_bgm_change():
	await get_tree().create_timer(0.5).timeout
	_change_bgm()

# Actually change the stream and start playing it.
func _change_bgm():
	var bgm_player := get_node_or_null(bgm_player_path)
	if bgm_player and bgm_player is AudioStreamPlayer:
		bgm_player.stream = new_bgm_stream
		bgm_player.play()
		print("[BellController] BGM switched to", new_bgm_stream)
	else:
		print("[BellController] Unable to find BGM player at path", bgm_player_path) 
