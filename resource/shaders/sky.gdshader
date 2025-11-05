shader_type spatial;
render_mode unshaded;

uniform sampler2D sky_texture : source_color;
uniform vec4 ground_color : source_color = vec4(1.0, 0.0, 0.0, 1.0); // Bright red for testing
uniform float horizon_fade : hint_range(0.0, 1.0) = 0.5;
uniform float horizon_height : hint_range(0.0, 1.0) = 0.5;

void fragment() {
    // Get the fragment's position in world space
    vec3 world_pos = WORLD_MATRIX[3].xyz;

    // Get the direction from fragment to camera
    vec3 view_dir = normalize(CAMERA_MATRIX[3].xyz - world_pos);

    // Debug: Show basic color based on view direction
    ALBEDO = vec3(
        (view_dir.x + 1.0) * 0.5,
        (view_dir.y + 1.0) * 0.5,
        (view_dir.z + 1.0) * 0.5
    );

    // If we see colors above, we can uncomment the rest
    /*
    // Calculate UV coordinates
    vec2 sky_uv = vec2(
        atan(view_dir.x, view_dir.z) / (2.0 * PI) + 0.5,
        asin(view_dir.y) / PI + 0.5
    );

    // Sample sky texture
    vec4 sky_color = texture(sky_texture, sky_uv);

    // Calculate fade
    float fade_factor = smoothstep(horizon_height - horizon_fade, horizon_height + horizon_fade, view_dir.y);

    // Mix colors
    ALBEDO = mix(ground_color.rgb, sky_color.rgb, fade_factor);
    */
}