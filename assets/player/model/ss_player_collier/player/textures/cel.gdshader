shader_type spatial;

group_uniforms Diffuse;
uniform sampler2D diffuse_texture : source_color, filter_linear_mipmap;
uniform bool enable_part_color;
uniform float part_color_threshold : hint_range(0.0, 1.0) = 0.5;
uniform vec3 part_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 overlay_color : source_color = vec3(1.0, 1.0, 1.0);
uniform sampler2D lightwarp : source_color, filter_linear, repeat_disable;

group_uniforms Normal;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform float normal_strength : hint_range(0.0, 16.0) = 1.0;

group_uniforms Phong;
uniform sampler2D phong_texture : source_color, filter_linear_mipmap;
uniform sampler2D phong_exponent_texture : source_color, filter_linear_mipmap;
uniform float phong : hint_range(0.0, 1.0) = .25;
uniform float phong_exponent : hint_range(0.0, 1.0) = .25;

group_uniforms Rim;
uniform bool enable_rim_lighting=true;
uniform float rim_strength : hint_range(0.0, 1.0) = .5;
uniform float rim_spread : hint_range(1.0, 8.0) = 6.0;


float fresnel(float amount, vec3 normal, vec3 view)
{
	return pow((1.0-clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}


void fragment() {
	switch (int(enable_part_color)) {
		case 1:
			if (texture(diffuse_texture, UV).a > part_color_threshold) {
				ALBEDO = texture(diffuse_texture, UV).rgb * overlay_color;
			}
			else{
				ALBEDO = (texture(diffuse_texture, UV).rgb * part_color)*overlay_color;
			}
			break;

		case 0:
			ALBEDO = ALBEDO = texture(diffuse_texture, UV).rgb * overlay_color;;
			break;

	}

	ROUGHNESS = 0.5;
	SPECULAR = 0.0;
	METALLIC = 0.0;
	switch (int(enable_rim_lighting)){
		case 1:
			ALBEDO += fresnel(rim_spread, VIEW, NORMAL) * rim_strength;
		case 0:
			break;
	}

	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}


void light() {
	float wrap = 0.5;

	// DIFFUSE
	float NdotL = clamp( dot(NORMAL, LIGHT), 0.0, 1.0);
	float wrapped = pow(NdotL * wrap + (1.0-wrap), 2.0);
	vec4 lw = texture(lightwarp, vec2(wrapped, 0.0));
	DIFFUSE_LIGHT += lw.rgb *  LIGHT_COLOR * ATTENUATION;


	// PHONG
	if (phong_exponent > 0.0) {
		float _phong_mask_tex = texture(phong_texture, UV).w;
		float _phong_exponent_tex = texture(phong_exponent_texture, UV).w;
		float _phong_strength = (_phong_mask_tex * phong);
		float _phong_exponent = (phong_exponent * _phong_exponent_tex);

		vec3 halfdir = normalize(VIEW+LIGHT);
		float NdotV = clamp( dot(NORMAL, halfdir), 0.0, 1.0);
		float _p = pow(NdotV, 256.0 * _phong_exponent) * _phong_exponent * _phong_strength * 0.1;
		SPECULAR_LIGHT += (_p * LIGHT_COLOR * ATTENUATION);
	}
}