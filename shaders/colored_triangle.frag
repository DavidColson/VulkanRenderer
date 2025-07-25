#version 450

//shader input
layout (location = 0) in vec3 inColor;
layout (location = 1) in vec2 inUV;

//output write
layout (location = 0) out vec4 outFragColor;

// texture
layout(set=1, binding=0) uniform texture2D texturePool[];
layout(set=0, binding=0) uniform texture2D crateTexture;
layout(set=0, binding=1) uniform sampler linearSampler;

void main() 
{
	//return red
	// outFragColor = vec4(inColor,1.0f);
	outFragColor = texture(sampler2D(texturePool[0], linearSampler), inUV);
}
