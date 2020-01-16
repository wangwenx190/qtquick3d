#version 440

layout(location = 0) in vec3 attr_pos;

layout(location = 0) out vec2 uv_coords;

layout(std140, binding = 0) uniform buf {
    vec2 cameraProperties;
} ubuf;

out gl_PerVertex { vec4 gl_Position; };

void main()
{
    gl_Position = vec4(attr_pos, 1.0);
    uv_coords.xy = attr_pos.xy;
}
