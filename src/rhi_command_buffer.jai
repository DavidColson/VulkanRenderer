
#if GFX_BACKEND == .VULKAN {
	#load "vulkan/vulkan_command_buffer.jai";
}

// generic, probably can be shared somewhere?
Rect :: struct {
	x: s32;
	y: s32;
	width: s32;
	height: s32;
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
