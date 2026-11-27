#version 450

layout(location = 0) in vec2 position;

void main() {
    vec2 pixels = position + vec2(8.0, -12.0);
    gl_Position = vec4(vec2(-1.0, 1.0) + pixels * vec2(2.0 / 192.0, 2.0 / 160.0), 0.0, 1.0);
}
