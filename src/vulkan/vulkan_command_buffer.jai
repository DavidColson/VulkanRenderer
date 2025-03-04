
CommandBuffer :: struct {
	inUse: bool;
	dev: *Device;

	// vulkan specific stuff
	platformHandle: VkCommandBuffer;
	commandPool: VkCommandPool;
	inFlightFence: VkFence;
	forPresent: bool;
	waitSemaphore: *VkSemaphore;
	signalSemaphore: *VkSemaphore;
	swapchainIndex: u32;
}

wait_and_acquire_swapchain_texture :: (cmd: *CommandBuffer) -> Texture {
	// waitForFences on the current frame render fence (from the window)
	ONE_SECOND_IN_NS :: 1000000000;
	// wait for the fence for this swapchain (was signalled in a previous submit)
	frameIndex := cmd.dev.frameNumber % cmd.dev.nInFlightFrames;

	if cmd.dev.inFlightFences[frameIndex] != null {
		vkWaitForFences(cmd.dev.vkDevice, 1, cmd.dev.inFlightFences[frameIndex], VK_TRUE, ONE_SECOND_IN_NS);
		vkResetFences(cmd.dev.vkDevice, 1, cmd.dev.inFlightFences[frameIndex]);

		// unsure if this is really the best way to do this
		// we can't mark the command buffer as not in use right after submit cause submit may take some time
		// it must be after the fence has been waited on
		for * cmd.dev.commandBuffers {
			if it.inFlightFence == <<cmd.dev.inFlightFences[frameIndex] {
				it.inUse = false;
				it.forPresent = false;
			}
		}
	}

	vkAcquireNextImageKHR(
		cmd.dev.vkDevice, 
		cmd.dev.swapchain, 
		ONE_SECOND_IN_NS, 
		cmd.dev.swapchainSemaphores[frameIndex], 
		null, 
		*cmd.swapchainIndex
	);

	cmd.forPresent = true;

	cmd.waitSemaphore = *cmd.dev.swapchainSemaphores[frameIndex];
	cmd.signalSemaphore = *cmd.dev.renderSemaphores[frameIndex];

	swapchainTexture: Texture = .{
		platformHandle = cmd.dev.swapchainImages[frameIndex],
		imageViewHandle = cmd.dev.swapchainImageViews[frameIndex],
		size = .{
			width = xx cmd.dev.swapchainExtent.width,
			height = xx cmd.dev.swapchainExtent.height,
			depth = 1,
		},
		// @todo: fix
		// format = cmd.dev.swapchainImageFormat,
	};
	return swapchainTexture;
}

