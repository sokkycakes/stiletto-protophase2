extends Node3D
signal bell_rang
@export var shot_sound: AudioStream
@export var melee_sound: AudioStream
@export var ring_force: float = 1.0
@export var ring_duration: float = 2.0
@export var bell_body_path: NodePath = NodePath("bell/StaticBody3D")
@export var bgm_player_path: NodePath = NodePath("../env/bgm")
@export var new_bgm_stream: AudioStream = preload("res://assets/snd/music/BGM_00000006.mp3")
var audio_player: AudioStreamPlayer
var is_ringing: bool = false
var ring_timer: Timer
var bell_body: Node
var _bgm_changed: bool = false
func _ready():
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	ring_timer = Timer.new()
	ring_timer.wait_time = ring_duration
	ring_timer.one_shot = true
	ring_timer.timeout.connect(_on_ring_finished)
	add_child(ring_timer)
	bell_body = get_node_or_null(bell_body_path) or get_node_or_null("StaticBody3D") or get_node_or_null("bell") or _find_static_body()
	if bell_body and bell_body.has_signal("body_entered"):
		bell_body.connect("body_entered", Callable(self, "_on_bell_hit"))
	emit_signal("bell_rang")
func _find_static_body():
	for child in get_children():
		if child is StaticBody3D:
			return child
	return null
func ring_bell(sound: AudioStream):
	if is_ringing:
		return
	is_ringing = true
	emit_signal("bell_rang")
	if audio_player and sound:
		audio_player.stream = sound
		audio_player.play()
	var tween = create_tween()
	tween.tween_property(self, "rotation", rotation + Vector3(0.1, 0, 0), 0.1)
	tween.tween_property(self, "rotation", rotation, 0.1)
	ring_timer.start()
func _on_bell_hit(body):
	var selected_sound = melee_sound
	var is_projectile = body.is_in_group("Projectile") or body.is_in_group("projectile") or body.is_in_group("Bullet") or body.get_class() == "Bullet" or "bullet" in body.name.to_lower() or "projectile" in body.name.to_lower()
	if is_projectile:
		selected_sound = shot_sound
	var should_ring = is_projectile or (body.has_method("get_linear_velocity") and body.get_linear_velocity().length() > ring_force) or not body.has_method("get_linear_velocity")
	if should_ring:
		ring_bell(selected_sound)
func _on_ring_finished():
	is_ringing = false
func ring(sound: AudioStream = shot_sound):
	ring_bell(sound)
func take_damage(damage_amount := 0, attacker: Variant = null):
	ring_bell(shot_sound)
