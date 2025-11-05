extends Node

signal hitbox_entered(hitbox: Area3D, body: Node3D)
signal hitbox_exited(hitbox: Area3D, body: Node3D)

@export_node_path("Area3D") var hurtbox_path: NodePath
@onready var hurtbox: Area3D = get_node(hurtbox_path)

@export_node_path("Area3D") var detection_box_path: NodePath
@onready var detection_box: Area3D = get_node(detection_box_path)

var hitboxes: Array[Area3D] = []

func _ready() -> void:
	if not hurtbox:
		push_error("Hurtbox not set in the inspector!")
		return
		
	if not detection_box:
		push_error("Detection Box not set in the inspector!")
		return
	
	# Connect signals for hurtbox
	hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	hurtbox.body_exited.connect(_on_hurtbox_body_exited)
	
	# Connect signals for detection box
	detection_box.body_entered.connect(_on_detection_box_body_entered)
	detection_box.body_exited.connect(_on_detection_box_body_exited)
	
	# Find all hitboxes in children
	for child in get_children():
		if child is Area3D and child != hurtbox and child != detection_box:
			hitboxes.append(child)
			child.body_entered.connect(_on_hitbox_body_entered.bind(child))
			child.body_exited.connect(_on_hitbox_body_exited.bind(child))

func _on_hurtbox_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_attack"):
		# Handle taking damage from player attacks
		pass

func _on_hurtbox_body_exited(body: Node3D) -> void:
	pass

func _on_detection_box_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		# Handle player entering detection range
		pass

func _on_detection_box_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		# Handle player leaving detection range
		pass

func _on_hitbox_body_entered(body: Node3D, hitbox: Area3D) -> void:
	hitbox_entered.emit(hitbox, body)

func _on_hitbox_body_exited(body: Node3D, hitbox: Area3D) -> void:
	hitbox_exited.emit(hitbox, body)

func add_hitbox(hitbox: Area3D) -> void:
	hitboxes.append(hitbox)
	hitbox.body_entered.connect(_on_hitbox_body_entered.bind(hitbox))
	hitbox.body_exited.connect(_on_hitbox_body_exited.bind(hitbox))

func remove_hitbox(hitbox: Area3D) -> void:
	if hitbox in hitboxes:
		hitboxes.erase(hitbox)
		hitbox.body_entered.disconnect(_on_hitbox_body_entered.bind(hitbox))
		hitbox.body_exited.disconnect(_on_hitbox_body_exited.bind(hitbox)) 