
#if GFX_BACKEND == .VULKAN {
	#load "vulkan/vulkan_command_buffer.jai";
}

// generic, probably can be shared somewhere?
Rect :: struct {
	x: s32 = 0;
	y: s32 = 0;
	width: s32 = 0;
	height: s32 = 0;
}

Viewport :: struct {
	x: float;
	y: float;
	width: float;
	height: float;
	minDepth: float;
	maxDepth: float;
}

RenderAttachmentLoadOp :: enum {
	LOAD;
	CLEAR;
	DONTCARE;
}

RenderAttachmentStoreOp :: enum {
	STORE;
	DONTCARE;
}

BindPoint :: enum {
	GRAPHICS;
	COMPUTE;
}

ClearValue :: union {
	depth: float;
	color: Vector4;
}

RenderAttachment :: struct {
	image: Texture;
	loadOp: RenderAttachmentLoadOp;
	storeOp: RenderAttachmentStoreOp;
	clear: ClearValue;
}

RenderingInfo :: struct {
	renderArea: Rect;
	colorAttachments: []RenderAttachment;
	depthAttachment: RenderAttachment;
}

TextureBarrier :: struct {
	texture: Texture;
	prevUsage: TextureUsage;
	nextUsage: TextureUsage;
}

CopyImageInfo :: struct {
	src: Texture;
	dst: Texture;
	srcRect: Rect;
	dstRect: Rect;
}

CopyBufferInfo :: struct {
	src: Buffer;
	dst: Buffer;
	size: s64 = 0;
	srcOffset: s64 = 0;
	dstOffset: s64 = 0;
}
