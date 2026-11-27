#version 450

layout(set = 2, binding = 0) uniform sampler2D image;
layout(set = 2, binding = 1) uniform sampler2D mask;
layout(std140, set = 3, binding = 0) uniform Tint { vec4 color; } tint;
layout(std140, set = 3, binding = 1) uniform Add { vec4 color; } add;
layout(location = 0) in vec4 vertex_color;
layout(location = 1) in vec2 uv;
layout(location = 0) out vec4 color;

void main() {
    color = texture(image, uv) * texture(mask, uv) * vertex_color * tint.color + add.color;
}
