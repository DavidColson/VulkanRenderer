
// Types
Device :: struct {
	window: *SDL_Window;
	width: s32;
	height: s32;

	instance: VkInstance;
	debugMessenger: VkDebugUtilsMessengerEXT;
	physicalDevice: VkPhysicalDevice;
	device: VkDevice;
	surface: VkSurfaceKHR;
	graphicsQueue: VkQueue;
	presentQueue: VkQueue;
	graphicsQueueFamily: int;
	presentQueueFamily: int;
	present_mode: VkPresentModeKHR;
	swapchain: VkSwapchainKHR;
	swapchainImageFormat: VkFormat;
	swapchainExtent: VkExtent2D;
	swapchainImages: [..] VkImage;
	swapchainImageViews: [..] VkImageView;

	// new descriptor management
	globalDescriptorPool: DescriptorPool;
	perFrameDescriptorPool: DescriptorPool;

	// old descriptor management
	globalDescriptorAllocator: DescriptorAllocator;
	drawImageDescriptors: VkDescriptorSet;
	drawImageDescriptorLayout: VkDescriptorSetLayout;

	imguiDescriptorPool: VkDescriptorPool;

	gradientPipeline: VkPipeline;
	gradientPipelineLayout: VkPipelineLayout;

	trianglePipeline: VkPipeline;
	trianglePipelineLayout: VkPipelineLayout;

	// @todo: move out of rhi to higher level rendering
	meshPipeline: Pipeline;
	cubeMesh: GpuMeshBuffers;
	crateTexture: Texture;
	linearSampler: Sampler;
	cubeMaterialBindGroup: BindGroup;
	cubeMaterialBindGroupLayout: BindGroupLayout;

	immediateFence: VkFence;
	immediateCommandBuffer: VkCommandBuffer;
	immediateCommandPool: VkCommandPool;

	gpuAllocator: VmaAllocator;

	drawImage: Texture;
	depthImage: Texture;
	drawExtent: VkExtent2D;
	frames: [..] FrameData;
	frame_number: int;

	pc: ComputePushConstants;
}

FrameData :: struct
{
	commandPool: VkCommandPool;
	mainCommandBuffer: VkCommandBuffer;
	swapchainSemaphore: VkSemaphore;
	renderSempahore: VkSemaphore;
	renderFence: VkFence;
}


ComputePushConstants :: struct {
	data1: Vector4;
	data2: Vector4;
	data3: Vector4;
	data4: Vector4;
}

Vertex :: struct {
	position: Vector3;
	uv_x: float;
	normal: Vector3;
	uv_y: float;
	color: Vector4;
}

GpuMeshBuffers :: struct {
	indexBuffer: Buffer;
	vertexBuffer: Buffer;
	deviceAddress: VkDeviceAddress;
}

GpuDrawPushConstants :: struct {
	worldMatrix: Matrix4;
	vertexBuffer: VkDeviceAddress;
}

// Resources

BindGroupLayout :: struct {
	platformHandle: VkDescriptorSetLayout = VK_NULL_HANDLE;
	bindings: []Binding;
}

BindGroup :: struct {
	platformHandle: VkDescriptorSet = VK_NULL_HANDLE;
	allocatedFrom: VkDescriptorPool;
	canBeFreed: bool;
}

Pipeline :: struct {
	platformHandle: VkPipeline = VK_NULL_HANDLE;
	pipelineLayout: VkPipelineLayout = VK_NULL_HANDLE;
}

Shader :: struct {
	platformHandle: VkShaderModule = VK_NULL_HANDLE;
}

Texture :: struct {
	imageFormat: PixelFormat;

	// backend specific handles
	image: VkImage = VK_NULL_HANDLE;
	imageView: VkImageView;
	allocation: VmaAllocation;
	imageExtent: VkExtent3D;
}

Sampler :: struct {
	platformHandle: VkSampler = VK_NULL_HANDLE;
}

Buffer :: struct {
	buffer: VkBuffer = VK_NULL_HANDLE;
	allocation: VmaAllocation;
	info: VmaAllocationInfo;
}

// rhi api

// core graphics initialization
rhi_device_init :: (s: *Device, window: *SDL_Window, width: s32, height: s32) {
	s.window = window;
	s.width = width;
	s.height = height;

	init_vulkan(s);
	init_swapchain(s);
	init_swapchain_image_views(s);
	init_commands(s);
	init_sync_structures(s);
	init_descriptors(s);
	init_pipelines(s);
	init_imgui(s);
	// init_triangle_pipeline(s);

	s.pc.data1 = Vector4.{1, 0, 0, 1};
	s.pc.data2 = Vector4.{0, 0, 1, 1};
}

rhi_device_get_current_frame :: (s: *Device) -> *FrameData
{
	return *s.frames[s.frame_number % s.frames.count];
}

// @todo: this should be a part of the command buffer functions
transition_image :: (cmd: VkCommandBuffer, image: VkImage, current_layout: VkImageLayout, new_layout: VkImageLayout) {
	image_barrier: VkImageMemoryBarrier2;
    image_barrier.srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    image_barrier.srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT ;
    image_barrier.dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
    image_barrier.dstAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT  | VK_ACCESS_2_MEMORY_READ_BIT;
    image_barrier.oldLayout = current_layout;
    image_barrier.newLayout = new_layout;

    aspect_mask: VkImageAspectFlags = ifx new_layout == .DEPTH_ATTACHMENT_OPTIMAL then .DEPTH_BIT else .COLOR_BIT;
    image_barrier.subresourceRange = image_subresource_range(aspect_mask);
    image_barrier.image = image;

    dep_info: VkDependencyInfo;
    dep_info.sType = .DEPENDENCY_INFO;
    dep_info.imageMemoryBarrierCount = 1;
    dep_info.pImageMemoryBarriers = *image_barrier;
    
    vkCmdPipelineBarrier2(cmd, *dep_info);
}

rhi_device_create_bind_group_layout :: (using s: *Device, opts: BindGroupLayoutDesc) -> BindGroupLayout {
	info: VkDescriptorSetLayoutCreateInfo;
	info.pNext = null;
	info.flags = 0;

	bindings : [..]VkDescriptorSetLayoutBinding;
	bindings.allocator = temp;
	for 0..opts.bindings.count-1 {
		newBind: VkDescriptorSetLayoutBinding;
		newBind.binding = xx opts.bindings[it].slot;
		newBind.descriptorCount = 1;
		newBind.descriptorType = binding_type_to_vk_descriptor_type(opts.bindings[it].type);
		newBind.stageFlags = shader_stage_to_vk_shader_stage(opts.bindings[it].shaderStage);
		array_add(*bindings, newBind);
	}
	info.pBindings = bindings.data;
	info.bindingCount = xx bindings.count;

	layout: BindGroupLayout;
	result := vkCreateDescriptorSetLayout(s.device, *info, null, *layout.platformHandle);
	assert(result == .SUCCESS, "Could not create descriptor set layout");

	layout.bindings = opts.bindings;
	return layout;
}

