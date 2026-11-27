#version 450

layout(set = 2, binding = 0) uniform sampler2D atlas;
layout(std140, set = 3, binding = 0) uniform Style {
    vec4 tint;
    vec4 image_type;
} style;
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 color;

void main() {
    vec4 glyph = texture(atlas, uv);
    if (style.image_type.x == 1.0) {
        // Color glyphs already contain premultiplied RGB.
        color = glyph * style.tint.a;
    } else {
        float coverage = glyph.a;
        if (style.image_type.x == 2.0) {
            coverage = smoothstep(0.44, 0.56, coverage);
        }
        float opacity = coverage * style.tint.a;
        color = vec4(style.tint.rgb * opacity, opacity);
    }
}
