package main

import "vkb"
import "core:fmt"
import "vendor:glfw"
import "core:os"
import vk "vendor:vulkan"
import "base:runtime"

WIDTH :: 800
HEIGHT :: 600

State :: struct {
	window: glfw.WindowHandle,
	instance: ^vkb.Instance,
	surface: vk.SurfaceKHR,
	physical_device: ^vkb.Physical_Device,
	device: ^vkb.Device
}

General_Error :: enum {
	None,
	Vulkan_Error,
}

Error :: union #shared_nil {
	General_Error,
	vkb.Error,
}

init_vulkan :: proc(s: ^State) -> (err: Error) {

	// instance
	instance_builder := vkb.init_instance_builder() or_return
	defer vkb.destroy_instance_builder(&instance_builder)

	vkb.instance_set_minimum_version(&instance_builder, vk.API_VERSION_1_3)
	
	when ODIN_DEBUG {
		vkb.instance_request_validation_layers(&instance_builder)
		vkb.instance_use_default_debug_messenger(&instance_builder)
	}

	s.instance = vkb.build_instance(&instance_builder) or_return
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

	s.physical_device = vkb.select_physical_device(&selector) or_return
	defer if err != nil do vkb.destroy_physical_device(s.physical_device)

	// device
	device_builder := vkb.init_device_builder(s.physical_device) or_return
	defer vkb.destroy_device_builder(&device_builder)

	s.device = vkb.build_device(&device_builder) or_return

	return
}
  
init_swapchain :: proc(s: ^State) {
}

init_commands :: proc(s: ^State) {
}

init_sync_structures :: proc(s: ^State) {
}

init :: proc(s: ^State) {

	glfw.Init()

	glfw.WindowHint(glfw.RESIZABLE, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	s.window = glfw.CreateWindow(WIDTH, HEIGHT, "Renderer", nil, nil)

	init_vulkan(s);
	init_swapchain(s);
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
