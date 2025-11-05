extends Label

var body: Node = null

func _ready():
	# Find the Body node in the scene tree
	body = get_node_or_null("../../../../Body")
	if not body:
		text = "x"
	else:
		text = "--"

func _process(delta):
	if not body:
		return
	var velocity = body.velocity if body.has_method("velocity") else body.get("velocity")
	var h_vel = Vector2(velocity.x, velocity.z)
	var speed_mps = round(h_vel.length())
	var speed_ups = int(h_vel.length() * 39.37)
	text = "%s" % [speed_ups]
