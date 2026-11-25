#version 450

layout (set = 2, binding = 0) uniform sampler2D label_texture;

layout (location = 0) in vec2 uv;
layout (location = 1) in vec3 color;
layout (location = 2) flat in int is_label;
layout (location = 0) out vec4 pixel;

void main() {
    // The title rectangle has black behind it, so it needs no blending.
    float coverage = is_label != 0 ? texture(label_texture, uv).a : 1.0;
    pixel = vec4(color * coverage, 1.0);
}
