#version 450
layout(location = 0) in vec2 wall;
layout(location = 0) out vec4 color;
layout(set = 2, binding = 0) uniform sampler2D gradient;

layout(std140, set = 3, binding = 0) uniform Frame {
    vec4 view;    // time, aspect ratio, horizontal and vertical aim
    vec4 effect;  // pulse depth, ring count, unused, unused
} frame;

const float TAU = 6.28318530718;
const vec3 DARK = vec3(4.0, 7.0, 18.0) / 255.0;

float away(float phase) {
    return abs(fract(phase + 0.5) - 0.5);
}

// Soften narrow lines when their phase changes by more than a pixel.
float line(float phase, float width) {
    float pixel = max(fwidth(phase), 0.001);
    return (1.0 - smoothstep(width, width + pixel, away(phase))) *
           (width / (width + 0.33 * pixel));
}

void main() {
    float t = frame.view.x;
    float z = wall.y;
    float advance = z + t * 5.5;
    float ribs = 18.0 * wall.x + 0.28 * sin(0.28 * z - 0.9 * t);
    float panels = 0.48 * advance;
    float braid = 2.0 * wall.x - 0.087 * advance;
    float ribbon = exp(-9.0 * away(braid));

    float grid = line(ribs, 0.028) * 0.72 + line(panels, 0.026) * 0.52;
    float braids = line(braid, 0.019) * 0.64 + line(braid + 0.065, 0.011) * 0.35;
    float trace = line(panels + 0.32, 0.035) *
                  (1.0 - smoothstep(0.18, 0.32, away(ribs - 0.5)));
    float column = mod(floor(ribs), 18.0);
    float flicker = 0.5 + 0.5 * sin(TAU * (0.17 * floor(panels) - 0.075 * column));
    float glow = 0.10 * exp(-10.0 * away(ribs)) + 0.11 * exp(-12.0 * away(panels));

    float hue = fract(wall.x + 0.016 * z + 0.055 * sin(t * 0.5 + z * 0.17));
    vec3 tint = texture(gradient, vec2(hue, 0.5)).rgb;
    vec3 hot = mix(tint, vec3(0.77, 0.91, 1.0), 0.64);
    float pulse = exp(-1.4 * abs(z - frame.effect.x));
    float wake = step(z, frame.effect.x) * exp(-0.16 * abs(z - frame.effect.x));

    vec3 light = tint * (0.045 + glow + 0.24 * ribbon + trace * (0.12 + 0.23 * flicker));
    light += hot * (grid * (0.36 + 0.53 * ribbon + 0.55 * wake) + braids);
    light += hot * pulse * (0.23 + 0.63 * line(ribs, 0.10));
    float fade = exp(-0.032 * z) * (1.0 - smoothstep(47.0, 64.0, z));
    color = vec4(DARK + light * fade, 1.0);
}
