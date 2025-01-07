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
	init_graphics_device(*device, window, WIDTH, HEIGHT);

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
	vkWaitForFences(s.device, 1, *get_current_frame(s).renderFence, VK_TRUE, ONE_SECOND_IN_NS);
	vkResetFences(s.device, 1, *get_current_frame(s).renderFence);

	swapchain_image_index: u32;
	vkAcquireNextImageKHR(
		s.device, 
		s.swapchain, 
		ONE_SECOND_IN_NS, 
		get_current_frame(s).swapchainSemaphore, 
		null, 
		*swapchain_image_index
	);

	cmd_begin_info := VkCommandBufferBeginInfo.{
		flags = .ONE_TIME_SUBMIT_BIT
	};

	cmd := get_current_frame(s).mainCommandBuffer;
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

	wait_info := semaphore_submit_info( VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR, get_current_frame(s).swapchainSemaphore);
	signal_info := semaphore_submit_info( VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT, get_current_frame(s).renderSempahore);

	submit := submit_info(*cmd_info, *signal_info, *wait_info);
	vkQueueSubmit2(s.graphicsQueue, 1, *submit, get_current_frame(s).renderFence);

	present_info := VkPresentInfoKHR.{
		pSwapchains = *s.swapchain,
		swapchainCount = 1,
		pWaitSemaphores = *get_current_frame(s).renderSempahore,
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