rhi_device_create_bind_group :: (using s: *Device, opts: BindGroupDesc) -> BindGroup {
	pool := *s.globalDescriptorPool;
	if opts.temp {
		pool = *s.perFrameDescriptorPool;
	}

	create_new_pool :: (using s: *Device) -> VkDescriptorPool {
		poolSizes: []VkDescriptorPoolSize = .[
			.{type = .SAMPLER, descriptorCount = 20 },
			.{type = .SAMPLED_IMAGE, descriptorCount = 100 },
			.{type = .STORAGE_IMAGE, descriptorCount = 50 },
			.{type = .UNIFORM_BUFFER, descriptorCount = 100 },
			.{type = .STORAGE_BUFFER, descriptorCount = 100 },
		];

		poolInfo: VkDescriptorPoolCreateInfo;
		poolInfo.flags = .FREE_DESCRIPTOR_SET_BIT;
		poolInfo.maxSets = 20;
		poolInfo.poolSizeCount = xx poolSizes.count;
		poolInfo.pPoolSizes = poolSizes.data;

		pool: VkDescriptorPool;
		result := vkCreateDescriptorPool(device, *poolInfo, null, *pool);
		return pool;
	}

	// attempt allocation in top most pool
	if pool.pools.count == 0 {
		array_add(*pool.pools, create_new_pool(s));
	}

	allocInfo: VkDescriptorSetAllocateInfo;
	allocInfo.descriptorPool = pool.pools[pool.pools.count-1];
	allocInfo.descriptorSetCount = 1;
	allocInfo.pSetLayouts = *opts.layout.platformHandle;

	descriptorSet: VkDescriptorSet;
	result := vkAllocateDescriptorSets(device, *allocInfo, *descriptorSet);

	// if it fails, make a new pool
	if result == .ERROR_OUT_OF_POOL_MEMORY || result == .ERROR_FRAGMENTED_POOL {
		array_add(*pool.pools, create_new_pool(s));
		allocInfo.descriptorPool = pool.pools[pool.pools.count-1];
		result = vkAllocateDescriptorSets(device, *allocInfo, *descriptorSet);
	}

	// count descriptor type allocations in the pool (mostly for tracking how well we've balanced the pool sizes)
	for 0..opts.layout.bindings.count-1 {
		pool.descriptorCounts[opts.layout.bindings[it].type] += 1; 
	}

	// write the resources to the descriptor set
	writeDescriptorSets: [..]VkWriteDescriptorSet;
	writeDescriptorSets.allocator = temp;

	imageInfos: [..]VkDescriptorImageInfo;
	imageInfos.allocator = temp;

	// update descriptor set with the given data
	for 0..opts.layout.bindings.count-1 {
		bind := opts.layout.bindings[it];
		if bind.type == .SAMPLER {
			assert(opts.resources[it].sampler.platformHandle != VK_NULL_HANDLE);

			imgInfo := array_add(*imageInfos);
			imgInfo.sampler = opts.resources[it].sampler.platformHandle;

			descriptorWrite := array_add(*writeDescriptorSets);
			descriptorWrite.dstSet = descriptorSet;
			descriptorWrite.dstBinding = xx opts.resources[it].slot;
			descriptorWrite.descriptorCount = 1;
			descriptorWrite.descriptorType = .SAMPLER;
			descriptorWrite.pImageInfo = imgInfo;
		}
		else if bind.type == .SAMPLED_IMAGE {
			assert(opts.resources[it].texture.image != VK_NULL_HANDLE);

			imgInfo := array_add(*imageInfos);
			imgInfo.imageLayout = .SHADER_READ_ONLY_OPTIMAL;
			imgInfo.imageView = opts.resources[it].texture.imageView;

			descriptorWrite := array_add(*writeDescriptorSets);
			descriptorWrite.dstSet = descriptorSet;
			descriptorWrite.dstBinding = xx opts.resources[it].slot;
			descriptorWrite.descriptorCount = 1;
			descriptorWrite.descriptorType = .SAMPLED_IMAGE;
			descriptorWrite.pImageInfo = imgInfo;
		}
		else if bind.type == .STORAGE_IMAGE {
			assert(opts.resources[it].texture.image != VK_NULL_HANDLE);

			imgInfo := array_add(*imageInfos);
			imgInfo.imageLayout = .GENERAL;
			imgInfo.imageView = opts.resources[it].texture.imageView;

			descriptorWrite := array_add(*writeDescriptorSets);
			descriptorWrite.dstSet = descriptorSet;
			descriptorWrite.dstBinding = xx opts.resources[it].slot;
			descriptorWrite.descriptorCount = 1;
			descriptorWrite.descriptorType = .STORAGE_IMAGE;
			descriptorWrite.pImageInfo = imgInfo;
		}
	}

	vkUpdateDescriptorSets(device, xx writeDescriptorSets.count, writeDescriptorSets.data, 0, null);

	bindGroup: BindGroup;
	bindGroup.platformHandle = descriptorSet;
	bindGroup.allocatedFrom = allocInfo.descriptorPool;
	bindGroup.canBeFreed = !opts.temp;
	return bindGroup;
}

rhi_device_create_pipeline :: (using s: *Device, opts: PipelineDesc) -> Pipeline {
	pipelineInfo: VkGraphicsPipelineCreateInfo;

	pushConstants: [ShaderStage.NUM_STAGES]VkPushConstantRange;
	for 0..opts.pushConstants.count-1 {
		pushConstants[it].offset = xx opts.pushConstants[it].offset;
		pushConstants[it].size = xx opts.pushConstants[it].size;
		pushConstants[it].stageFlags = shader_stage_to_vk_shader_stage(opts.pushConstants[it].stage);
	}

	setLayouts: [3]VkDescriptorSetLayout;
	for 0..opts.layouts.count-1 {
		setLayouts[it] = opts.layouts[it].platformHandle;
	}

	layoutCreateInfo: VkPipelineLayoutCreateInfo;
	layoutCreateInfo.pPushConstantRanges = pushConstants.data;
	layoutCreateInfo.pushConstantRangeCount = xx opts.pushConstants.count;
	layoutCreateInfo.pSetLayouts = setLayouts.data;
	layoutCreateInfo.setLayoutCount = xx opts.layouts.count;

	layout: VkPipelineLayout;
	vkCreatePipelineLayout(device, *layoutCreateInfo, null, *layout);
	pipelineInfo.layout = layout;

	renderInfo: VkPipelineRenderingCreateInfo;
	colorTargetFormats: [MAX_COLOR_TARGETS]VkFormat;
	for 0..opts.colorTargetCount-1 {
		colorTargetFormats[it] = pixel_format_to_vk_format(opts.colorTargets[it].format);
	}
	renderInfo.colorAttachmentCount = xx opts.colorTargetCount;
	renderInfo.pColorAttachmentFormats = colorTargetFormats.data;
	renderInfo.depthAttachmentFormat = pixel_format_to_vk_format(opts.depthTargetFormat);
	pipelineInfo.pNext = *renderInfo;

	shaderStages: [2]VkPipelineShaderStageCreateInfo;
	shaderStages[0].stage = .VERTEX_BIT;
	shaderStages[0].module = opts.vertexShader.platformHandle;
	shaderStages[0].pName = "main";
	shaderStages[1].stage = .FRAGMENT_BIT;
	shaderStages[1].module = opts.fragmentShader.platformHandle;
	shaderStages[1].pName = "main";
	pipelineInfo.stageCount = shaderStages.count;
	pipelineInfo.pStages = shaderStages.data;

	vertexInputInfo: VkPipelineVertexInputStateCreateInfo;
	pipelineInfo.pVertexInputState = *vertexInputInfo;

	inputAssembly: VkPipelineInputAssemblyStateCreateInfo;
	inputAssembly.primitiveRestartEnable = VK_FALSE;
	inputAssembly.topology = topology_to_vk_topology(opts.topology);
	pipelineInfo.pInputAssemblyState = *inputAssembly;

	viewportState: VkPipelineViewportStateCreateInfo;
	viewportState.viewportCount = 1;
	viewportState.scissorCount = 1;
	pipelineInfo.pViewportState = *viewportState;

	rasterizer: VkPipelineRasterizationStateCreateInfo;
	rasterizer.polygonMode = polygon_mode_to_vk_polygon_mode(opts.rasterizer.polygonMode);
	rasterizer.cullMode = cull_mode_to_vk_cull_mode(opts.rasterizer.cullMode);
	rasterizer.frontFace = front_face_to_vk_front_face(opts.rasterizer.frontFace); 
	rasterizer.depthClampEnable = VK_FALSE;
	rasterizer.lineWidth = 1;
	pipelineInfo.pRasterizationState = *rasterizer;

	multisampling: VkPipelineMultisampleStateCreateInfo;
	multisampling.sampleShadingEnable = VK_FALSE;
	multisampling.rasterizationSamples = .VK_SAMPLE_COUNT_1_BIT;
	multisampling.minSampleShading = 1.0;
	multisampling.pSampleMask = null;
	multisampling.alphaToCoverageEnable = VK_FALSE;
	multisampling.alphaToOneEnable = VK_FALSE;
	pipelineInfo.pMultisampleState = *multisampling;

	colorBlending: VkPipelineColorBlendStateCreateInfo;
	colorBlending.logicOpEnable = VK_FALSE;
	colorBlending.logicOp = .COPY;
	colorBlendAttachments: [MAX_COLOR_TARGETS]VkPipelineColorBlendAttachmentState;
	for 0..opts.colorTargetCount-1 {
		colorBlendAttachments[it].colorWriteMask = color_mask_to_vk_color_mask(opts.colorTargets[it].colorWriteMask);
		colorBlendAttachments[it].blendEnable = VK_FALSE;
	}
	colorBlending.attachmentCount = xx opts.colorTargetCount;
	colorBlending.pAttachments = colorBlendAttachments.data;
	pipelineInfo.pColorBlendState = *colorBlending;

	depthStencil: VkPipelineDepthStencilStateCreateInfo;
	depthStencil.depthTestEnable =  cast(VkBool32) opts.depth.depthTestEnabled;
	depthStencil.depthWriteEnable = cast(VkBool32) opts.depth.depthWriteEnabled;
	depthStencil.depthCompareOp = compare_op_to_vk_compare_op(opts.depth.compareOp);
	depthStencil.depthBoundsTestEnable = VK_FALSE;
	depthStencil.stencilTestEnable = cast(VkBool32) opts.depth.stencilTestEnabled;
	depthStencil.front = .{};
	depthStencil.back = .{};
	depthStencil.minDepthBounds = 0.0;
	depthStencil.maxDepthBounds = 1.0;
	pipelineInfo.pDepthStencilState = *depthStencil;

	state: []VkDynamicState = .[.VIEWPORT, .SCISSOR];
	dynamicInfo: VkPipelineDynamicStateCreateInfo;
	dynamicInfo.pDynamicStates = state.data;
	dynamicInfo.dynamicStateCount = xx state.count;
	pipelineInfo.pDynamicState = *dynamicInfo;

	pipeline: Pipeline;
	pipeline.pipelineLayout = layout;
	if vkCreateGraphicsPipelines(s.device, VK_NULL_HANDLE, 1, *pipelineInfo, null, *pipeline.platformHandle) == .SUCCESS {
		return pipeline;
	}

	// @todo: should probably crash the program here tbh
	print("Failed to create pipeline");
	return pipeline;
}

