#version 450

layout(set = 2, binding = 0) uniform sampler2D mask;
layout(location = 0) in vec4 vertex_color;
layout(location = 0) out vec4 color;

void main() {
    color = texture(mask, vec2(0.5)) * vertex_color;
}
