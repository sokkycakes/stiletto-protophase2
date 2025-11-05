extends Node

@export var main_text: String = "GOAL REACHED!"
@export var sub_text: String = "Press F to respawn"
@export var respawn_key: Key = KEY_F

var _overlay: CanvasLayer
var _player: Node
var _paused_previously: bool = false

func on_goal_reached(player: Node):
    _player = player
    _disable_player_input()
    _show_overlay()
    self.set_process_input(true)
    # Ensure we continue processing even when game is paused
    self.process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event):
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == respawn_key:
        respawn()

func respawn():
    _hide_overlay()
    _enable_player_input()
    get_tree().reload_current_scene()

func _disable_player_input():
    # Save existing pause state
    _paused_previously = get_tree().paused
    get_tree().paused = true

func _enable_player_input():
    get_tree().paused = _paused_previously

func _show_overlay():
    if _overlay and is_instance_valid(_overlay):
        return
    _overlay = CanvasLayer.new()
    _overlay.layer = 100
    var panel := CenterContainer.new()
    panel.anchor_left = 0.0
    panel.anchor_top = 0.0
    panel.anchor_right = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left = 0.0
    panel.offset_top = 0.0
    panel.offset_right = 0.0
    panel.offset_bottom = 0.0
    var vbox := VBoxContainer.new()
    vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    panel.add_child(vbox)
    var main_label := Label.new()
    main_label.text = main_text
    main_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    main_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    main_label.add_theme_font_size_override("font_size", 64)
    vbox.add_child(main_label)
    var sub_label := Label.new()
    sub_label.text = sub_text
    sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    sub_label.add_theme_font_size_override("font_size", 24)
    vbox.add_child(sub_label)
    _overlay.add_child(panel)
    get_tree().get_root().add_child(_overlay)

func _hide_overlay():
    if _overlay and is_instance_valid(_overlay):
        _overlay.queue_free()
        _overlay = null 