rhi_device_create_image :: (using s: *Device, size: VkExtent3D, format: PixelFormat, usage: VkImageUsageFlags) -> Texture {

	image: Texture;
	image.imageExtent = size;
	image.imageFormat = format; 

	imageInfo: VkImageCreateInfo;
	imageInfo.imageType = .VK_IMAGE_TYPE_2D;
	imageInfo.format = pixel_format_to_vk_format(format);
	imageInfo.extent = size;
	imageInfo.mipLevels = 1;
	imageInfo.arrayLayers = 1;
	imageInfo.samples = .VK_SAMPLE_COUNT_1_BIT;
	imageInfo.tiling = .VK_IMAGE_TILING_OPTIMAL;
	imageInfo.usage = usage;

	imgAllocInfo: VmaAllocationCreateInfo;
	imgAllocInfo.usage = .GPU_ONLY;
	imgAllocInfo.requiredFlags = .DEVICE_LOCAL_BIT;

	vmaCreateImage(gpuAllocator, *imageInfo, *imgAllocInfo, *image.image, *image.allocation, null);

	aspectFlag: VkImageAspectFlags = .COLOR_BIT;
	if format == .DEPTH {
		aspectFlag = .DEPTH_BIT;
	}
	imageViewInfo := image_view_create_info(imageInfo.format, image.image, aspectFlag);

	vkCreateImageView(device, *imageViewInfo, null, *image.imageView);
	return image;
}

rhi_device_create_image :: (using s: *Device, data: *void, size: VkExtent3D, format: PixelFormat, usage: VkImageUsageFlags) -> Texture {

	dataSize := size.depth * size.width * size.height * 4;
	uploadBuffer := rhi_device_create_buffer(s, dataSize, .TRANSFER_SRC_BIT, .CPU_TO_GPU);
	memcpy(uploadBuffer.info.pMappedData, data, dataSize);

	image := rhi_device_create_image(s, size, format, usage | .TRANSFER_DST_BIT | .TRANSFER_SRC_BIT);

	rhi_device_begin_immediate_submit(s);

	transition_image(immediateCommandBuffer, image.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL); 

	copyRegion: VkBufferImageCopy;
	copyRegion.bufferOffset = 0;
	copyRegion.bufferRowLength = 0;
	copyRegion.bufferImageHeight = 0;
	copyRegion.imageSubresource.aspectMask = .COLOR_BIT;
	copyRegion.imageSubresource.mipLevel = 0;
	copyRegion.imageSubresource.baseArrayLayer = 0;
	copyRegion.imageSubresource.layerCount = 1;
	copyRegion.imageExtent = size;
	vkCmdCopyBufferToImage(immediateCommandBuffer, uploadBuffer.buffer, image.image, .TRANSFER_DST_OPTIMAL, 1, *copyRegion);

	transition_image(immediateCommandBuffer, image.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL); 

	rhi_device_end_immediate_submit(s);
	return image;
}

rhi_device_create_sampler :: (s: *Device, opts: SamplerDesc) -> Sampler {
	samplerInfo: VkSamplerCreateInfo;
	samplerInfo.magFilter = opts.magFilter;
	samplerInfo.minFilter = opts.minFilter;
	samplerInfo.anisotropyEnable = VK_FALSE;

	sampler: Sampler;
	vkCreateSampler(s.device, *samplerInfo, null, *sampler.platformHandle);
	return sampler;
}

rhi_device_create_shader :: (s: *Device, bytes: []u8) -> Shader {
	createInfo: VkShaderModuleCreateInfo;
	createInfo.codeSize = xx bytes.count;
	createInfo.pCode = cast(*u32) bytes.data;

	shaderModule: VkShaderModule;
	result := vkCreateShaderModule(s.device, *createInfo, null, *shaderModule);
	assert(result == .SUCCESS, "Failed to create shader module");
	return .{platformHandle = shaderModule};
}

rhi_device_create_buffer :: (s: *Device, size: u64, usage: VkBufferUsageFlags, memoryUsage: VmaMemoryUsage) -> Buffer {
	info: VkBufferCreateInfo;
	info.size = size;
	info.usage = usage;

	allocInfo: VmaAllocationCreateInfo;
	allocInfo.usage = memoryUsage;
	allocInfo.flags = .MAPPED_BIT;
	newBuffer: Buffer;
	result := vmaCreateBuffer(s.gpuAllocator, *info, *allocInfo, *newBuffer.buffer, *newBuffer.allocation, *newBuffer.info);
	assert(result == .SUCCESS, "Failed to allocate buffer");
	return newBuffer;
}

rhi_device_destroy_buffer :: (s: *Device, buffer: *Buffer) {
	vmaDestroyBuffer(s.gpuAllocator, buffer.buffer, buffer.allocation);
}

