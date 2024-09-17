package main

import "vkb"
import "core:fmt"
import "vendor:glfw"
import "core:os"
import vk "vendor:vulkan"
import "base:runtime"
import "core:math"

WIDTH :: 800
HEIGHT :: 600

FrameData :: struct {
	commandPool: vk.CommandPool,
	mainCommandBuffer: vk.CommandBuffer,
	renderFence: vk.Fence,
	swapchainSemaphore: vk.Semaphore,
	renderSemaphore: vk.Semaphore
}

FRAMES_OVERLAP :: 2

State :: struct {
	window: glfw.WindowHandle,
	instance: ^vkb.Instance,
	surface: vk.SurfaceKHR,
	physicalDevice: ^vkb.Physical_Device,
	device: ^vkb.Device,
	swapchain: ^vkb.Swapchain,
	graphicsQueue: vk.Queue,
	graphicsQueueFamily: u32,
	swapchainImages: []vk.Image,
	swapchainImageViews: []vk.ImageView,

	frames: [FRAMES_OVERLAP]FrameData,
	frameNumber: u32
}

General_Error :: enum {
	None,
	Vulkan_Error,
}

Error :: union #shared_nil {
	General_Error,
	vkb.Error,
}

get_current_frame :: proc(s: ^State) -> ^FrameData {
	return &s.frames[s.frameNumber]
}

init_vulkan :: proc(s: ^State) -> (err: Error) {

	// instance
	instanceBuilder := vkb.init_instance_builder() or_return
	defer vkb.destroy_instance_builder(&instanceBuilder)

	vkb.instance_set_minimum_version(&instanceBuilder, vk.API_VERSION_1_3)
	
	when ODIN_DEBUG {
		vkb.instance_request_validation_layers(&instanceBuilder)
		vkb.instance_use_default_debug_messenger(&instanceBuilder)
	}

	s.instance = vkb.build_instance(&instanceBuilder) or_return
	defer if err != nil do vkb.destroy_instance(s.instance)

	// surface
	if glfw.CreateWindowSurface(s.instance.ptr, s.window, nil, &s.surface) != .SUCCESS {
		fmt.eprintf("Error: Unable to create surface for Vulkan")
	}

	// physical device
	features: vk.PhysicalDeviceVulkan13Features
	features.sType = .PHYSICAL_DEVICE_VULKAN_1_3_FEATURES;
	features.dynamicRendering = true
	features.synchronization2 = true

	features12: vk.PhysicalDeviceVulkan12Features
	features12.sType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
	features12.bufferDeviceAddress = true
	features12.descriptorIndexing = true

	selector := vkb.init_physical_device_selector(s.instance) or_return
	defer vkb.destroy_physical_device_selector(&selector)

	vkb.selector_set_minimum_version(&selector, vk.API_VERSION_1_3)
	vkb.selector_set_required_features_13(&selector, features)
	vkb.selector_set_required_features_12(&selector, features12)
	vkb.selector_set_surface(&selector, s.surface)

	s.physicalDevice = vkb.select_physical_device(&selector) or_return
	defer if err != nil do vkb.destroy_physical_device(s.physicalDevice)

	// device
	deviceBuilder := vkb.init_device_builder(s.physicalDevice) or_return
	defer vkb.destroy_device_builder(&deviceBuilder)

	s.device = vkb.build_device(&deviceBuilder) or_return

	s.graphicsQueue = vkb.device_get_queue(s.device, .Graphics) or_return
	s.graphicsQueueFamily = vkb.device_get_queue_index(s.device, .Graphics) or_return
	return
}
  
init_swapchain :: proc(s: ^State, width, height: u32) -> (err: Error) {
	builder := vkb.init_swapchain_builder(s.device) or_return
	defer vkb.destroy_swapchain_builder(&builder)

	vkb.swapchain_builder_set_old_swapchain(&builder, s.swapchain)
	vkb.swapchain_builder_set_desired_extent(&builder, width, height)
	vkb.swapchain_builder_use_default_format_selection(&builder)
	vkb.swapchain_builder_set_present_mode(&builder, .FIFO)
	vkb.swapchain_builder_add_image_usage_flags(&builder, {.TRANSFER_DST})

	swapchain := vkb.build_swapchain(&builder) or_return
	vkb.destroy_swapchain(s.swapchain)
	s.swapchain = swapchain
	
	s.swapchainImages = vkb.swapchain_get_images(s.swapchain) or_return
	s.swapchainImageViews = vkb.swapchain_get_image_views(s.swapchain) or_return
	return
}

init_commands :: proc(s: ^State) -> (err: Error) {
	createInfo := vk.CommandPoolCreateInfo {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = s.graphicsQueueFamily
	}

	for i := 0; i < FRAMES_OVERLAP; i+=1 {
		if res := vk.CreateCommandPool(s.device.ptr, &createInfo, nil, &s.frames[i].commandPool); res != .SUCCESS {
			return .Vulkan_Error
		}

		allocateInfo := vk.CommandBufferAllocateInfo {
			sType = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool = s.frames[i].commandPool,
			commandBufferCount = 1,
			level = .PRIMARY
		}
		if res := vk.AllocateCommandBuffers(s.device.ptr, &allocateInfo, &s.frames[i].mainCommandBuffer, ); res != .SUCCESS {
			return .Vulkan_Error
		}
	}
	return
}

