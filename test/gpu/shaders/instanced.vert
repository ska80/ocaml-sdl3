#version 450

layout(location = 0) in vec2 position;
layout(location = 1) in vec4 vertex_tint;
layout(location = 2) in float shift;
layout(location = 3) in vec4 instance_tint;
layout(location = 0) out vec4 vertex_color;

void main() {
    gl_Position = vec4(position + vec2(shift, 0.0), 0.0, 1.0);
    vertex_color = vertex_tint * instance_tint;
}