rhi_device_destroy_bind_group :: (using s: *Device, bindGroup: BindGroup) {
	if bindGroup.canBeFreed {
		vkFreeDescriptorSets(device, bindGroup.allocatedFrom, 1, *bindGroup.platformHandle);
	}
}

rhi_device_reset_temporary_memory :: (using s: *Device) {
	for 0..s.perFrameDescriptorPool.pools.count-1 {
		vkResetDescriptorPool(device, perFrameDescriptorPool.pools[it], 0); 
	}
}

// evaluate if these functions definitely need to be exposed once more vulkan stuff is removed from main
rhi_device_begin_immediate_submit :: (using s: *Device) {
	result := vkResetFences(device, 1, *immediateFence);
	assert(result == .SUCCESS, "Could not reset fence");
	result = vkResetCommandBuffer(immediateCommandBuffer, 0);
	assert(result == .SUCCESS, "Could not reset immediate command pool");

	cmdBeginInfo := VkCommandBufferBeginInfo.{ flags = .ONE_TIME_SUBMIT_BIT };

	result = vkBeginCommandBuffer(immediateCommandBuffer, *cmdBeginInfo);
	assert(result == .SUCCESS, "Could not begin command buffer");
}

rhi_device_end_immediate_submit :: (using s: *Device) {
	result := vkEndCommandBuffer(immediateCommandBuffer);
	assert(result == .SUCCESS, "failed to end command buffer");

	cmdInfo := command_buffer_submit_info(immediateCommandBuffer);
	submit := submit_info(*cmdInfo, null, null);
	result = vkQueueSubmit2(graphicsQueue, 1, *submit, immediateFence);
	assert(result == .SUCCESS, "Failed to submit immediate cmd buffer");

	// takes absolutely ages, blocks use of the queue!!
	result = vkWaitForFences(device, 1, *immediateFence, VK_TRUE, 999999999999999999);
	assert(result == .SUCCESS, "Wait For fences failed");
}

// @todo: should be a function in the command buffer file
copy_image_to_image :: (cmd: VkCommandBuffer, source: VkImage, destination: VkImage, srcSize: VkExtent2D, dstSize: VkExtent2D) {
	blitRegion: VkImageBlit2;
	blitRegion.srcOffsets[1].x = xx srcSize.width;
	blitRegion.srcOffsets[1].y = xx srcSize.height;
	blitRegion.srcOffsets[1].z = 1;

	blitRegion.dstOffsets[1].x = xx dstSize.width;
	blitRegion.dstOffsets[1].y = xx dstSize.height;
	blitRegion.dstOffsets[1].z = 1;

	blitRegion.srcSubresource.aspectMask = .COLOR_BIT;
	blitRegion.srcSubresource.baseArrayLayer = 0;
	blitRegion.srcSubresource.layerCount = 1;
	blitRegion.srcSubresource.mipLevel = 0;

	blitRegion.dstSubresource.aspectMask = .COLOR_BIT;
	blitRegion.dstSubresource.baseArrayLayer = 0;
	blitRegion.dstSubresource.layerCount = 1;
	blitRegion.dstSubresource.mipLevel = 0;

	blitInfo: VkBlitImageInfo2;
	blitInfo.dstImage = destination;
	blitInfo.dstImageLayout = .TRANSFER_DST_OPTIMAL;
	blitInfo.srcImage = source;
	blitInfo.srcImageLayout = .TRANSFER_SRC_OPTIMAL;
	blitInfo.filter = .LINEAR;
	blitInfo.regionCount = 1;
	blitInfo.pRegions = *blitRegion;

	vkCmdBlitImage2(cmd, *blitInfo);
}

command_buffer_submit_info :: (cmd: VkCommandBuffer) -> VkCommandBufferSubmitInfo {
	info: VkCommandBufferSubmitInfo;
	info.commandBuffer = cmd;
	return info;
}

semaphore_submit_info :: ( stage_mask: VkPipelineStageFlags2, semaphore: VkSemaphore) -> VkSemaphoreSubmitInfo {
	submit_info: VkSemaphoreSubmitInfo;
	submit_info.semaphore = semaphore;
	submit_info.stageMask = stage_mask;
	submit_info.value = 1;
	return submit_info;
}

submit_info :: ( cmd: *VkCommandBufferSubmitInfo, signal_semaphore_info: *VkSemaphoreSubmitInfo, wait_semaphore_info: *VkSemaphoreSubmitInfo) -> VkSubmitInfo2 {
	info: VkSubmitInfo2;
	info.waitSemaphoreInfoCount = ifx wait_semaphore_info then cast(u32) 1 else cast(u32) 0;
    info.pWaitSemaphoreInfos = wait_semaphore_info;

    info.signalSemaphoreInfoCount = ifx signal_semaphore_info then cast(u32) 1 else cast(u32) 0;
    info.pSignalSemaphoreInfos = signal_semaphore_info;

    info.commandBufferInfoCount = 1;
    info.pCommandBufferInfos = cmd;
    return info;
}

#scope_file

// Enum converters

shader_stage_to_vk_shader_stage :: (shaderStage: ShaderStage) -> VkShaderStageFlags {
	if shaderStage == {
		case .VERTEX; return .VERTEX_BIT; 
		case .PIXEL; return .FRAGMENT_BIT; 
		case .COMPUTE; return .COMPUTE_BIT; 
		case; return .VERTEX_BIT;
	}
}

pixel_format_to_vk_format :: (format: PixelFormat) -> VkFormat {
	if format == {
		case .RGBA8; return .R8G8B8A8_UNORM;
		case .RGBA16F; return .R16G16B16A16_SFLOAT;
		case .DEPTH; return .D32_SFLOAT;
		case; return .UNDEFINED;
	}
}

topology_to_vk_topology :: (topology: Topology) -> VkPrimitiveTopology {
	if topology == {
		case .POINT_LIST; return .POINT_LIST; 
		case .LINE_LIST; return .LINE_LIST; 
		case .LINE_STRIP; return .LINE_STRIP; 
		case .TRIANGLE_LIST; return .TRIANGLE_LIST; 
		case .TRIANGLE_STRIP; return .TRIANGLE_STRIP; 
		case .TRIANGLE_FAN; return .TRIANGLE_FAN; 
		case; return .TRIANGLE_LIST;
	}
}

polygon_mode_to_vk_polygon_mode :: (polygonMode: PolygonMode) -> VkPolygonMode {
	if polygonMode == {
		case .FILL; return .FILL; 
		case .LINE; return .LINE; 
		case .POINT; return .POINT; 
		case; return .FILL;
	}
}

cull_mode_to_vk_cull_mode :: (cullMode: CullMode) -> VkCullModeFlagBits {
	if cullMode == {
		case .NONE; return .NONE; 
		case .FRONT; return .FRONT_BIT; 
		case .BACK; return .BACK_BIT; 
		case .FRONT_AND_BACK; return .FRONT_AND_BACK; 
		case; return .NONE;
	}
}

front_face_to_vk_front_face :: (frontFace: FrontFace) -> VkFrontFace {
	if frontFace == {
		case .COUNTER_CLOCKWISE; return .COUNTER_CLOCKWISE; 
		case .CLOCKWISE; return .CLOCKWISE; 
		case; return .CLOCKWISE;
	}
}

compare_op_to_vk_compare_op :: (compareOp: CompareOp) -> VkCompareOp {
	if compareOp == {
		case .NEVER; return .NEVER; 
		case .LESS; return .LESS; 
		case .EQUAL; return .EQUAL; 
		case .LESS_OR_EQUAL; return .LESS_OR_EQUAL; 
		case .GREATER; return .GREATER; 
		case .NOT_EQUAL; return .NOT_EQUAL; 
		case .GREATER_OR_EQUAL; return .GREATER_OR_EQUAL; 
		case .ALWAYS; return .ALWAYS; 
		case; return .NEVER;
	}
}

