#import "Basic"()(MEMORY_DEBUGGER = BUILD_TYPE != .RELEASE, ENABLE_ASSERT = BUILD_TYPE != .RELEASE);

#import "SDL"(VULKAN = true);
#import "Print_Color";
#import "String";
#import "Math";
#import "stb_image";

#load "gfx_device.jai";


WIDTH :: 800;
HEIGHT :: 600;

// what does our API look like:

// gfx device
// init_device(options) -- does all the init stuff for you and gives you the device struct to hold on to
// create_shader(shaderdata) -- 
// create_pipeline(options)
// create_texture/_with_data(options)
// upload_to_texture(data)
// create_buffer/_with_data(options)
// upload_to_buffer(data)
// acquire_command_buffer(options) -- device maintains a pool of command buffers, gives them out as requested and begin's them
// submit_command_buffer(buffer) -- ends the command buffer and submits it, will present if a swapchain texture was used

// commandbuffer
// wait_for_swapchain_texture() -- acquires a swapchain texture for rendering into. As with SDL, when this occurs, automatically present when the command buffer is submitted
// all the things you can do with a command buffer

main :: () {
	context.logger = logger;

	// Create the window
	result_sdl := SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER);
	if result_sdl != 0
	{
		log_error("Could not load SDL : %\n", to_string(SDL_GetError()));
	}

	sdl_flags: SDL_WindowFlags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_VULKAN;
	window := SDL_CreateWindow("Hello Vulkan with Jai", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WIDTH, HEIGHT, sdl_flags);
	if window == null 
	{
		log_error("Could not create window: %\n", to_string(SDL_GetError()));
	}

	device: GfxDevice;
	gfx_device_init(*device, window, WIDTH, HEIGHT);
	init_mesh_pipeline(*device);
	init_cube_mesh(*device);

	should_stop_rendering := false;
	while !should_stop_rendering {
		event: SDL_Event;
		while SDL_PollEvent(*event)
		{
			if event.type ==
			{
				case SDL_QUIT;
					should_stop_rendering = true;
				case SDL_KEYDOWN;
					if event.key.keysym.sym == SDLK_ESCAPE 
					{
						should_stop_rendering = true;
					}
			}
			ImGui_ImplSDL2_ProcessEvent(*event);
		}
		draw(*device);
		reset_temporary_storage();
	}
}

