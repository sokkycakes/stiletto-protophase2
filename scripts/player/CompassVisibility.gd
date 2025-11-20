extends MeshInstance3D

const LOCAL_ONLY_LAYER := 1 << 5
const DEFAULT_LAYER := 1 << 1

func _ready() -> void:
	var camera := get_parent() as Camera3D
	var networked_player := _find_parent_networked_player()
	var is_local := false
	if networked_player and networked_player.has_method("is_local_player"):
		is_local = networked_player.is_local_player()
	
	if is_local:
		_set_layers_for_mesh(self, LOCAL_ONLY_LAYER)
		if camera:
			camera.cull_mask &= ~LOCAL_ONLY_LAYER
	else:
		_set_layers_for_mesh(self, DEFAULT_LAYER)

func _set_layers_for_mesh(root: MeshInstance3D, layer_mask: int) -> void:
	root.layers = layer_mask
	for child in root.get_children():
		if child is MeshInstance3D:
			child.layers = layer_mask

func _find_parent_networked_player() -> Node3D:
	var node: Node = self
	while node:
		if node is NetworkedPlayer:
			return node
		node = node.get_parent()
	return null