color_mask_to_vk_color_mask :: (colorMask: ColorComponentFlags) -> VkColorComponentFlags {
	vkMask: VkColorComponentFlags;
	if colorMask & .R then vkMask |= .R_BIT;
	if colorMask & .G then vkMask |= .G_BIT;
	if colorMask & .B then vkMask |= .B_BIT;
	if colorMask & .A then vkMask |= .A_BIT;
	return vkMask;
}

binding_type_to_vk_descriptor_type :: (bindingType: BindingType) -> VkDescriptorType {
	if bindingType == {
		case .SAMPLER; return .SAMPLER; 
		case .SAMPLED_IMAGE; return .SAMPLED_IMAGE; 
		case .STORAGE_IMAGE; return .STORAGE_IMAGE; 
		case .UNIFORM_BUFFER; return .UNIFORM_BUFFER; 
		case .STORAGE_BUFFER; return .STORAGE_BUFFER; 
		case; return .SAMPLED_IMAGE;
	}
}

// init code

init_vulkan :: (state: *Device) -> bool {
	#if VALIDATION_ENABLED 
	{
		if !supports_validation_layers() 
		{
			log_error("This GPU doesn't support validation layers.\n");
			return false;
		}
	}

	result := VkResult.ERROR_INITIALIZATION_FAILED;

	// instance
	app_info: VkApplicationInfo;
	app_info.pApplicationName = "VulkanRenderer";
	app_info.applicationVersion = #run VK_MAKE_API_VERSION(0, 1, 0, 0);
	app_info.pEngineName = "No Engine";
	app_info.engineVersion = #run VK_MAKE_API_VERSION(0, 1, 0, 0);
	app_info.apiVersion = VK_API_VERSION_1_3;

	create_info: VkInstanceCreateInfo;
	create_info.pApplicationInfo = *app_info;

	required_extensions, went_well := get_required_extensions(state);
	if !went_well then return false;

	create_info.enabledExtensionCount = xx required_extensions.count;
	create_info.ppEnabledExtensionNames = required_extensions.data;

	#if VALIDATION_ENABLED
	{
		create_info.enabledLayerCount = REQUIRED_VALIDATION_LAYERS.count;
		create_info.ppEnabledLayerNames = REQUIRED_VALIDATION_LAYERS.data;

		debug_create_info := create_debug_messenger_create_info();
		create_info.pNext = cast(*VkDebugUtilsMessengerCreateInfoEXT) *debug_create_info;
	}
	else
	{
		create_info.enabledLayerCount = 0;
	}

	result = vkCreateInstance(*create_info, null, *state.instance);

	// surface
	could_create_surface := SDL_Vulkan_CreateSurface(
		state.window, 
		state.instance, 
		*state.surface
	);
	assert(could_create_surface == .SDL_TRUE, "Failed to create Vulkan surface.");

	// physical device
	device_count: u32;
	vkEnumeratePhysicalDevices(state.instance, *device_count, null);
	if device_count == 0 
	{
		log_error("Could not find a GPU with Vulkan support.\n");
	}

	devices: [] VkPhysicalDevice;
	devices.count = device_count;
	devices.data = temporary_alloc(devices.count * size_of(VkPhysicalDevice));
	vkEnumeratePhysicalDevices(state.instance, *device_count, devices.data);

	scored_devices: [..] ScoredDevice;
	scored_devices.allocator = temp;

	for device: devices 
	{
		score := rate_device_suitability(device, state.surface);
		if score != 0
		{
			array_add(*scored_devices, ScoredDevice.{score, device});
		}
	}
	
	assert(scored_devices.count != 0, "Failed to find a suitable GPU.");
	
	highest_scored_device: ScoredDevice;
	for scored_device: scored_devices
	{
		if scored_device.score > highest_scored_device.score
		{
			highest_scored_device = scored_device;
		}
	}
	
	state.physicalDevice = highest_scored_device.device;

	// device
	indices := find_queue_families(state.physicalDevice, state.surface);
	
	indices_array := u32.[indices.graphics_family, indices.present_family];
	unique_indices: [..] u32;
	unique_indices.allocator = temp;
	for indices_array array_add_if_unique(*unique_indices, it);
	
	queue_priority := 1.0;
	queue_infos: [] VkDeviceQueueCreateInfo;
	queue_infos.data = temporary_alloc(unique_indices.count * size_of(VkDeviceQueueCreateInfo));
	queue_infos.count = unique_indices.count;
	
	for unique_indices 
	{
		queue_infos[it_index].sType = .DEVICE_QUEUE_CREATE_INFO;
		queue_infos[it_index].queueFamilyIndex = it;
		queue_infos[it_index].queueCount = 1;
		queue_infos[it_index].pQueuePriorities = *queue_priority;
	}
	
	device_features: VkPhysicalDeviceFeatures;
	
	dynamic_rendering := VkPhysicalDeviceDynamicRenderingFeatures.{dynamicRendering = VK_TRUE};
	sync2 := VkPhysicalDeviceSynchronization2Features.{
		synchronization2 = VK_TRUE, 
		pNext = *dynamic_rendering
	};
	buffer_device_address := VkPhysicalDeviceBufferDeviceAddressFeatures.{
		bufferDeviceAddress = VK_TRUE,
		pNext = *sync2,
	};
	
	extensions :: (*u8).[VK_KHR_SWAPCHAIN_EXTENSION_NAME];
	
	device_create_info: VkDeviceCreateInfo;
	device_create_info.pQueueCreateInfos = queue_infos.data;
	device_create_info.queueCreateInfoCount = xx queue_infos.count;
	device_create_info.pEnabledFeatures = *device_features;
	device_create_info.pNext = *buffer_device_address;
	device_create_info.enabledExtensionCount = extensions.count;
	device_create_info.ppEnabledExtensionNames = extensions.data;
	
	#if VALIDATION_ENABLED 
	{
		device_create_info.enabledLayerCount = REQUIRED_VALIDATION_LAYERS.count;
		device_create_info.ppEnabledLayerNames = REQUIRED_VALIDATION_LAYERS.data;
	}
	
	result = vkCreateDevice(state.physicalDevice, *device_create_info, null, *state.device);
	assert(result == .SUCCESS, "Failed to create logical device!");
	
	vkGetDeviceQueue(state.device, indices.graphics_family, 0, *state.graphicsQueue);
	vkGetDeviceQueue(state.device, indices.present_family, 0, *state.presentQueue);

	state.graphicsQueueFamily = indices.graphics_family;
	state.presentQueueFamily = indices.graphics_family;

	allocatorInfo: VmaAllocatorCreateInfo;
	allocatorInfo.physicalDevice = state.physicalDevice; 
	allocatorInfo.device = state.device; 
	allocatorInfo.instance = state.instance; 
	allocatorInfo.flags = .VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT; 
	vmaCreateAllocator(*allocatorInfo, *state.gpuAllocator);
	return result == .SUCCESS;
}

