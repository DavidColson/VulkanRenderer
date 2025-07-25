
CommandBuffer :: struct {
	inUse: bool;
	dev: *Device;
	currentPipeline: Pipeline;

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

barrier :: (cmd: *CommandBuffer, textureBarriers: []TextureBarrier) {
	imageBarriers: [..]VkImageMemoryBarrier2;
	imageBarriers.allocator = temp;

	for textureBarriers {
		imageBarrier: VkImageMemoryBarrier2;

		imageBarrier.srcStageMask = 0;
		imageBarrier.srcAccessMask = 0 ;
		imageBarrier.dstStageMask = 0;
		imageBarrier.dstAccessMask = 0;
		imageBarrier.oldLayout = .UNDEFINED;
		imageBarrier.newLayout = .UNDEFINED;
		imageBarrier.image = it.texture.platformHandle;

		texture_usage_to_barrier(it.prevUsage, it.texture.format, *imageBarrier.srcStageMask, *imageBarrier.srcAccessMask, *imageBarrier.oldLayout);
		texture_usage_to_barrier(it.nextUsage, it.texture.format, *imageBarrier.dstStageMask, *imageBarrier.dstAccessMask, *imageBarrier.newLayout);

		subresourceRange: VkImageSubresourceRange;
		subresourceRange.aspectMask = ifx imageBarrier.newLayout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL then .DEPTH_BIT else .COLOR_BIT;;
		subresourceRange.levelCount = 1;
		subresourceRange.layerCount = 1;
		imageBarrier.subresourceRange = subresourceRange;

		array_add(*imageBarriers, imageBarrier);
	}

    dep_info: VkDependencyInfo;
    dep_info.sType = .DEPENDENCY_INFO;
    dep_info.imageMemoryBarrierCount = xx imageBarriers.count;
    dep_info.pImageMemoryBarriers = imageBarriers.data;
    
    vkCmdPipelineBarrier2(cmd.platformHandle, *dep_info);
}

marker_start :: (cmd: *CommandBuffer, label: string) {
	labelInfo: VkDebugUtilsLabelEXT;
	labelInfo.pLabelName = label.data;

	vkCmdBeginDebugUtilsLabelEXT(cmd.dev.instance, cmd.platformHandle, *labelInfo);
}

marker_end :: (cmd: *CommandBuffer) {
	vkCmdEndDebugUtilsLabelEXT(cmd.dev.instance, cmd.platformHandle);
}

set_pipeline :: (cmd: *CommandBuffer, bindPoint: BindPoint, pipeline: Pipeline) {
	cmd.currentPipeline = pipeline;
	vkCmdBindPipeline(cmd.platformHandle, to_vk(bindPoint), pipeline.platformHandle);
}

set_bind_group :: (cmd: *CommandBuffer, bindPoint: BindPoint, set: u32, bindGroup: BindGroup) {
	vkCmdBindDescriptorSets(cmd.platformHandle, to_vk(bindPoint), cmd.currentPipeline.pipelineLayout, set, 1, *bindGroup.platformHandle, 0, null);
}

set_bindless_pool :: (cmd: *CommandBuffer, bindPoint: BindPoint, set: u32, bindlessPool: BindlessPool) {
	vkCmdBindDescriptorSets(cmd.platformHandle, to_vk(bindPoint), cmd.currentPipeline.pipelineLayout, set, 1, *bindlessPool.descriptorSet, 0, null);
}

set_index_buffer :: (cmd: *CommandBuffer, buffer: Buffer, elementSizeBytes: s32) {
	if (elementSizeBytes == 32) {
		vkCmdBindIndexBuffer(cmd.platformHandle, buffer.buffer, 0, .UINT32);
	}
	else if (elementSizeBytes == 16) {
		vkCmdBindIndexBuffer(cmd.platformHandle, buffer.buffer, 0, .UINT16);
	}
	else {
		assert(false, "Only support 16 or 32 bit index buffers");
	}
}

set_push_constants :: (cmd: *CommandBuffer, stage: ShaderStage, offset: u32, size: u32, data: *void) {
	vkCmdPushConstants(cmd.platformHandle, cmd.currentPipeline.pipelineLayout, shader_stage_to_vk(stage), offset, size, data);
}

draw_indexed :: (cmd: *CommandBuffer, indexCount: u32, instanceCount: u32, firstIndex: u32, vertexOffset: u32, firstInstance: u32) {
	vkCmdDrawIndexed(cmd.platformHandle, indexCount, instanceCount, firstIndex, xx vertexOffset, firstInstance);
}

dispatch :: (cmd: *CommandBuffer, x: u32, y: u32, z: u32) {
	vkCmdDispatch(cmd.platformHandle, x, y, z);
}

set_viewport :: (cmd: *CommandBuffer, opts: Viewport) {
	viewport: VkViewport;
	viewport.x = opts.x;
	viewport.y = opts.y;
	viewport.width = opts.width;
	viewport.height = opts.height;
	viewport.minDepth = opts.minDepth;
	viewport.maxDepth = opts.maxDepth;
	vkCmdSetViewport(cmd.platformHandle, 0, 1, *viewport);
}

set_scissor :: (cmd: *CommandBuffer, opts: Rect) {
	scissor: VkRect2D;
	scissor.offset.x = opts.x;
	scissor.offset.y = opts.y;
	scissor.extent.width = xx opts.width;
	scissor.extent.height = xx opts.height;
	vkCmdSetScissor(cmd.platformHandle, 0, 1, *scissor);
}

copy_image_to_image :: (cmd: *CommandBuffer, opts: CopyImageInfo) {
	blitRegion: VkImageBlit2;
	blitRegion.srcOffsets[0].x = xx opts.srcRect.x;
	blitRegion.srcOffsets[0].y = xx opts.srcRect.y;
	blitRegion.srcOffsets[0].z = 0;
	blitRegion.srcOffsets[1].x = xx opts.srcRect.width;
	blitRegion.srcOffsets[1].y = xx opts.srcRect.height;
	blitRegion.srcOffsets[1].z = 1;

	blitRegion.dstOffsets[0].x = xx opts.srcRect.x;
	blitRegion.dstOffsets[0].y = xx opts.srcRect.y;
	blitRegion.dstOffsets[0].z = 0;
	blitRegion.dstOffsets[1].x = xx opts.srcRect.width;
	blitRegion.dstOffsets[1].y = xx opts.srcRect.height;
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
	blitInfo.dstImage = opts.dst.platformHandle;
	blitInfo.dstImageLayout = .TRANSFER_DST_OPTIMAL;
	blitInfo.srcImage = opts.src.platformHandle;
	blitInfo.srcImageLayout = .TRANSFER_SRC_OPTIMAL;
	blitInfo.filter = .LINEAR;
	blitInfo.regionCount = 1;
	blitInfo.pRegions = *blitRegion;

	vkCmdBlitImage2(cmd.platformHandle, *blitInfo);
}

copy_buffer_to_buffer :: (cmd: *CommandBuffer, opts: CopyBufferInfo) {
	copy: VkBufferCopy;
	copy.dstOffset = xx opts.dstOffset;
	copy.srcOffset = xx opts.srcOffset;
	copy.size = xx opts.size;
	vkCmdCopyBuffer(cmd.platformHandle, opts.src.buffer, opts.dst.buffer, 1, *copy);
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

to_vk :: (bindpoint: BindPoint) -> VkPipelineBindPoint {
	if bindpoint == {
		case .GRAPHICS; return .GRAPHICS; 
		case .COMPUTE; return .COMPUTE; 
		case; return .GRAPHICS;
	}
}

#scope_file

texture_usage_to_barrier :: (usage: TextureUsage, textureFormat: PixelFormat, stage: *VkPipelineStageFlags2, access: *VkAccessFlags2, layout: *VkImageLayout) {
	if usage & .READ_GEOMETRY {
		stage |= VkPipelineStageFlagBits.VERTEX_SHADER_BIT | .GEOMETRY_SHADER_BIT | .TESSELLATION_CONTROL_SHADER_BIT | .TESSELLATION_EVALUATION_SHADER_BIT;
		access |= VkAccessFlagBits.SHADER_READ_BIT;
		<<layout = .SHADER_READ_ONLY_OPTIMAL;
	}
	if usage & .READ_WRITE_GEOMETRY {
		stage |= VkPipelineStageFlagBits.VERTEX_SHADER_BIT | .GEOMETRY_SHADER_BIT | .TESSELLATION_CONTROL_SHADER_BIT | .TESSELLATION_EVALUATION_SHADER_BIT;
		access |= VkAccessFlagBits.SHADER_WRITE_BIT;
		<<layout = .GENERAL;
	}
	if usage & .READ_PIXEL {
		stage |= VkPipelineStageFlagBits.FRAGMENT_SHADER_BIT;
		access |= VkAccessFlagBits.SHADER_READ_BIT;
		<<layout = .SHADER_READ_ONLY_OPTIMAL;
	}
	if usage & .READ_WRITE_PIXEL {
		stage |= VkPipelineStageFlagBits.FRAGMENT_SHADER_BIT;
		access |= VkAccessFlagBits.SHADER_WRITE_BIT;
		<<layout = .GENERAL;
	}
	if usage & .READ_COMPUTE {
		stage |= VkPipelineStageFlagBits.COMPUTE_SHADER_BIT;
		access |= VkAccessFlagBits.SHADER_READ_BIT;
		<<layout = .SHADER_READ_ONLY_OPTIMAL;
	}
	if usage & .READ_WRITE_COMPUTE {
		stage |= VkPipelineStageFlagBits.COMPUTE_SHADER_BIT;
		access |= VkAccessFlagBits.SHADER_WRITE_BIT;
		<<layout = .GENERAL;
	}
	if usage & .READ_RENDER_TARGET {
		if textureFormat == .DEPTH {
			stage |= VkPipelineStageFlagBits.EARLY_FRAGMENT_TESTS_BIT | .LATE_FRAGMENT_TESTS_BIT;
			access |= VkAccessFlagBits.DEPTH_STENCIL_ATTACHMENT_READ_BIT;
			<<layout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL;
		}
		else {
			stage |= VkPipelineStageFlagBits.COLOR_ATTACHMENT_OUTPUT_BIT;
			access |= VkAccessFlagBits.COLOR_ATTACHMENT_READ_BIT;
			<<layout = .COLOR_ATTACHMENT_OPTIMAL;
		}
	}
	if usage & .WRITE_RENDER_TARGET {
		if textureFormat == .DEPTH {
			stage |= VkPipelineStageFlagBits.EARLY_FRAGMENT_TESTS_BIT | .LATE_FRAGMENT_TESTS_BIT;
			access |= VkAccessFlagBits.DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
			<<layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
		}
		else {
			stage |= VkPipelineStageFlagBits.COLOR_ATTACHMENT_OUTPUT_BIT;
			access |= VkAccessFlagBits.COLOR_ATTACHMENT_WRITE_BIT;
			<<layout = .COLOR_ATTACHMENT_OPTIMAL;
		}
	}
	if usage & .COPY_SRC {
		stage |= VkPipelineStageFlagBits.TRANSFER_BIT;
		access |= VkAccessFlagBits.TRANSFER_READ_BIT;
		<<layout = .TRANSFER_SRC_OPTIMAL;
	}
	if usage & .COPY_DST {
		stage |= VkPipelineStageFlagBits.TRANSFER_BIT;
		access |= VkAccessFlagBits.TRANSFER_WRITE_BIT;
		<<layout = .TRANSFER_DST_OPTIMAL;
	}
	if usage & .PRESENT {
		stage |= VkPipelineStageFlagBits.BOTTOM_OF_PIPE_BIT;
		access |= VkAccessFlagBits.MEMORY_READ_BIT;
		<<layout = .PRESENT_SRC_KHR;
	}
}

vkCmdBeginDebugUtilsLabelEXT :: (instance: VkInstance, cmd: VkCommandBuffer, pLabelInfo: *VkDebugUtilsLabelEXT) {
	func := cast(PFN_vkCmdBeginDebugUtilsLabelEXT) vkGetInstanceProcAddr(instance, "vkCmdBeginDebugUtilsLabelEXT");
	if func != null then func(cmd, pLabelInfo);
}

vkCmdInsertDebugUtilsLabelEXT :: (instance: VkInstance, cmd: VkCommandBuffer, pLabelInfo: *VkDebugUtilsLabelEXT) {
	func := cast(PFN_vkCmdInsertDebugUtilsLabelEXT) vkGetInstanceProcAddr(instance, "vkCmdInsertDebugUtilsLabelEXT");
	if func != null then func(cmd, pLabelInfo);
}

vkCmdEndDebugUtilsLabelEXT :: (instance: VkInstance, cmd: VkCommandBuffer) {
	func := cast(PFN_vkCmdEndDebugUtilsLabelEXT) vkGetInstanceProcAddr(instance, "vkCmdEndDebugUtilsLabelEXT");
	if func != null then func(cmd);
}
