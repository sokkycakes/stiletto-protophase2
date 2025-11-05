shader_type sky;

// Based on "A Practical Analytic Model for Daylight" (Preetham et al.)
// Adapted for cube-sphere mapping so the sky can be baked to a seamless
// 6-sided cubemap instead of a lat-long sphere. Only the sampling logic
// for cover/auxiliary textures changes – the luminance model is
// untouched.

// ------------------------------
// Uniforms (identical to the built-in procedural sky)
// ------------------------------

uniform vec4 sky_top_color : source_color;
uniform vec4 sky_horizon_color : source_color;
uniform float sky_curve : hint_range(0.0, 1.0, 0.001) = 0.09;
uniform float sky_energy : hint_range(0.0, 16.0, 0.001) = 1.0;

uniform vec4 ground_bottom_color : source_color;
uniform vec4 ground_horizon_color : source_color;
uniform float ground_curve : hint_range(0.0, 1.0, 0.001) = 0.02;
uniform float ground_energy : hint_range(0.0, 16.0, 0.001) = 1.0;

uniform float sun_angle_max : hint_range(0.0, 180.0, 0.1) = 90.0;
uniform float sun_curve : hint_range(0.0, 1.0, 0.001) = 0.05;

uniform sampler2D sky_cover_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 sky_cover_modulate : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// ------------------------------
// Cube-sphere helper
// ------------------------------

int get_cube_face(vec3 dir) {
	vec3 a = abs(dir);
	float m = max(max(a.x, a.y), a.z);
	if (m == a.x) return dir.x > 0.0 ? 0 : 1;
	if (m == a.y) return dir.y > 0.0 ? 2 : 3;
	return dir.z > 0.0 ? 4 : 5;
}

vec2 direction_to_uv(vec3 dir, int face) {
	vec3 a = abs(dir);
	float m = max(max(a.x, a.y), a.z);
	vec2 uv;
	if (face == 0)      uv = vec2(-dir.z,  dir.y) / m; // +X
	else if (face == 1) uv = vec2( dir.z,  dir.y) / m; // -X
	else if (face == 2) uv = vec2( dir.x, -dir.z) / m; // +Y
	else if (face == 3) uv = vec2( dir.x,  dir.z) / m; // -Y
	else if (face == 4) uv = vec2( dir.x,  dir.y) / m; // +Z
	else                uv = vec2(-dir.x,  dir.y) / m; // -Z
	return uv * 0.5 + 0.5; // map from [-1,1] to [0,1]
}

// ------------------------------
// Constants taken from the engine implementation
// ------------------------------

const float LUMINANCE_COEFFICIENT = 1000.0;
const float ATMOSPHERE_THICKNESS = 1.0;
const float SKY_POWER = 2.5;

// Perez / Preetham sky luminance helper (verbatim)
vec3 get_sky_color(vec3 ray_dir, vec3 sun_dir, vec3 turbidity, float sun_disk_scale) {
	float cos_theta = clamp(ray_dir.y, 0.0, 1.0);
	float theta = acos(cos_theta);

	float cos_gamma = clamp(dot(ray_dir, sun_dir), 0.0, 1.0);
	float gamma = acos(cos_gamma);

	float cos_sun_theta = clamp(sun_dir.y, 0.0, 1.0);
	float sun_theta = acos(cos_sun_theta);

	float m = 1.0 / (cos_theta + 0.15 * pow(93.885 - (theta * 180.0 / PI), -1.253));

	vec3 Y_z = vec3(
		(4.0453 * turbidity.r - 4.9710) * tan(sun_theta) + 0.2155 * turbidity.r - 0.2675,
		(4.0453 * turbidity.g - 4.9710) * tan(sun_theta) + 0.2155 * turbidity.g - 0.2675,
		(4.0453 * turbidity.b - 4.9710) * tan(sun_theta) + 0.2155 * turbidity.b - 0.2675
	);
	Y_z *= (1.0 + 1.0 * exp(-sun_theta / (PI * 0.5)));
	Y_z = max(Y_z, vec3(0.0));

	vec3 A = vec3(0.1787) * turbidity - vec3(1.4630);
	vec3 B = vec3(-0.3554) * turbidity + vec3(0.4278);
	vec3 C = vec3(-0.0227) * turbidity + vec3(5.3251);
	vec3 D = vec3(0.1206) * turbidity - vec3(2.5771);
	vec3 E_coeff = vec3(-0.0670) * turbidity + vec3(0.3703);

	vec3 perez = (vec3(1.0) + A * exp(B / cos_theta)) * (vec3(1.0) + C * exp(D * gamma) + E_coeff * pow(cos_gamma, 2.0));

	float sun_disk = smoothstep(sun_disk_scale, sun_disk_scale + 0.0001, cos_gamma);
	vec3 sun = sun_disk * perez * Y_z;

	return sun;
}

// ------------------------------
// Main sky() function (unchanged apart from cube-sphere sampling)
// ------------------------------

void sky() {
	vec3 ray_dir = normalize(EYEDIR);
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);

	float y_interp = pow(max(0.0, ray_dir.y), sky_curve);
	vec3 sky = mix(sky_horizon_color.rgb, sky_top_color.rgb, y_interp);
	sky *= sky_energy;

	float sun_fade = pow(max(0.0, dot(ray_dir, sun_dir)), sun_curve);
	float sun_amount = smoothstep(cos(sun_angle_max * PI / 180.0), 1.0, dot(ray_dir, sun_dir));
	sky = mix(sky, sky_top_color.rgb * sky_energy, sun_fade * sun_amount);

	if (sun_dir.y > 0.0) {
		vec3 turbidity = vec3(pow(sky_top_color.r, SKY_POWER), pow(sky_top_color.g, SKY_POWER), pow(sky_top_color.b, SKY_POWER)) * 20.0;
		vec3 perez = get_sky_color(ray_dir, sun_dir, turbidity, 0.999);
		sky += perez * LUMINANCE_COEFFICIENT;
	}

	float ground_y_interp = pow(max(0.0, -ray_dir.y), ground_curve);
	vec3 ground = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, ground_y_interp);
	ground *= ground_energy;

	vec3 final_color = mix(sky, ground, step(0.0, -ray_dir.y));

	// Cube-sphere UV for cover texture (avoids polar seam)
	int face = get_cube_face(ray_dir);
	vec2 sky_cover_uv = direction_to_uv(ray_dir, face);
	vec4 sky_cover = texture(sky_cover_texture, sky_cover_uv);

	final_color = mix(final_color, sky_cover.rgb, sky_cover.a * sky_cover_modulate.a) * sky_cover_modulate.rgb;

	COLOR = final_color;
}