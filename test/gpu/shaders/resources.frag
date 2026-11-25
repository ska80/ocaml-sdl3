#version 450

layout(set = 2, binding = 0) uniform sampler2D first_texture;
layout(set = 2, binding = 1) uniform sampler2D second_texture;
layout(std140, set = 3, binding = 0) uniform Fragment_data {
    vec4 coordinates;
} fragment_data;
layout(location = 0) flat in float red;
layout(location = 0) out vec4 color;

void main() {
    float green = texture(first_texture, fragment_data.coordinates.xy).r;
    float blue = texture(second_texture, fragment_data.coordinates.zw).r;
    color = vec4(red, green, blue, 1.0);
}
