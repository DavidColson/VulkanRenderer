
// common types and functions can go in here
// also documentation

#if GFX_BACKEND == .VULKAN {
    #load "vulkan/vulkan_device.jai";
}

Topology :: enum {
    POINT_LIST;
    LINE_LIST;
    LINE_STRIP;
    TRIANGLE_LIST;
    TRIANGLE_STRIP;
    TRIANGLE_FAN;
}

PolygonMode :: enum {
    FILL;
    LINE;
    POINT;
}

CullMode :: enum {
    NONE;
    FRONT;
    BACK;
    FRONT_AND_BACK;
}

FrontFace :: enum {
    COUNTER_CLOCKWISE;
    CLOCKWISE;
}

RasterizerDesc :: struct {
	polygonMode: PolygonMode = .FILL;
	cullMode: CullMode = .FRONT_AND_BACK;
	frontFace: FrontFace = .COUNTER_CLOCKWISE;
}

PixelFormat :: enum {
	// create formats as needed
	R8G8B8A8_UNORM;
	R16G16B16A16_SFLOAT;
	D32_SFLOAT;
}

ColorComponentFlags :: enum_flags {
    R :: 0x1;
    G :: 0x2;
    B :: 0x4;
    A :: 0x8;
}
ColorTarget :: struct {
	format: PixelFormat;
	colorWriteMask: ColorComponentFlags = .R | .G | .B | .A;
}

CompareOp :: enum {
    NEVER;
    LESS;
    EQUAL;
    LESS_OR_EQUAL;
    GREATER;
    NOT_EQUAL;
    GREATER_OR_EQUAL;
    ALWAYS;
}

DepthStencil :: struct {
	depthWriteEnabled: bool = false;
	depthTestEnabled: bool = false;
	stencilTestEnabled: bool = false;
	compareOp: CompareOp = .NEVER;
}

MAX_COLOR_TARGETS :: 8;
PipelineCreateOptions :: struct {
	// @todo: temporary before we have bindless, ideally no vk specific stuff in here
	vkLayout: VkPipelineLayout;
	vertexShader: Shader;
	fragmentShader: Shader;
	topology: Topology;
	rasterizer: RasterizerDesc;
	colorTargetCount: s32;
	colorTargets: [MAX_COLOR_TARGETS]ColorTarget;
	depthTargetFormat: PixelFormat;
	depth: DepthStencil;
}

