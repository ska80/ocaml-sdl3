#version 450
layout(location = 0) in vec2 ring_vertex;
layout(location = 0) out vec2 wall;

layout(std140, set = 1, binding = 0) uniform Frame {
    vec4 view;    // time, aspect ratio, horizontal and vertical aim
    vec4 effect;  // pulse depth, ring count, unused, unused
} frame;

const float TAU = 6.28318530718;

void main() {
    // Draw the far rings first. Share the edge positions of adjacent rings.
    float layer = (float(gl_InstanceIndex) + ring_vertex.y) / frame.effect.y;
    float depth = 64.0 * pow(0.65 / 64.0, layer);
    float bend = log(1.0 + depth);
    float t = frame.view.x;
    float turn = TAU * fract(ring_vertex.x);
    float twist = 0.45 * sin(1.6 * bend - 0.85 * t) + 0.22 * bend;
    float radius = 3.25 + 0.22 * cos(6.0 * turn + 2.5 * bend)
                       + 0.21 * sin(4.0 * bend - 0.7 * t);
    vec2 spine = vec2(0.75 * sin(1.75 * bend + 0.37 * t),
                      0.55 * cos(1.50 * bend - 0.48 * t));
    spine *= 1.0 - exp(-0.2 * depth);
    vec2 p = spine + radius * vec2(cos(turn + twist), sin(turn + twist));

    // SDL uses a clip-space depth from 0 to w. The tunnel starts past the
    // near plane and ends before the far plane.
    vec2 screen = (1.45 * p) / vec2(frame.view.y, 1.0);
    screen += 0.44 * frame.view.zw * depth;
    float clip_z = (depth - 0.4) * (80.0 / (80.0 - 0.4));
    gl_Position = vec4(screen, clip_z, depth);
    wall = vec2(ring_vertex.x, depth);
}
