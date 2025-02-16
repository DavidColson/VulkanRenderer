
CommandBuffer :: struct {
	inUse: bool;
	device: *Device;

	// vulkan specific stuff
	platformHandle: VkCommandBuffer;
	commandPool: VkCommandPool;
	inFlightFence: VkFence;
	forPresent: bool;
	waitSemaphore: *VkSemaphore;
	signalSemaphore: *VkSemaphore;
	swapchainIndex: u32;
}

wait_and_acquire_swapchain_texture :: (cmdBuf: *CommandBuffer) -> Texture {
	// waitForFences on the current frame render fence (from the window)
	ONE_SECOND_IN_NS :: 1000000000;
	// wait for the fence for this swapchain (was signalled in a previous submit)
	frameIndex := cmdBuf.device.frameNumber % cmdBuf.device.nInFlightFrames;

	if cmdBuf.device.inFlightFences[frameIndex] != null {
		vkWaitForFences(cmdBuf.device.device, 1, cmdBuf.device.inFlightFences[frameIndex], VK_TRUE, ONE_SECOND_IN_NS);
		vkResetFences(cmdBuf.device.device, 1, cmdBuf.device.inFlightFences[frameIndex]);

		// unsure if this is really the best way to do this
		// we can't mark the command buffer as not in use right after submit cause submit may take some time
		// it must be after the fence has been waited on
		for * cmdBuf.device.commandBuffers {
			if it.inFlightFence == <<cmdBuf.device.inFlightFences[frameIndex] {
				it.inUse = false;
				it.forPresent = false;
			}
		}
	}

	vkAcquireNextImageKHR(
		cmdBuf.device.device, 
		cmdBuf.device.swapchain, 
		ONE_SECOND_IN_NS, 
		cmdBuf.device.swapchainSemaphores[frameIndex], 
		null, 
		*cmdBuf.swapchainIndex
	);

	cmdBuf.forPresent = true;

	cmdBuf.waitSemaphore = *cmdBuf.device.swapchainSemaphores[frameIndex];
	cmdBuf.signalSemaphore = *cmdBuf.device.renderSemaphores[frameIndex];

	swapchainTexture: Texture = .{
		platformHandle = cmdBuf.device.swapchainImages[frameIndex],
		imageViewHandle = cmdBuf.device.swapchainImageViews[frameIndex],
		size = .{
			width = xx cmdBuf.device.swapchainExtent.width,
			height = xx cmdBuf.device.swapchainExtent.height,
			depth = 1,
		},
		// @todo: fix
		// format = cmdBuf.device.swapchainImageFormat,
	};
	return swapchainTexture;
}

submit :: (cmdBuf: *CommandBuffer) {
	vkEndCommandBuffer(cmdBuf.platformHandle);

	if cmdBuf.forPresent {
		cmdInfo: VkCommandBufferSubmitInfo;
		cmdInfo.commandBuffer = cmdBuf.platformHandle;

		waitInfo: VkSemaphoreSubmitInfo;
		waitInfo.semaphore = <<cmdBuf.waitSemaphore;
		waitInfo.stageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR;
		waitInfo.value = 1;

		signalInfo: VkSemaphoreSubmitInfo;
		signalInfo.semaphore = <<cmdBuf.signalSemaphore;
		signalInfo.stageMask = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT;
		signalInfo.value = 1;

		submitInfo: VkSubmitInfo2;
		submitInfo.waitSemaphoreInfoCount = 1;
		submitInfo.pWaitSemaphoreInfos = *waitInfo;
		submitInfo.signalSemaphoreInfoCount = 1;
		submitInfo.pSignalSemaphoreInfos = *signalInfo;
		submitInfo.commandBufferInfoCount = 1;
		submitInfo.pCommandBufferInfos = *cmdInfo;

		result := vkQueueSubmit2(cmdBuf.device.graphicsQueue, 1, *submitInfo, cmdBuf.inFlightFence);
		assert(result == .SUCCESS, "Failed to submit immediate cmd buffer");

		presentInfo := VkPresentInfoKHR.{
			pSwapchains = *cmdBuf.device.swapchain,
			swapchainCount = 1,
			pWaitSemaphores = cmdBuf.signalSemaphore,
			waitSemaphoreCount = 1,
			pImageIndices = *cmdBuf.swapchainIndex
		};
		vkQueuePresentKHR(cmdBuf.device.presentQueue, *presentInfo);

		frameIndex := cmdBuf.device.frameNumber % cmdBuf.device.nInFlightFrames;
		cmdBuf.device.inFlightFences[frameIndex] = *cmdBuf.inFlightFence;
		cmdBuf.device.frameNumber += 1;
	}
	else {
		cmdInfo: VkCommandBufferSubmitInfo;
		cmdInfo.commandBuffer = cmdBuf.platformHandle;

		submitInfo: VkSubmitInfo2;
		submitInfo.waitSemaphoreInfoCount = 0;
		submitInfo.signalSemaphoreInfoCount = 0;
		submitInfo.commandBufferInfoCount = 1;
		submitInfo.pCommandBufferInfos = *cmdInfo;

		result := vkQueueSubmit2(cmdBuf.device.graphicsQueue, 1, *submitInfo, cmdBuf.inFlightFence);
		assert(result == .SUCCESS, "Failed to submit immediate cmd buffer");

		result = vkWaitForFences(cmdBuf.device.device, 1, *cmdBuf.inFlightFence, VK_TRUE, 999999999999999999);
		assert(result == .SUCCESS, "Wait For fences failed");
		result = vkResetFences(cmdBuf.device.device, 1, *cmdBuf.inFlightFence);
		assert(result == .SUCCESS, "Could not reset fence");

		cmdBuf.inUse = false;
		cmdBuf.forPresent = false;
	}
}

submit_command_buffer_and_acquire_fence :: (s: *Device) {
	// same as above but..
	// return the fence that was used in the queue submit function
}
