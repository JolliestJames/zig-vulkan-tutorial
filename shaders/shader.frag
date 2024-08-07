#version 450

layout(location = 0) in vec3 fragColor;
layout(location = 1) in vec2 fragTextureXY;

layout(location = 0) out vec4 outColor;

layout(binding = 1) uniform sampler2D textureSampler;

void main() {
    outColor = vec4(fragColor * texture(textureSampler, fragTextureXY).rgb, 1.0);
}