init_mesh_pipeline :: (using s: *GfxDevice) {
	// load the texture for the cube
	{
		x, y: s32;
		comp: s32;
		imageData: *u8 = stbi_load("crate.png", *x, *y, *comp, 4);

		crateTexture = gfx_device_create_image(s, imageData, VkExtent3D.{width = xx x, height = xx y, depth=1}, .R8G8B8A8_UNORM, .SAMPLED_BIT);
	}

	samplerInfo := VkSamplerCreateInfo.{magFilter = .LINEAR, minFilter= .LINEAR};
	vkCreateSampler(device, *samplerInfo, null, *linearSampler);

	// crate texture descriptor setup
	{
		builder: DescriptorLayoutBuilder;
		add_binding_to_builder(*builder, 0, .COMBINED_IMAGE_SAMPLER);
		textureDescriptorSetLayout = build_descriptor_layout(*builder, device, .FRAGMENT_BIT);

		textureDescriptorSet = allocate_descriptor_set(*globalDescriptorAllocator, device, textureDescriptorSetLayout);

		imgInfo: VkDescriptorImageInfo;
		imgInfo.imageLayout = .SHADER_READ_ONLY_OPTIMAL;
		imgInfo.imageView = crateTexture.imageView;
		imgInfo.sampler = linearSampler;

		imageWrite: VkWriteDescriptorSet;
		imageWrite.dstSet = textureDescriptorSet;
		imageWrite.descriptorCount = 1;
		imageWrite.descriptorType = .COMBINED_IMAGE_SAMPLER;
		imageWrite.pImageInfo = *imgInfo;

		vkUpdateDescriptorSets(device, 1, *imageWrite, 0, null);
	}

	VERT :: #run SHADER_GET("colored_triangle_mesh.vert");
	vertShader := gfx_device_create_shader(s, VERT);
	// @todo this is duplicated above, something to improve
	FRAG :: #run SHADER_GET("colored_triangle.frag");
	fragShader := gfx_device_create_shader(s, FRAG);

	pushConstant: VkPushConstantRange;
	pushConstant.offset = 0;
	pushConstant.size = size_of(GpuDrawPushConstants);
	pushConstant.stageFlags = .VERTEX_BIT;

	// @todo: set our descriptor set layout here for passing an image to the shader
	meshPipelineLayoutCreateInfo: VkPipelineLayoutCreateInfo;
	meshPipelineLayoutCreateInfo.pPushConstantRanges = *pushConstant;
	meshPipelineLayoutCreateInfo.pushConstantRangeCount = 1;
	meshPipelineLayoutCreateInfo.pSetLayouts = *textureDescriptorSetLayout;
	meshPipelineLayoutCreateInfo.setLayoutCount = 1;

	vkCreatePipelineLayout(device, *meshPipelineLayoutCreateInfo, null, *meshPipelineLayout);

	meshPipeline := gfx_device_create_pipeline(s, .{
		vkLayout = meshPipelineLayout,
		vertexShader = gfx_device_create_shader(s, #run SHADER_GET("colored_triangle_mesh.vert")),
		fragmentShader = gfx_device_create_shader(s, #run SHADER_GET("colored_triangle.frag")),
		topology = .TRIANGLE_LIST,
		rasterizer = .{
			polygonMode = .FILL,
			cullMode = .NONE,
			frontFace = .CLOCKWISE,
		},
		colorTargetCount = 1,
		colorTargets[0] = .{
			format = drawImage.imageFormat
		},
		depthTargetFormat = depthImage.imageFormat,
		depth = .{
			depthWriteEnabled = true,
			depthTestEnabled = true,
			compareOp = .GREATER_OR_EQUAL
		}
	});

	builder: PipelineBuilder;
	builder.pipelineLayout = meshPipelineLayout; // done
	builder.inputAssembly.topology = .TRIANGLE_LIST; // done
	builder.rasterizer.polygonMode = .FILL; // done
	builder.rasterizer.cullMode = .NONE; // done
	builder.rasterizer.frontFace = .CLOCKWISE; // done
	builder.rasterizer.depthClampEnable = VK_TRUE; // done
	builder_set_shaders(*builder, vertShader, fragShader); // done
	builder_set_multisample_none(*builder); // not needed
	builder_disable_blending(*builder); // not needed
	builder_enable_depthtest(*builder, true, .GREATER_OR_EQUAL);
	builder_set_color_attachment_format(*builder, drawImage.imageFormat); // done
	builder_set_depth_attachment_format(*builder, depthImage.imageFormat); // done

	meshPipeline = build_pipeline(*builder, s);
}

init_cube_mesh :: (using s: *GfxDevice) {
	cubeVerts : [8]Vertex;
	
	// front side
	cubeVerts[0].position = .{-0.5, -0.5, 0.5};
	cubeVerts[0].uv_x = 0.0;
	cubeVerts[0].uv_y = 0.0;
	cubeVerts[1].position = .{0.5, -0.5, 0.5};
	cubeVerts[1].uv_x = 1.0;
	cubeVerts[1].uv_y = 0.0;
	cubeVerts[2].position = .{-0.5, 0.5, 0.5};
	cubeVerts[2].uv_x = 0.0;
	cubeVerts[2].uv_y = 1.0;
	cubeVerts[3].position = .{0.5, 0.5, 0.5};
	cubeVerts[3].uv_x = 1.0;
	cubeVerts[3].uv_y = 1.0;

	// back side
	cubeVerts[4].position = .{-0.5, -0.5, -0.5};
	cubeVerts[4].uv_x = 1.0;
	cubeVerts[4].uv_y = 0.0;
	cubeVerts[5].position = .{0.5, -0.5, -0.5};
	cubeVerts[5].uv_x = 0.0;
	cubeVerts[5].uv_y = 0.0;
	cubeVerts[6].position = .{-0.5, 0.5, -0.5};
	cubeVerts[6].uv_x = 1.0;
	cubeVerts[6].uv_y = 1.0;
	cubeVerts[7].position = .{0.5, 0.5, -0.5};
	cubeVerts[7].uv_x = 0.0;
	cubeVerts[7].uv_y = 1.0;

	cubeVerts[0].color = .{0, 0, 0, 1};
	cubeVerts[1].color = .{0.5, 0.5, 0.5, 1};
	cubeVerts[2].color = .{1, 0, 0, 1};
	cubeVerts[3].color = .{0, 1, 0, 1};
	cubeVerts[4].color = .{0, 0, 0, 1};
	cubeVerts[5].color = .{0.5, 0.5, 0.5, 1};
	cubeVerts[6].color = .{1, 0, 0, 1};
	cubeVerts[7].color = .{0, 1, 0, 1};

	cubeIndices : []u32 = .[
		//Top
        2, 6, 7,
        2, 3, 7,

        //Bottom
        0, 4, 5,
        0, 1, 5,

        //Left
        0, 2, 6,
        0, 4, 6,

        //Right
        1, 3, 7,
        1, 5, 7,

        //Front
        0, 2, 3,
        0, 1, 3,

        //Back
        4, 6, 7,
        4, 5, 7
	];

	cubeMesh = upload_mesh(s, cubeIndices, cubeVerts);
}

upload_mesh :: (s: *GfxDevice, indices: []u32, vertices: []Vertex) -> GpuMeshBuffers {
	vertexBufferSize := vertices.count * size_of(Vertex);
	indexBufferSize := indices.count * size_of(u32);

	mesh: GpuMeshBuffers;

	mesh.vertexBuffer = gfx_device_create_buffer(s, xx vertexBufferSize, .STORAGE_BUFFER_BIT | .TRANSFER_DST_BIT | .SHADER_DEVICE_ADDRESS_BIT, .GPU_ONLY);

	deviceAddressInfo: VkBufferDeviceAddressInfo;
	deviceAddressInfo.buffer = mesh.vertexBuffer.buffer;
	mesh.deviceAddress = vkGetBufferDeviceAddress(s.device, *deviceAddressInfo);

	mesh.indexBuffer = gfx_device_create_buffer(s, xx indexBufferSize, .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT, .GPU_ONLY);

	// here's where the actual data upload happens
	// it's doing a full immediate submit, should research how to do this better
	staging := gfx_device_create_buffer(s, xx (vertexBufferSize + indexBufferSize), .TRANSFER_SRC_BIT, .CPU_ONLY);

	data := staging.info.pMappedData;

	memcpy(data, vertices.data, vertexBufferSize);
	memcpy(cast(*u8)data + vertexBufferSize, indices.data, indexBufferSize);

	gfx_device_begin_immediate_submit(s);

	vertexCopy: VkBufferCopy;
	vertexCopy.dstOffset = 0;
	vertexCopy.srcOffset = 0;
	vertexCopy.size = xx vertexBufferSize;
	vkCmdCopyBuffer(s.immediateCommandBuffer, staging.buffer, mesh.vertexBuffer.buffer, 1, *vertexCopy);

	indexCopy: VkBufferCopy;
	indexCopy.dstOffset = 0;
	indexCopy.srcOffset = xx vertexBufferSize;
	indexCopy.size = xx indexBufferSize;
	vkCmdCopyBuffer(s.immediateCommandBuffer, staging.buffer, mesh.indexBuffer.buffer, 1, *indexCopy);

	gfx_device_end_immediate_submit(s);
	return mesh;
}

draw :: (s: *GfxDevice) {
	ImGui_ImplVulkan_NewFrame();
	ImGui_ImplSDL2_NewFrame();
	ImGui.NewFrame();


	// ImGui.ShowDemoWindow();

	// if ImGui.Begin("Background") {
	// 	ImGui.InputFloat4("data1", *state.pc.data1.component);
	// 	ImGui.InputFloat4("data2", *state.pc.data2.component);
	// 	ImGui.InputFloat4("data3", *state.pc.data3.component);
	// 	ImGui.InputFloat4("data4", *state.pc.data4.component);
	// }
	// ImGui.End();

	ImGui.Render();


	ONE_SECOND_IN_NS :: 1000000000;
	vkWaitForFences(s.device, 1, *gfx_device_get_current_frame(s).renderFence, VK_TRUE, ONE_SECOND_IN_NS);
	vkResetFences(s.device, 1, *gfx_device_get_current_frame(s).renderFence);

	swapchain_image_index: u32;
	vkAcquireNextImageKHR(
		s.device, 
		s.swapchain, 
		ONE_SECOND_IN_NS, 
		gfx_device_get_current_frame(s).swapchainSemaphore, 
		null, 
		*swapchain_image_index
	);

	cmd_begin_info := VkCommandBufferBeginInfo.{
		flags = .ONE_TIME_SUBMIT_BIT
	};

	cmd := gfx_device_get_current_frame(s).mainCommandBuffer;
	vkResetCommandBuffer(cmd, 0);

	s.drawExtent.width = s.drawImage.imageExtent.width;
	s.drawExtent.height = s.drawImage.imageExtent.height;

	vkBeginCommandBuffer(cmd, *cmd_begin_info);

	transition_image(cmd, s.drawImage.image, .UNDEFINED, .GENERAL);

	// draw background with compute
	////////////////////////////////

	// Actually clear our screen
	// clear_value: VkClearColorValue;
	// flash := abs(sin(cast(float32)s.frame_number / 1020.0));
	// clear_value._float32 = float32.[0.0, 0.0, xx flash, 1.0];
	//  
	// clear_range := image_subresource_range(.COLOR_BIT);
	// vkCmdClearColorImage(cmd, s.drawImage.image, .GENERAL, *clear_value, 1, *clear_range);

	// compute to draw our gradient
	vkCmdBindPipeline(cmd, .COMPUTE, s.gradientPipeline);
	vkCmdBindDescriptorSets(cmd, .COMPUTE, s.gradientPipelineLayout, 0, 1, *s.drawImageDescriptors, 0, null);

	vkCmdPushConstants(cmd, s.gradientPipelineLayout, .COMPUTE_BIT, 0, size_of(ComputePushConstants), *s.pc);
	vkCmdDispatch(cmd, xx ceil(s.drawExtent.width / 16.0), xx ceil(s.drawExtent.width / 16.0), 1);


	transition_image(cmd, s.drawImage.image, .GENERAL, .COLOR_ATTACHMENT_OPTIMAL);
	transition_image(cmd, s.depthImage.image, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL);

	draw_geometry(cmd, s);

	// blit our frame onto the swapchain
	transition_image(cmd, s.drawImage.image, .COLOR_ATTACHMENT_OPTIMAL, .TRANSFER_SRC_OPTIMAL);
	transition_image(cmd, s.swapchainImages[swapchain_image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL);

	copy_image_to_image(cmd, s.drawImage.image, s.swapchainImages[swapchain_image_index], s.drawExtent, s.swapchainExtent);

	transition_image(cmd, s.swapchainImages[swapchain_image_index], .TRANSFER_DST_OPTIMAL, .COLOR_ATTACHMENT_OPTIMAL);

	// draw imgui render lists
	attachmentInfo: VkRenderingAttachmentInfo;
	attachmentInfo.imageView = s.swapchainImageViews[swapchain_image_index];
	attachmentInfo.imageLayout = .COLOR_ATTACHMENT_OPTIMAL;
	attachmentInfo.loadOp = .LOAD;
	attachmentInfo.storeOp = .STORE;

	renderingInfo: VkRenderingInfo;
	renderingInfo.renderArea.extent = s.swapchainExtent;
	renderingInfo.layerCount = 1;
	renderingInfo.colorAttachmentCount = 1;
	renderingInfo.pColorAttachments = *attachmentInfo;

	vkCmdBeginRendering(cmd, *renderingInfo);
	ImGui_ImplVulkan_RenderDrawData(ImGui.GetDrawData(), cmd);
	vkCmdEndRendering(cmd);

	transition_image(cmd, s.swapchainImages[swapchain_image_index], .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR);

	vkEndCommandBuffer(cmd);

	cmd_info := command_buffer_submit_info(cmd);

	wait_info := semaphore_submit_info( VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR, gfx_device_get_current_frame(s).swapchainSemaphore);
	signal_info := semaphore_submit_info( VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT, gfx_device_get_current_frame(s).renderSempahore);

	submit := submit_info(*cmd_info, *signal_info, *wait_info);
	vkQueueSubmit2(s.graphicsQueue, 1, *submit, gfx_device_get_current_frame(s).renderFence);

	present_info := VkPresentInfoKHR.{
		pSwapchains = *s.swapchain,
		swapchainCount = 1,
		pWaitSemaphores = *gfx_device_get_current_frame(s).renderSempahore,
		waitSemaphoreCount = 1,
		pImageIndices = *swapchain_image_index
	};
	vkQueuePresentKHR(s.presentQueue, *present_info);
	s.frame_number += 1;
}

draw_geometry :: (cmd: VkCommandBuffer, s: *GfxDevice) {
	colorAttachment: VkRenderingAttachmentInfo;
	colorAttachment.imageView = s.drawImage.imageView;
	colorAttachment.imageLayout = .COLOR_ATTACHMENT_OPTIMAL;
	colorAttachment.loadOp = .LOAD;
	colorAttachment.storeOp = .STORE;
	depthAttachment: VkRenderingAttachmentInfo;
	depthAttachment.imageView = s.depthImage.imageView;
	depthAttachment.imageLayout = .DEPTH_ATTACHMENT_OPTIMAL;
	depthAttachment.loadOp = .CLEAR;
	depthAttachment.storeOp = .STORE;
	depthAttachment.clearValue.depthStencil.depth = 0;

	renderingInfo: VkRenderingInfo;
	renderingInfo.renderArea.extent = s.drawExtent;
	renderingInfo.layerCount = 1;
	renderingInfo.colorAttachmentCount = 1;
	renderingInfo.pColorAttachments = *colorAttachment;
	renderingInfo.pDepthAttachment = *depthAttachment;

	vkCmdBeginRendering(cmd, *renderingInfo);


	viewport: VkViewport;
	viewport.x = 0;
	viewport.y = 0;
	viewport.width = xx s.drawExtent.width;
	viewport.height = xx s.drawExtent.height;
	viewport.minDepth = 0.;
	viewport.maxDepth = 1.;

	vkCmdSetViewport(cmd, 0, 1, *viewport);

	scissor: VkRect2D;
	scissor.offset.x = 0;
	scissor.offset.y = 0;
	scissor.extent.width = s.drawExtent.width;
	scissor.extent.height = s.drawExtent.height;

	vkCmdSetScissor(cmd, 0, 1, *scissor);

	// draw triangle
	// vkCmdBindPipeline(cmd, .GRAPHICS, s.trianglePipeline);
	// vkCmdDraw(cmd, 3, 1, 0, 0);

	// draw mesh cube
	vkCmdBindPipeline(cmd, .GRAPHICS, s.meshPipeline);
	vkCmdBindDescriptorSets(cmd, .GRAPHICS, s.meshPipelineLayout, 0, 1, *s.textureDescriptorSet, 0, null);

	projection := make_projection_matrix(60.0 * PI / 180.0, cast(float)WIDTH/cast(float)HEIGHT, 1000.0, 0.01, 0.0, 0.0, true);
	projection._11 *= -1; // @todo eh?
	view := make_translation_matrix4(.{0.0, 0.0, -4.0});

	rotation: Quaternion;
	set_from_axis_and_angle(*rotation, .{0, 1, 0}, xx seconds_since_init() * 0.5);
	model := rotation_matrix(Matrix4, rotation);

	// beware, jai matrixes are row-major (designed for hlsl)
	pushConstants: GpuDrawPushConstants;
	pushConstants.worldMatrix = transpose(projection * view * model);
	pushConstants.vertexBuffer = s.cubeMesh.deviceAddress;

	vkCmdPushConstants(cmd, s.meshPipelineLayout, .VERTEX_BIT, 0, size_of(GpuDrawPushConstants), *pushConstants);
	vkCmdBindIndexBuffer(cmd, s.cubeMesh.indexBuffer.buffer, 0, .UINT32);

	vkCmdDrawIndexed(cmd, 36, 1, 0, 0, 0);

	vkCmdEndRendering(cmd);
}

logger :: (message: string, data: *void, info: Log_Info) {
	#if BUILD_TYPE == .RELEASE then return;
	if info.common_flags == .VERBOSE_ONLY && context.log_level != .VERBOSE then return;
	if info.common_flags == .VERY_VERBOSE_ONLY && context.log_level != .VERY_VERBOSE then return;

	color: Console_Color;
	if info.common_flags == .ERROR then color = .RED;
	if info.common_flags == .WARNING then color = .YELLOW;
	
	with_console_color(color, write_string(message));
}

// Return the length of s, a C-style zero-terminated string.
// If you pass in a pointer that is not zero-terminated, BAD things will happen!
strlen :: (s: *u8) -> s64 {  
    count: s64 = 0;

    while << s {
        count += 1;
        s += 1;
    }

    return count;
}

strcmp :: (s1: *u8, s2: *u8) -> s32 {
	while (<<s1 != #char "\0" && (<<s1 == <<s2)) 
	{
		s1 += 1; 
		s2 += 1;
	}
    return (<<s1 - <<s2);
}

