
// common types and functions can go in here
// also documentation

#if GFX_BACKEND == .VULKAN {
    #load "vulkan/vulkan_device.jai";
}

ShaderStage :: enum {
	VERTEX;
	PIXEL;
	COMPUTE;
	NUM_STAGES;
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
	UNDEFINED;
	RGBA8;
	RGBA16F;
	DEPTH;
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

PipelineDesc :: struct {
	layouts: []BindGroupLayout;
	vertexShader: Shader;
	fragmentShader: Shader;
	topology: Topology;
	rasterizer: RasterizerDesc;
	colorTargetCount: s32;
	colorTargets: []ColorTarget;
	depthTargetFormat: PixelFormat;
	depth: DepthStencil;
	pushConstants: []PushConstantDesc;
}

BindingType :: enum {
    SAMPLER;
    SAMPLED_IMAGE;
    STORAGE_IMAGE;
    UNIFORM_BUFFER;
    STORAGE_BUFFER;
	NUM_BINDING_TYPES;
}

Binding :: struct {
	slot: s32;
	type: BindingType;
	shaderStage: ShaderStage;
}

BindGroupLayoutDesc :: struct {
	bindings: []Binding;
}

ResourceBind :: struct {
	slot: s32;
	texture: Texture;
	buffer: Buffer;
	sampler: Sampler;
}

BindGroupDesc :: struct {
	layout: BindGroupLayout;
	temp: bool = false;
	resources: []ResourceBind;
}

PushConstantDesc :: struct {
	stage: ShaderStage;
	size: s32;
	offset: s32;
}

SamplerDesc :: struct {
	// @todo: options!!
	magFilter: VkFilter;
	minFilter: VkFilter;
}

TextureSize :: struct {
	width: s32;
	height: s32;
	depth: s32;
}

TextureUsageFlags :: enum_flags {
    COPY_SRC       :: 0x1;
    COPY_DST       :: 0x2;
    READ_ONLY      :: 0x4;
    READ_AND_WRITE :: 0x8;
    COLOR_TARGET   :: 0x10;
    DEPTH_TARGET   :: 0x20;
}

TextureDesc :: struct {
	format: PixelFormat;
	size: TextureSize;
	usage: TextureUsageFlags;
	data: *void;
}

BufferUsageFlags :: enum_flags {
    COPY_SRC              :: 0x1;
    COPY_DST              :: 0x2;
    READ_ONLY             :: 0x4;
    READ_AND_WRITE        :: 0x8;
    INDEX_BUFFER          :: 0x10;
    VERTEX_BUFFER         :: 0x20;
	SHADER_DEVICE_ADDRESS :: 0x40;
}

MemoryUsageFlags :: enum {
    GPU_ONLY;
    CPU_ONLY;
    CPU_TO_GPU;
    GPU_TO_CPU;
}

BufferDesc :: struct {
	size: s32;
	usage: BufferUsageFlags;
	memory: MemoryUsageFlags;
}