init_swapchain :: (state: *Device) {
	using state;
	
	swapchain_support := query_swapchain_support(physicalDevice, surface);
	surface_format := choose_swapchain_surface_format(swapchain_support.formats);
	present_mode = choose_swapchain_present_mode(swapchain_support.present_modes);
	extent := choose_swapchain_extent(swapchain_support.capabilities, window);
	
	image_count := swapchain_support.capabilities.minImageCount + 1;
	max_image_count := swapchain_support.capabilities.maxImageCount;
	if max_image_count > 0 && image_count > max_image_count then image_count = max_image_count;
	
	create_info: VkSwapchainCreateInfoKHR;
	create_info.surface = surface;
	create_info.minImageCount = image_count;
	create_info.imageFormat = surface_format.format;
	create_info.imageColorSpace = surface_format.colorSpace;
	create_info.imageExtent = extent;
	create_info.imageArrayLayers = 1;
	create_info.imageUsage = .COLOR_ATTACHMENT_BIT | .TRANSFER_DST_BIT;
	
	indices := find_queue_families(physicalDevice, surface);
	queue_family_indices := u32.[indices.graphics_family, indices.present_family];
	
	if indices.graphics_family != indices.present_family
	{
		create_info.imageSharingMode = .CONCURRENT;
		create_info.queueFamilyIndexCount = xx queue_family_indices.count;
		create_info.pQueueFamilyIndices = queue_family_indices.data;
	}
	else
	{
		create_info.imageSharingMode = .EXCLUSIVE;
	}
	
	create_info.preTransform = swapchain_support.capabilities.currentTransform;
	create_info.compositeAlpha = .OPAQUE_BIT_KHR;
	create_info.presentMode = present_mode;
	create_info.clipped = VK_TRUE;
	create_info.oldSwapchain = null;
	
	result := vkCreateSwapchainKHR(device, *create_info, null, *swapchain);
	assert(result == .SUCCESS, "Failed to create swapchain");

	vkGetSwapchainImagesKHR(device, swapchain, *image_count, null);
	array_resize(*swapchainImages, image_count);
	vkGetSwapchainImagesKHR(device, swapchain, *image_count, swapchainImages.data);
	swapchainImageFormat = surface_format.format;
	swapchainExtent = extent;
	
	array_resize(*frames, image_count);

	// init draw image
	drawImageUsageFlags : VkImageUsageFlags;
	drawImageUsageFlags |= .TRANSFER_SRC_BIT;
	drawImageUsageFlags |= .TRANSFER_DST_BIT;
	drawImageUsageFlags |= .STORAGE_BIT;
	drawImageUsageFlags |= .COLOR_ATTACHMENT_BIT;
	drawImage = rhi_device_create_image(state, VkExtent3D.{width = WIDTH, height = HEIGHT, depth=1}, .RGBA16F, drawImageUsageFlags);

	// init depth
	depthImageUsage: VkImageUsageFlags;
	depthImageUsage |= .DEPTH_STENCIL_ATTACHMENT_BIT;
	depthImage = rhi_device_create_image(state, drawImage.imageExtent, .DEPTH, depthImageUsage);
}

init_swapchain_image_views :: (state: *Device) {
	using state;
	
	array_resize(*swapchainImageViews, swapchainImages.count);
	
	for swapchainImages
	{
		createdInfo: VkImageViewCreateInfo;
		createdInfo.image = it;
		createdInfo.viewType = ._2D;
		createdInfo.format = swapchainImageFormat;
		createdInfo.components.r = .IDENTITY;
		createdInfo.components.g = .IDENTITY;
		createdInfo.components.b = .IDENTITY;
		createdInfo.components.a = .IDENTITY;
		createdInfo.subresourceRange.aspectMask = .COLOR_BIT;
		createdInfo.subresourceRange.baseMipLevel = 0;
		createdInfo.subresourceRange.levelCount = 1;
		createdInfo.subresourceRange.baseArrayLayer = 0;
		createdInfo.subresourceRange.layerCount = 1;
		
		result := vkCreateImageView(device, *createdInfo, null, *swapchainImageViews[it_index]);
	}
}

init_commands :: (state: *Device) {
	using state;
	
	
	commandPoolInfo := VkCommandPoolCreateInfo.{
		flags = .RESET_COMMAND_BUFFER_BIT,
		queueFamilyIndex = xx graphicsQueueFamily
	};

	result := vkCreateCommandPool(device, *commandPoolInfo, null, *immediateCommandPool);
	assert(result == .SUCCESS, "Could not create immediate command pool.");

	immediateCmdAllocInfo := VkCommandBufferAllocateInfo.{
		commandPool = immediateCommandPool,
		commandBufferCount = 1,
		level = .PRIMARY
	};

	result = vkAllocateCommandBuffers(device, *immediateCmdAllocInfo, *immediateCommandBuffer);
	assert(result == .SUCCESS, "Could not allocate immediate command buffer");

	for frames
	{
		result = vkCreateCommandPool(device, *commandPoolInfo, null, *it.commandPool);
		assert(result == .SUCCESS, "Could not create command pool.");
	
		cmd_alloc_info := VkCommandBufferAllocateInfo.{
			commandPool = it.commandPool,
			commandBufferCount = 1,
			level = .PRIMARY
		};
		
		result = vkAllocateCommandBuffers(device, *cmd_alloc_info, *it.mainCommandBuffer);
		assert(result == .SUCCESS, "Could not allocate command buffer.");
	}
}

init_sync_structures :: (state: *Device) {
	using state;

	fence_create_info := VkFenceCreateInfo.{
		flags = .SIGNALED_BIT
	};
	semaphore_create_info := VkSemaphoreCreateInfo.{
		flags = 0
	};

	result := vkCreateFence(device, *fence_create_info, null, *immediateFence);
	assert(result == .SUCCESS, "Could not create fence.");
	
	for frames
	{
		result = vkCreateFence(device, *fence_create_info, null, *it.renderFence);
		assert(result == .SUCCESS, "Could not create fence.");

		result = vkCreateSemaphore(device, *semaphore_create_info, null, *it.swapchainSemaphore);
		assert(result == .SUCCESS, "Could not create semaphore.");
		
		result = vkCreateSemaphore(device, *semaphore_create_info, null, *it.renderSempahore);
		assert(result == .SUCCESS, "Could not create semaphore.");
	}
}

init_descriptors :: (state: *Device) {
	using state;


	sizes := PoolSizeRatio.[.{ .STORAGE_IMAGE, 1 }, .{ .COMBINED_IMAGE_SAMPLER, 1}];

	globalDescriptorAllocator = init_pool(device, 10, sizes);
	
	// draw image descriptors setup
	{
		builder: DescriptorLayoutBuilder;
		add_binding_to_builder(*builder, 0, .STORAGE_IMAGE);
		drawImageDescriptorLayout = build_descriptor_layout(*builder, device, .COMPUTE_BIT);

		drawImageDescriptors = allocate_descriptor_set(*globalDescriptorAllocator, device, drawImageDescriptorLayout);

		imgInfo: VkDescriptorImageInfo;
		imgInfo.imageLayout = .GENERAL;
		imgInfo.imageView = drawImage.imageView;

		drawImageWrite: VkWriteDescriptorSet;
		drawImageWrite.dstSet = drawImageDescriptors;
		drawImageWrite.descriptorCount = 1;
		drawImageWrite.descriptorType = .STORAGE_IMAGE;
		drawImageWrite.pImageInfo = *imgInfo;

		vkUpdateDescriptorSets(device, 1, *drawImageWrite, 0, null);
	}
}

init_pipelines :: (state: *Device) {
	init_background_pipelines(state);
}