init_sync_structures :: proc(s: ^State) -> (err: Error) {
	fenceCreateInfo := vk.FenceCreateInfo { sType = .FENCE_CREATE_INFO, flags = {.SIGNALED} }
	semaphoreCreateInfo := vk.SemaphoreCreateInfo { sType = .SEMAPHORE_CREATE_INFO }

	for i := 0; i < FRAMES_OVERLAP; i+=1 {
		if res := vk.CreateFence(s.device.ptr, &fenceCreateInfo, nil, &s.frames[i].renderFence); res != .SUCCESS {
			return .Vulkan_Error
		}

		if res := vk.CreateSemaphore(s.device.ptr, &semaphoreCreateInfo, nil, &s.frames[i].swapchainSemaphore); res != .SUCCESS {
			return .Vulkan_Error
		}
		if res := vk.CreateSemaphore(s.device.ptr, &semaphoreCreateInfo, nil, &s.frames[i].renderSemaphore); res != .SUCCESS {
			return .Vulkan_Error
		}
	}
	return
}

init :: proc(s: ^State) {

	glfw.Init()

	glfw.WindowHint(glfw.RESIZABLE, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	s.window = glfw.CreateWindow(WIDTH, HEIGHT, "Renderer", nil, nil)

	init_vulkan(s);
	init_swapchain(s, WIDTH, HEIGHT);
	init_commands(s);
	init_sync_structures(s);
}

image_subresource_range :: proc(aspectMask: vk.ImageAspectFlags) -> vk.ImageSubresourceRange {
	subImage: vk.ImageSubresourceRange
	subImage.aspectMask = aspectMask
	subImage.baseMipLevel = 0
	subImage.levelCount = vk.REMAINING_MIP_LEVELS
	subImage.baseArrayLayer = 0
	subImage.layerCount = vk.REMAINING_ARRAY_LAYERS	

	return subImage
}

transition_image :: proc(cmd: vk.CommandBuffer, image: vk.Image, currentLayout: vk.ImageLayout, newLayout: vk.ImageLayout) {
	imageBarrier := vk.ImageMemoryBarrier2 { sType = .IMAGE_MEMORY_BARRIER }
	imageBarrier.pNext = nil
 
	imageBarrier.srcStageMask = {.ALL_COMMANDS }
	imageBarrier.srcAccessMask = { .MEMORY_WRITE }
	imageBarrier.dstStageMask = { .ALL_COMMANDS }
	imageBarrier.dstAccessMask = { .MEMORY_WRITE, .MEMORY_READ }

	imageBarrier.oldLayout = currentLayout
	imageBarrier.newLayout = newLayout

	aspectMask: vk.ImageAspectFlags = newLayout == .DEPTH_ATTACHMENT_OPTIMAL ? {.DEPTH} : {.COLOR}
	imageBarrier.subresourceRange =	image_subresource_range(aspectMask) 
	imageBarrier.image = image

	depInfo: vk.DependencyInfo
	depInfo.sType = .DEPENDENCY_INFO
	depInfo.pNext = nil

	depInfo.imageMemoryBarrierCount = 1
	depInfo.pImageMemoryBarriers = &imageBarrier

	vk.CmdPipelineBarrier2(cmd, &depInfo)
}

draw :: proc(s: ^State) -> (err: Error) {
	vk.WaitForFences(s.device.ptr, 1, &get_current_frame(s).renderFence, true, 1000000000)
	vk.ResetFences(s.device.ptr, 1, &get_current_frame(s).renderFence)

	swapchainImageIndex: u32 = 0
	if res := vk.AcquireNextImageKHR(
		s.device.ptr, s.swapchain.ptr, 1000000000, get_current_frame(s).swapchainSemaphore,  
		0, &swapchainImageIndex); res != .SUCCESS {
		return .Vulkan_Error
	}

	beginInfo := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT}
	}

	cmd := get_current_frame(s).mainCommandBuffer 

	vk.ResetCommandBuffer(cmd, {})

	if res := vk.BeginCommandBuffer(cmd, &beginInfo); res != .SUCCESS {
		return .Vulkan_Error
	}

	transition_image(cmd, s.swapchainImages[swapchainImageIndex], .UNDEFINED, .GENERAL)

	clearValue: vk.ClearColorValue
	flash:f32 =  abs(math.sin(cast(f32)s.frameNumber / 120.0))
	clearValue = { float32 = { 0.0, 0.0, flash, 1.0 } }
	
	clearRange: vk.ImageSubresourceRange = image_subresource_range({.COLOR})

	vk.CmdClearColorImage(cmd, s.swapchainImages[swapchainImageIndex], .GENERAL, &clearValue, 1, &clearRange)

	transition_image(cmd, s.swapchainImages[swapchainImageIndex], .GENERAL, .PRESENT_SRC_KHR)

	if res := vk.EndCommandBuffer(cmd); res != .SUCCESS {
		return .Vulkan_Error
	}

	// TODO: Dave next step is to actually do the vk.queuesubmit, and the submit info stuff
	return
}

main :: proc() {
	fmt.println("Hello World!")

	state: State;

	init(&state);	

	for !glfw.WindowShouldClose(state.window)
	{
		glfw.PollEvents()

	}
}
