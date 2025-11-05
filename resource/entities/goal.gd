extends Area3D

signal goal_reached

@export var routine_scene: PackedScene

var _routine_nodes: Array[Node] = []

func _ready():
    if routine_scene:
        var routine_instance = routine_scene.instantiate()
        add_child(routine_instance)
    _collect_routine_nodes()
    body_entered.connect(_on_body_entered)

func _collect_routine_nodes():
    _routine_nodes.clear()
    _scan_for_routines(self)


func _scan_for_routines(node: Node):
    for child in node.get_children():
        if child.has_method("on_goal_reached"):
            _routine_nodes.append(child)
        _scan_for_routines(child)

func _on_body_entered(body: Node):
    if body.is_in_group("player"):
        emit_signal("goal_reached", body)
        for node in _routine_nodes:
            node.call_deferred("on_goal_reached", body) 