init_background_pipelines :: (state: *Device) {
	using state;
	computeLayout: VkPipelineLayoutCreateInfo;
	computeLayout.pSetLayouts = *drawImageDescriptorLayout;
	computeLayout.setLayoutCount = 1;

	pushConstant: VkPushConstantRange;
	pushConstant.offset = 0;
	pushConstant.size = size_of(ComputePushConstants);
	pushConstant.stageFlags = .COMPUTE_BIT;

	computeLayout.pPushConstantRanges = *pushConstant;
	computeLayout.pushConstantRangeCount = 1;
	vkCreatePipelineLayout(device, *computeLayout, null, *gradientPipelineLayout);

	// compile time load the shader binary
	// @todo potentially you can auto create these constants in the build code for each filename that gets compiled
	GRADIENT_SHADER :: #run SHADER_GET("gradient.comp");
	computeDrawShader := rhi_device_create_shader(state, GRADIENT_SHADER);

	stageInfo: VkPipelineShaderStageCreateInfo;
	stageInfo.stage = .COMPUTE_BIT;
	stageInfo.module = computeDrawShader.platformHandle;
	stageInfo.pName = "main";

	computePipelineCreateInfo: VkComputePipelineCreateInfo;
	computePipelineCreateInfo.layout = gradientPipelineLayout;
	computePipelineCreateInfo.stage = stageInfo;

	result := vkCreateComputePipelines(device, null, 1, *computePipelineCreateInfo, null, *gradientPipeline);
	assert(result == .SUCCESS, "Failed to create compute pipeline");

	vkDestroyShaderModule(device, computeDrawShader.platformHandle, null);
}

alloc_imgui :: (sz: u64, user_data: *void) -> *void #c_call
{
	new_context: Context;
	push_context new_context
	{
		return alloc(xx sz);
	}
}

free_imgui :: (ptr: *void, user_data: *void) #c_call
{
	new_context: Context;
	push_context new_context
	{
		free(ptr);
	}
}

init_imgui :: (s: *Device) {
	using s;
	poolSizes := VkDescriptorPoolSize.[.{.COMBINED_IMAGE_SAMPLER, 1}];
	poolInfo: VkDescriptorPoolCreateInfo;
	poolInfo.flags = .FREE_DESCRIPTOR_SET_BIT;
	poolInfo.maxSets = 1;
	poolInfo.poolSizeCount = poolSizes.count;
	poolInfo.pPoolSizes = poolSizes.data;
	result := vkCreateDescriptorPool(device, *poolInfo, null, *imguiDescriptorPool);
	assert(result == .SUCCESS, "Could not create descriptor pool");

	ImGui.SetAllocatorFunctions(alloc_imgui, free_imgui);
	ImGui.CreateContext();

	io := ImGui.GetIO();
	io.ConfigFlags_ |= .NavEnableKeyboard;
	io.ConfigFlags_ |= .DockingEnable;

	ImGui_ImplSDL2_InitForVulkan(window);

	pipelineRenderingInfo: VkPipelineRenderingCreateInfoKHR;
	pipelineRenderingInfo.colorAttachmentCount = 1;
	pipelineRenderingInfo.pColorAttachmentFormats = *swapchainImageFormat;

	initInfo: ImGui_ImplVulkan_InitInfo;
	initInfo.Instance = instance;
	initInfo.PhysicalDevice = physicalDevice;
	initInfo.Device = device;
	initInfo.QueueFamily = xx graphicsQueueFamily;
	initInfo.Queue = graphicsQueue;
	initInfo.PipelineCache = VK_NULL_HANDLE;
	initInfo.DescriptorPool = imguiDescriptorPool;
	initInfo.RenderPass = null;
	initInfo.UseDynamicRendering = true;
	initInfo.PipelineRenderingCreateInfo = pipelineRenderingInfo;
	initInfo.Subpass = 0;
	initInfo.MinImageCount = xx swapchainImages.count;
	initInfo.ImageCount = xx swapchainImages.count;
	initInfo.MSAASamples = ._1_BIT;
	initInfo.Allocator = null;

	ImGui_ImplVulkan_Init(*initInfo);
	ImGui_ImplVulkan_CreateFontsTexture();
}

supports_validation_layers :: () -> bool {
	layer_count: u32;
	vkEnumerateInstanceLayerProperties(*layer_count, null);

	available_layers: [] VkLayerProperties;
	available_layers.data = temporary_alloc(layer_count * size_of(VkLayerProperties));
	available_layers.count = layer_count;

	vkEnumerateInstanceLayerProperties(*layer_count, available_layers.data);

	for layer_name: REQUIRED_VALIDATION_LAYERS
	{
		layer_found := false;

		for layer_properties: available_layers 
		{
			layer_property_name := cast(string) layer_properties.layerName;
			layer_name_string := to_string(layer_name);
			layer_property_name.count = layer_name_string.count;

			if compare(layer_name_string, layer_property_name) == 0
			{
				layer_found = true;
				break;
			}
		}

		if !layer_found then return false;
	}

	return true;
}

get_required_extensions :: (state: *Device) -> [..] *u8, bool {
	required_extensions: [..] *u8;
	required_extensions.allocator = temp;

	extensions_count: u32;
	could_get_instance_extensions_count := SDL_Vulkan_GetInstanceExtensions(state.window, *extensions_count, null);
	if !could_get_instance_extensions_count 
	{
		log_error("Could not get instance extensions count from SDL.\n");
		return required_extensions, false;
	}

	array_reserve(*required_extensions, xx extensions_count);
	required_extensions.count = xx extensions_count;

	could_get_instance_extensions := SDL_Vulkan_GetInstanceExtensions(state.window, *extensions_count, required_extensions.data);
	if !could_get_instance_extensions 
	{
		log_error("Could not get instance extensions from SDL.\n");
		return required_extensions, false;
	}

	#if BUILD_TYPE != .RELEASE
	{
		array_add(*required_extensions, VK_EXT_DEBUG_UTILS_EXTENSION_NAME.data);
	}

	return required_extensions, true;
}

vulkan_debug_callback :: ( messageSeverity: VkDebugUtilsMessageSeverityFlagBitsEXT, messageType: VkDebugUtilsMessageTypeFlagsEXT, 
pCallbackData: *VkDebugUtilsMessengerCallbackDataEXT, pUserData: *void) -> VkBool32 #c_call {
	new_context: Context;
	push_context new_context 
	{
		new_context.logger = logger;
		
		message := to_string(pCallbackData.pMessage);
		if messageSeverity ==
		{
			case .VERBOSE_BIT_EXT;
				log("VULKAN_VALIDATION(VERBOSE): %\n", message, flags = .VERY_VERBOSE_ONLY);
			case .INFO_BIT_EXT;
				log("VULKAN_VALIDATION(INFO): %\n", message, flags = .VERBOSE_ONLY);
			case .WARNING_BIT_EXT;
				log("VULKAN_VALIDATION(WARNING): %\n", message, flags = .WARNING);
			case .ERROR_BIT_EXT;
				log_error("VULKAN_VALIDATION(ERROR): %\n", message);
				assert(false);
			case;
				log("VULKAN_VALIDATION(UNKOWN): %\n", message);
			
		}
	}

	return VK_FALSE;
}

create_debug_messenger_create_info :: () -> VkDebugUtilsMessengerCreateInfoEXT {
	create_info: VkDebugUtilsMessengerCreateInfoEXT;
	create_info.messageSeverity = .WARNING_BIT_EXT | .ERROR_BIT_EXT;
	create_info.messageType = .GENERAL_BIT_EXT | .VALIDATION_BIT_EXT | .PERFORMANCE_BIT_EXT;
	create_info.pfnUserCallback = vulkan_debug_callback;

	return create_info;
}

ScoredDevice :: struct
{
	score: int;
	device: VkPhysicalDevice;
}

// A score of 0 indicates that the device is not suitable
rate_device_suitability :: (device: VkPhysicalDevice, surface: VkSurfaceKHR) -> int {
	properties: VkPhysicalDeviceProperties2;
	vkGetPhysicalDeviceProperties2(device, *properties);
	
	indices := find_queue_families(device, surface);
	if !is_queue_family_complete(indices) then return 0;
	if !check_physical_device_extensions(device) then return 0;
	if !check_vulkan_features(device) then return 0;
	
	swapchain_support := query_swapchain_support(device, surface);
	if swapchain_support.formats.count == 0 || swapchain_support.present_modes.count == 0
		return 0;

	if properties.properties.apiVersion < VK_API_VERSION_1_3 then return 0;
	
	score := 100;
	if properties.properties.deviceType == .DISCRETE_GPU then score += 1000;
	score += properties.properties.limits.maxImageDimension2D;
	
	return score;
}

