package main

import "vkb"
import "core:fmt"
import "vendor:glfw"
import "core:os"
import vk "vendor:vulkan"
import "base:runtime"

WIDTH :: 800
HEIGHT :: 600

FrameData :: struct {
	commandPool: vk.CommandPool,
	mainCommandBuffer: vk.CommandBuffer
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

get_current_frame :: proc(s: ^State) -> FrameData {
	return s.frames[s.frameNumber]
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

init_sync_structures :: proc(s: ^State) {
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

main :: proc() {
	fmt.println("Hello World!")

	state: State;

	init(&state);	

	for !glfw.WindowShouldClose(state.window)
	{
		glfw.PollEvents()
	}
}
