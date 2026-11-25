#version 450

// Match Spectrum.band_count. Instance zero draws the title.
const int band_count = 32;

layout (set = 1, binding = 0, std140) uniform View {
    vec4 label; // Left, top, width, height in window fractions.
    vec4 bands[band_count / 4];
} view;

layout (location = 0) out vec2 uv;
layout (location = 1) out vec3 color;
layout (location = 2) flat out int is_label;

const vec2 corners[6] = vec2[6](
    vec2(0, 0), vec2(0, 1), vec2(1, 0),
    vec2(1, 0), vec2(0, 1), vec2(1, 1)
);

void main() {
    uv = corners[gl_VertexIndex];
    vec2 position;
    if (gl_InstanceIndex == 0) {
        is_label = 1;
        position = view.label.xy + uv * view.label.zw;
        color = vec3(0.94, 0.96, 1.0);
    } else {
        is_label = 0;
        int band = gl_InstanceIndex - 1;
        float level = view.bands[band / 4][band % 4];
        float step_width = 0.84 / float(band_count);
        float height = 0.006 + 0.53 * level;
        position.x = 0.08 + step_width * (float(band) + 0.14 + 0.72 * uv.x);
        position.y = 0.86 - height * (1.0 - uv.y);
        float fraction = float(band) / float(band_count - 1);
        color = mix(vec3(0.08, 0.80, 1.0), vec3(1.0, 0.28, 0.63), fraction);
        color *= (0.2 + 0.8 * level) * (1.0 - 0.35 * uv.y);
    }
    gl_Position = vec4(position * vec2(2, -2) + vec2(-1, 1), 0, 1);
}
