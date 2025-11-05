shader_type spatial;
render_mode unshaded;

uniform sampler2D sky_texture : source_color;
uniform vec4 ground_color : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform float horizon_fade : hint_range(0.0, 1.0) = 0.5;
uniform float horizon_height : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // Get the view direction in world space
    vec3 view_dir = normalize(VIEW);

    // Calculate the vertical position (y component) of the view direction
    float vertical_pos = view_dir.y;

    // Calculate the UV coordinates for the sky texture
    // We use the x and z components of the view direction to map to the sky texture
    vec2 sky_uv = vec2(
        atan(view_dir.x, view_dir.z) / (2.0 * PI) + 0.5,
        asin(view_dir.y) / PI + 0.5
    );

    // Sample the sky texture
    vec4 sky_color = texture(sky_texture, sky_uv);

    // Calculate the fade factor based on the vertical position
    float fade_factor = smoothstep(horizon_height - horizon_fade, horizon_height + horizon_fade, vertical_pos);

    // Mix between ground color and sky color based on the fade factor
    ALBEDO = mix(ground_color.rgb, sky_color.rgb, fade_factor);
}