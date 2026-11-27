#version 450

layout(set = 0, binding = 0) uniform sampler2D vertex_texture;
layout(std140, set = 1, binding = 0) uniform Vertex_data {
    vec4 coordinates;
} vertex_data;
layout(location = 0) flat out float red;

const vec2 points[3] = vec2[3](vec2(-1.0, -1.0), vec2(3.0, -1.0), vec2(-1.0, 3.0));

void main() {
    gl_Position = vec4(points[gl_VertexIndex], 0.0, 1.0);
    red = textureLod(vertex_texture, vertex_data.coordinates.xy, vertex_data.coordinates.z).r;
}
