extends Node

# Scroll the UV offset along the X axis for an infinite scrolling effect.
export (float) var scroll_speed = 0.25
var _uv_offset = 0.0

func _process(delta):
	# Advance the offset and wrap around at 1.0 for seamless looping
	_uv_offset = fmod(_uv_offset + delta * scroll_speed, 1.0)

	# Attempt to find a ShaderMaterial on the DrawCall node (surface materials or overrides)
	var material = null
	# Prefer the first surface material if this is a MeshInstance-like node
	if has_method("get_surface_material"):
		material = get_surface_material(0)
	# Fallback to material_override if present
	if material == null and has_property("material_override"):
		material = self.material_override

	# If we found a shader material, push the offset to the shader
	if material != null and material is ShaderMaterial:
		# The shader should define a vec2 uniform named uv_offset
		material.set_shader_param("uv_offset", Vector2(_uv_offset, 0.0))
