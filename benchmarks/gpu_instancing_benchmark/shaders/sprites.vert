#version 450

layout(location = 0) in vec2 corner;
layout(location = 1) in vec2 initial_position;
layout(location = 2) in vec2 atlas_origin;

layout(std140, set = 1, binding = 0) uniform Frame {
    vec4 scales;
    vec4 motion;
} frame;

layout(location = 0) out vec2 uv;

void main() {
    vec2 position = mod(initial_position + frame.motion.xy, frame.motion.zw);
    vec2 clip = vec2(-1.0, 1.0) + (position + corner) * frame.scales.xy;
    gl_Position = vec4(clip, 0.0, 1.0);
    uv = (atlas_origin + corner) * frame.scales.zw;
}
