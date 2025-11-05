extends Control

@onready var charge1: TextureRect = $Charge1
@onready var charge2: TextureRect = $Charge2
@onready var charge3: TextureRect = $Charge3

var charges: Array[TextureRect] = []

@export_group("Charge Colors")
@export var active_color: Color = Color(0.2, 0.8, 0.2, 1.0)  # Green
@export var inactive_color: Color = Color(0.2, 0.2, 0.2, 0.5)  # Dark gray, semi-transparent

@export_group("Charge Appearance")
@export var charge_size: Vector2 = Vector2(40, 40)
@export var charge_spacing: int = 5
@export var charge_corner_radius: float = 4.0

func _ready():
	# Wait for the next frame to ensure all nodes are ready
	await get_tree().process_frame
	
	# Initialize charges array
	charges = [charge1, charge2, charge3]
	
	# Verify all charges are valid
	for charge in charges:
		if not is_instance_valid(charge):
			push_error("Charge indicator: Invalid charge reference")
			return
	
	# Apply initial properties
	apply_charge_properties()
	update_charges(3)  # Start with full charges

func apply_charge_properties():
	if charges.is_empty():
		return
		
	for charge in charges:
		if is_instance_valid(charge):
			charge.custom_minimum_size = charge_size

func update_charges(current_charges: int):
	if charges.is_empty():
		return
		
	# Ensure current_charges is within valid range
	current_charges = clamp(current_charges, 0, charges.size())
	
	for i in range(charges.size()):
		if is_instance_valid(charges[i]):
			charges[i].modulate = active_color if i < current_charges else inactive_color
