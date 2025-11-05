shader_type canvas_item;

uniform vec2 center = vec2(0.5, 0.5);
uniform float max_radius = 0.5;
uniform vec4 circle_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
uniform float edge_softness : hint_range(0.0, 1.0, 0.01) = 0.1;

void fragment() {
    vec2 uv = UV;
    vec2 diff = uv - center;
    float dist = length(diff);

    if (dist < max_radius) {
        float normalized_dist = dist / max_radius;
        float softness_start = max(0.0, 1.0 - edge_softness);
        float alpha = circle_color.a * (1.0 - smoothstep(softness_start, 1.0, normalized_dist));
        COLOR = vec4(circle_color.rgb, alpha);
    } else {
        COLOR = vec4(0.0);
    }
}