submit :: (cmd: *CommandBuffer) {
	vkEndCommandBuffer(cmd.platformHandle);

	if cmd.forPresent {
		cmdInfo: VkCommandBufferSubmitInfo;
		cmdInfo.commandBuffer = cmd.platformHandle;

		waitInfo: VkSemaphoreSubmitInfo;
		waitInfo.semaphore = <<cmd.waitSemaphore;
		waitInfo.stageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR;
		waitInfo.value = 1;

		signalInfo: VkSemaphoreSubmitInfo;
		signalInfo.semaphore = <<cmd.signalSemaphore;
		signalInfo.stageMask = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT;
		signalInfo.value = 1;

		submitInfo: VkSubmitInfo2;
		submitInfo.waitSemaphoreInfoCount = 1;
		submitInfo.pWaitSemaphoreInfos = *waitInfo;
		submitInfo.signalSemaphoreInfoCount = 1;
		submitInfo.pSignalSemaphoreInfos = *signalInfo;
		submitInfo.commandBufferInfoCount = 1;
		submitInfo.pCommandBufferInfos = *cmdInfo;

		result := vkQueueSubmit2(cmd.dev.graphicsQueue, 1, *submitInfo, cmd.inFlightFence);
		assert(result == .SUCCESS, "Failed to submit immediate cmd buffer");

		presentInfo := VkPresentInfoKHR.{
			pSwapchains = *cmd.dev.swapchain,
			swapchainCount = 1,
			pWaitSemaphores = cmd.signalSemaphore,
			waitSemaphoreCount = 1,
			pImageIndices = *cmd.swapchainIndex
		};
		vkQueuePresentKHR(cmd.dev.presentQueue, *presentInfo);

		frameIndex := cmd.dev.frameNumber % cmd.dev.nInFlightFrames;
		cmd.dev.inFlightFences[frameIndex] = *cmd.inFlightFence;
		cmd.dev.frameNumber += 1;
	}
	else {
		cmdInfo: VkCommandBufferSubmitInfo;
		cmdInfo.commandBuffer = cmd.platformHandle;

		submitInfo: VkSubmitInfo2;
		submitInfo.waitSemaphoreInfoCount = 0;
		submitInfo.signalSemaphoreInfoCount = 0;
		submitInfo.commandBufferInfoCount = 1;
		submitInfo.pCommandBufferInfos = *cmdInfo;

		result := vkQueueSubmit2(cmd.dev.graphicsQueue, 1, *submitInfo, cmd.inFlightFence);
		assert(result == .SUCCESS, "Failed to submit immediate cmd buffer");

		result = vkWaitForFences(cmd.dev.vkDevice, 1, *cmd.inFlightFence, VK_TRUE, 999999999999999999);
		assert(result == .SUCCESS, "Wait For fences failed");
		result = vkResetFences(cmd.dev.vkDevice, 1, *cmd.inFlightFence);
		assert(result == .SUCCESS, "Could not reset fence");

		cmd.inUse = false;
		cmd.forPresent = false;
	}
}

begin_rendering :: (cmd: *CommandBuffer, info: RenderingInfo) {
	// 8 max attachments, seems fine?
	colorAttachments: [8]VkRenderingAttachmentInfo;
	for * info.colorAttachments {
		colorAttachments[it_index].imageView = it.image.imageViewHandle;
		colorAttachments[it_index].imageLayout = .COLOR_ATTACHMENT_OPTIMAL; // assumed, maybe error?
		colorAttachments[it_index].loadOp = to_vk(it.loadOp);
		colorAttachments[it_index].storeOp = to_vk(it.storeOp);
		colorAttachments[it_index].clearValue.color = .{_float32 = .[it.clear.color.x, it.clear.color.y, it.clear.color.z, it.clear.color.w]};
	}

	depthAttachment: VkRenderingAttachmentInfo;
	depthAttachment.imageView = info.depthAttachment.image.imageViewHandle;
	depthAttachment.imageLayout = .DEPTH_ATTACHMENT_OPTIMAL;
	depthAttachment.loadOp = to_vk(info.depthAttachment.loadOp);
	depthAttachment.storeOp = to_vk(info.depthAttachment.storeOp);
	depthAttachment.clearValue.depthStencil.depth = info.depthAttachment.clear.depth;

	renderingInfo: VkRenderingInfo;
	renderingInfo.renderArea.offset = .{info.renderArea.x, info.renderArea.y};
	renderingInfo.renderArea.extent = .{xx info.renderArea.width, xx info.renderArea.height};
	renderingInfo.layerCount = 1;
	renderingInfo.colorAttachmentCount = xx info.colorAttachments.count;
	renderingInfo.pColorAttachments = colorAttachments.data;
	renderingInfo.pDepthAttachment = *depthAttachment;

	vkCmdBeginRendering(cmd.platformHandle, *renderingInfo);
}

end_rendering :: (cmd: *CommandBuffer) {
	vkCmdEndRendering(cmd.platformHandle);
}

to_vk :: (loadop: RenderAttachmentLoadOp) -> VkAttachmentLoadOp {
	if loadop == {
		case .LOAD; return .LOAD; 
		case .CLEAR; return .CLEAR; 
		case .DONTCARE; return .DONT_CARE; 
		case; return .DONT_CARE;
	}
}

to_vk :: (storeop: RenderAttachmentStoreOp) -> VkAttachmentStoreOp {
	if storeop == {
		case .STORE; return .STORE; 
		case .DONTCARE; return .DONT_CARE; 
		case; return .DONT_CARE;
	}
}