QueueFamilyIndices :: struct
{
	graphics_family: u32;
	present_family: u32;
	has_graphics_family: bool;
	has_present_family: bool;
}

is_queue_family_complete :: (indices: QueueFamilyIndices) -> bool {
	return indices.has_graphics_family && indices.has_present_family;
}

find_queue_families :: (device: VkPhysicalDevice, surface: VkSurfaceKHR) -> QueueFamilyIndices {
	indices: QueueFamilyIndices;

	queue_family_count: u32;
	vkGetPhysicalDeviceQueueFamilyProperties(device, *queue_family_count, null);

	queue_families: [] VkQueueFamilyProperties;
	queue_families.count = queue_family_count;
	queue_families.data = temporary_alloc(queue_families.count * size_of(VkQueueFamilyProperties));
	vkGetPhysicalDeviceQueueFamilyProperties(device, *queue_family_count, queue_families.data);

	for i: 0..queue_families.count - 1
	{
		if queue_families[i].queueFlags & .GRAPHICS_BIT
		{
			indices.graphics_family = xx i;
			indices.has_graphics_family = true;
		}
		
		present_support: VkBool32;
		vkGetPhysicalDeviceSurfaceSupportKHR(device, xx i, surface, *present_support);
		if present_support == VK_TRUE
		{
			indices.present_family = xx i;
			indices.has_present_family = true;
		}

		if is_queue_family_complete(indices) then break;
	}

	return indices;
}

check_physical_device_extensions :: (device: VkPhysicalDevice) -> bool {
	extensions_count: u32;
	result := vkEnumerateDeviceExtensionProperties(device, null, *extensions_count, null);
	if result != .SUCCESS
	{
		log_error("Failed to enumerate device extensions for a physical device\n");
		return false;
	}

	extensions: [] VkExtensionProperties;
	extensions.count = extensions_count;
	extensions.data = temporary_alloc(extensions_count * size_of(VkExtensionProperties));
	result = vkEnumerateDeviceExtensionProperties(device, null, *extensions_count, extensions.data);
	if result != .SUCCESS
	{
		log_error("Failed to enumerate device extensions for a physical device\n");
		return false;
	}

	DEVICE_REQUIRED_EXTENSION_NAMES :: string.[VK_KHR_SWAPCHAIN_EXTENSION_NAME];

	for required_ext_name: DEVICE_REQUIRED_EXTENSION_NAMES
	{
		found_in_available := false;
		for available_extension: extensions
		{
			available_ext_name := cast(string) available_extension.extensionName;
			available_ext_name.count = strlen(*available_extension.extensionName[0]);
			if required_ext_name == available_ext_name then 
			{
				found_in_available = true;
				break;
			}
		}
		
		if !found_in_available then return false;
	}

	return true;
}

check_vulkan_features :: (device: VkPhysicalDevice) -> bool {
	vulkan_12_features: VkPhysicalDeviceVulkan12Features;
	features: VkPhysicalDeviceFeatures2;
	features.pNext = *vulkan_12_features;
	vkGetPhysicalDeviceFeatures2(device, *features);

	if !vulkan_12_features.descriptorIndexing || !vulkan_12_features.bufferDeviceAddress
		return false;

	vulkan_13_features: VkPhysicalDeviceVulkan13Features;
	features.pNext = *vulkan_13_features;
	vkGetPhysicalDeviceFeatures2(device, *features);

	if !vulkan_13_features.dynamicRendering || !vulkan_13_features.synchronization2
		 return false;

	return true;
}

SwapchainSupportDetails :: struct
{
	capabilities: VkSurfaceCapabilitiesKHR;
	formats: [] VkSurfaceFormatKHR;
	present_modes: [] VkPresentModeKHR;
}

query_swapchain_support :: ( device: VkPhysicalDevice, surface: VkSurfaceKHR) -> SwapchainSupportDetails {
	details: SwapchainSupportDetails;
	
	vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, *details.capabilities);
	
	format_count: u32;
	vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, *format_count, null);
	
	if format_count > 0
	{
		details.formats.count = format_count;
		details.formats.data = temporary_alloc(format_count * size_of(VkSurfaceFormatKHR));
		vkGetPhysicalDeviceSurfaceFormatsKHR(device, surface, *format_count, details.formats.data);
	}
	
	present_mode_count: u32;
	vkGetPhysicalDeviceSurfacePresentModesKHR(device, surface, *present_mode_count, null);
	
	if present_mode_count > 0
	{
		details.present_modes.count = present_mode_count;
		details.present_modes.data = 
			temporary_alloc(present_mode_count * size_of(VkPresentModeKHR));
		vkGetPhysicalDeviceSurfacePresentModesKHR(
			device, 
			surface, 
			*present_mode_count, 
			details.present_modes.data
		);
	}
	
	return details;
}

choose_swapchain_surface_format :: (available_formats: [] VkSurfaceFormatKHR) -> VkSurfaceFormatKHR {
	for available_formats
	{
		if it.format == .B8G8R8A8_SRGB && it.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR
			return it;
	}
	
	return available_formats[0];
}

choose_swapchain_present_mode :: (available_present_modes: [] VkPresentModeKHR) -> VkPresentModeKHR {
	for available_present_modes if it == .MAILBOX_KHR then return it;

	return .FIFO_KHR;
}

choose_swapchain_extent :: (capabilities: VkSurfaceCapabilitiesKHR, window: *SDL_Window) -> VkExtent2D {
	if capabilities.currentExtent.width != U32_MAX then return capabilities.currentExtent;
	
	width, height: s32;
	SDL_GetWindowSize(window, *width, *height);
	
	extent := VkExtent2D.{width = xx width, height = xx height};
	
	extent.width = clamp(
		extent.width, 
		capabilities.minImageExtent.width, 
		capabilities.maxImageExtent.width
	);
	
	extent.height = clamp(
		extent.height, 
		capabilities.minImageExtent.height, 
		capabilities.maxImageExtent.height
	);
	
	return extent;
}

image_subresource_range :: (aspect_mask: VkImageAspectFlags) -> VkImageSubresourceRange
{
	sub_image: VkImageSubresourceRange;
    sub_image.aspectMask = aspect_mask;
    sub_image.levelCount = VK_REMAINING_MIP_LEVELS;
    sub_image.layerCount = VK_REMAINING_ARRAY_LAYERS;
    return sub_image;
}

// descriptor pool management

DescriptorPool :: struct {
	pools: [..]VkDescriptorPool;
	descriptorCounts: [BindingType.NUM_BINDING_TYPES]u32;
}

// createinfos

image_view_create_info :: (format: VkFormat, image: VkImage, aspectFlags: VkImageAspectFlags) -> VkImageViewCreateInfo {
	info: VkImageViewCreateInfo;
	info.viewType = .VK_IMAGE_VIEW_TYPE_2D;
	info.image = image;
	info.format = format;
	info.subresourceRange.baseMipLevel = 0;
	info.subresourceRange.levelCount = 1;
	info.subresourceRange.baseArrayLayer = 0;
	info.subresourceRange.layerCount = 1;
	info.subresourceRange.aspectMask = aspectFlags;
	return info;
}

#import "vulkan";
#import "vma";

#load "descriptors.jai";
#load "../imgui_backend.jai";

VALIDATION_ENABLED :: BUILD_TYPE != .RELEASE;
REQUIRED_VALIDATION_LAYERS :: (*u8).["VK_LAYER_KHRONOS_validation"];
FRAMES_OVERLAP :: 2;
