
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
	debugName: string;
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

ComputePipelineDesc :: struct {
	debugName: string;
	layouts: []BindGroupLayout;
	pushConstants: []PushConstantDesc;
	shader: Shader;
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
	debugName: string;
	bindings: []Binding;
}

ResourceBind :: struct {
	slot: s32;
	texture: Texture;
	buffer: Buffer;
	sampler: Sampler;
}

BindGroupDesc :: struct {
	debugName: string;
	layout: BindGroupLayout;
	temp: bool = false;
	resources: []ResourceBind;
}

PushConstantDesc :: struct {
	stage: ShaderStage;
	size: s32;
	offset: s32;
}

// Bindless stuff

BindlessResourceSlot :: struct {
	type: BindingType;
	count: s32;
}

BindlessPoolDesc :: struct {
	debugName: string;
	resourceTypes: []BindlessResourceSlot;
}

BindlessResource :: struct {
	slot: s32;
	index: s32;
	texture: Texture;
	buffer: Buffer;
}

BindlessPoolUpdateDesc :: struct {
	pool: BindlessPool;
	resources: []BindlessResource;
}

SamplerDesc :: struct {
	debugName: string;
	// @todo: options!!
	magFilter: VkFilter;
	minFilter: VkFilter;
}

TextureSize :: struct {
	width: s32;
	height: s32;
	depth: s32;
}

TextureUsage :: enum_flags {
	NONE;
	COPY_SRC;
	COPY_DST;

	READ_GEOMETRY;
	READ_PIXEL;
	READ_COMPUTE;

	READ_WRITE_GEOMETRY;
	READ_WRITE_PIXEL;
	READ_WRITE_COMPUTE;
	
	READ_RENDER_TARGET;
	WRITE_RENDER_TARGET;

	PRESENT;

	// derived
	READ_SHADER :: READ_GEOMETRY | READ_PIXEL | READ_COMPUTE;
	READ_WRITE_SHADER :: READ_WRITE_GEOMETRY | READ_WRITE_PIXEL | READ_WRITE_COMPUTE;

	READ_WRITE_RENDER_TARGET :: READ_RENDER_TARGET | WRITE_RENDER_TARGET;

	GEOMETRY_ALL :: READ_GEOMETRY | READ_WRITE_GEOMETRY;
	PIXEL_ALL :: READ_PIXEL | READ_WRITE_PIXEL;
	GRAPHICS_ALL :: GEOMETRY_ALL | PIXEL_ALL | READ_WRITE_RENDER_TARGET;
	COMPUTE_ALL :: READ_COMPUTE | READ_WRITE_COMPUTE;
	COPY_ALL :: COPY_SRC | COPY_DST;

	READ_ALL :: READ_SHADER | READ_RENDER_TARGET | COPY_SRC | PRESENT;
	WRITE_ALL :: READ_WRITE_SHADER | WRITE_RENDER_TARGET | COPY_DST;
	ALL :: READ_ALL | WRITE_ALL;
	SHADER_ALL :: READ_SHADER | READ_WRITE_SHADER;
}

TextureDesc :: struct {
	debugName: string;
	format: PixelFormat;
	size: TextureSize;
	usage: TextureUsage;
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
	debugName: string;
	size: s32;
	usage: BufferUsageFlags;
	memory: MemoryUsageFlags;
}
