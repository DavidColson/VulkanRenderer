package main

import "core:fmt"
import "vendor:glfw"
import "core:os"
import vk "vendor:vulkan"
import "base:runtime"

WIDTH :: 800
HEIGHT :: 600
VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}

debug_callback :: proc "stdcall" (messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr) -> b32 {
	context = runtime.default_context()
	fmt.printf("validation layer: %s\n", pCallbackData.pMessage)
	return false
}

main :: proc() {
	fmt.println("Hello World!")

	// Create window
	//////////////////////////////////////////////
	glfw.Init()

	glfw.WindowHint(glfw.RESIZABLE, 0)
	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)

	window := glfw.CreateWindow(WIDTH, HEIGHT, "Renderer", nil, nil)
	


	// create instance
	/////////////////////////////////////////////////
	instance: vk.Instance
	{
		// Load Vulkan functions
		context.user_ptr = &instance;
		get_proc_address :: proc(p: rawptr, name: cstring) 
		{
			(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress((^vk.Instance)(context.user_ptr)^, name);
		}
		vk.load_proc_addresses(get_proc_address);

		appInfo: vk.ApplicationInfo
		appInfo.sType = .APPLICATION_INFO
		appInfo.pApplicationName = "Renderer"
		appInfo.applicationVersion = vk.MAKE_VERSION(0, 0, 1)
		appInfo.pEngineName = "No Engine"
		appInfo.engineVersion = vk.MAKE_VERSION(1, 0, 0)
		appInfo.apiVersion = vk.API_VERSION_1_3

		createInfo: vk.InstanceCreateInfo
		createInfo.sType = .INSTANCE_CREATE_INFO
		createInfo.pApplicationInfo = &appInfo
		glfwExtensions := glfw.GetRequiredInstanceExtensions()

		// Add debug extensions
		extensions: [dynamic]cstring
		defer delete(extensions)
		append(&extensions, ..glfwExtensions[:])
		when ODIN_DEBUG
		{
			append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
		}

		createInfo.ppEnabledExtensionNames = raw_data(extensions)
		createInfo.enabledExtensionCount = cast(u32)len(extensions)

		// enable validation when on debug builds
		when ODIN_DEBUG
		{
			layerCount:u32
			vk.EnumerateInstanceLayerProperties(&layerCount, nil)
			availableLayers := make([]vk.LayerProperties, layerCount)
			vk.EnumerateInstanceLayerProperties(&layerCount, raw_data(availableLayers))

			outer: for name in &VALIDATION_LAYERS {
				for &layer in availableLayers {
					if name == cstring(&layer.layerName[0]) do continue outer
				}
				fmt.eprintf("Validation layers not available")
			os.exit(1)
			}
			createInfo.enabledLayerCount = len(VALIDATION_LAYERS)
			createInfo.ppEnabledLayerNames = &VALIDATION_LAYERS[0]

			debugMessengerCreateInfo: vk.DebugUtilsMessengerCreateInfoEXT
			debugMessengerCreateInfo.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
			debugMessengerCreateInfo.messageSeverity = { .VERBOSE, .INFO, .WARNING, .ERROR }
			debugMessengerCreateInfo.messageType = { .GENERAL, .VALIDATION, .PERFORMANCE }
			debugMessengerCreateInfo.pfnUserCallback = debug_callback
			debugMessengerCreateInfo.pUserData = nil

			// Will be given to create instance so we can get validation on instance creation
			createInfo.pNext = &debugMessengerCreateInfo
		}
		else
		{
			createInfo.enabledLayerCount = 0
		}

		if (vk.CreateInstance(&createInfo, nil, &instance) != .SUCCESS) {
			fmt.eprintf("Error: Failed to create instance\n")
			os.exit(1)
		}

		vk.load_proc_addresses(get_proc_address);

		// now we have an instance create a debug messenger
		when ODIN_DEBUG 
		{
			debugMessenger : vk.DebugUtilsMessengerEXT
			if vk.CreateDebugUtilsMessengerEXT(instance, &debugMessengerCreateInfo, nil, &debugMessenger) != .SUCCESS
			{
				fmt.eprintf("Error: Failed to create debug messenger\n")
			os.exit(1)
			}
		}
	}

	// Create surface and swapchain
	//////////////////////////////////////
	surface: vk.SurfaceKHR
	{
		if glfw.CreateWindowSurface(instance, window, nil, &surface) != .SUCCESS
		{
			fmt.eprintf("Error: Unable to create surface for Vulkan")
		}
	}

	// List available extensions
	fmt.println("Available Extensions:")
	numExtensions :u32
	vk.EnumerateInstanceExtensionProperties(nil, &numExtensions, nil)
	availableExtensions := make([]vk.ExtensionProperties, numExtensions)
	vk.EnumerateInstanceExtensionProperties(nil, &numExtensions, raw_data(availableExtensions))
	for &ext in availableExtensions 
	{
		fmt.println(cstring(&ext.extensionName[0]))
	}

	// Picking a physical device
	///////////////////////////////
	physicalDevice:	vk.PhysicalDevice
	{

		deviceCount: u32
		vk.EnumeratePhysicalDevices(instance, &deviceCount, nil)
		if (deviceCount == 0)
		{
			fmt.eprintf("Error: no devices with vulkan support found")
		}
		devices := make([]vk.PhysicalDevice, deviceCount)
		vk.EnumeratePhysicalDevices(instance, &deviceCount, raw_data(devices))

		for &device in devices
		{ 
			deviceProperties: vk.PhysicalDeviceProperties 
			deviceFeatures: vk.PhysicalDeviceFeatures
			vk.GetPhysicalDeviceProperties(device, &deviceProperties)
			vk.GetPhysicalDeviceFeatures(device, &deviceFeatures)

			if deviceProperties.deviceType == .DISCRETE_GPU && deviceFeatures.geometryShader
			{
				physicalDevice = device
				break
			}
		}
	}

	// Finding Queue Indices
	/////////////////////////////////
	QueueFamily :: enum
	{
		Graphics,
		Present
	}
	queueIndices: [QueueFamily]int
	for &q in queueIndices do q = -1

	{
		queueFamilyCount: u32
		vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, nil)
		queueFamilies := make([]vk.QueueFamilyProperties, queueFamilyCount)
		vk.GetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueFamilyCount, raw_data(queueFamilies))

		for queue, i in queueFamilies
		{
			presentSupport: b32
			vk.GetPhysicalDeviceSurfaceSupportKHR(physicalDevice, u32(i), surface, &presentSupport)
			if presentSupport && queueIndices[.Present] == -1 do queueIndices[.Present] = i

			if .GRAPHICS in queue.queueFlags && queueIndices[.Graphics] == -1 do queueIndices[.Graphics] = i
		}
	}

	// Create Logical Device and grab queue handles
	////////////////////////////////
	device: vk.Device
	graphicsQueue: vk.Queue
	presentQueue: vk.Queue

	{
		uniqueQueueIndices: map[int]b8
		defer delete(uniqueQueueIndices)
		for i in queueIndices do uniqueQueueIndices[i] = true

		queueCreateInfos: [dynamic]vk.DeviceQueueCreateInfo
		defer delete(queueCreateInfos)
		for k, _ in uniqueQueueIndices
		{
			queueCreateInfo: vk.DeviceQueueCreateInfo
			queueCreateInfo.sType = .DEVICE_QUEUE_CREATE_INFO
			queueCreateInfo.queueFamilyIndex = cast(u32)k
			queueCreateInfo.queueCount = 1
			queuePriority:f32 = 1.0
			queueCreateInfo.pQueuePriorities = &queuePriority
			append(&queueCreateInfos, queueCreateInfo)
		}

		deviceFeatures: vk.PhysicalDeviceFeatures

		createInfo: vk.DeviceCreateInfo
		createInfo.sType = .DEVICE_CREATE_INFO
		createInfo.pQueueCreateInfos = raw_data(queueCreateInfos)
		createInfo.queueCreateInfoCount = cast(u32)len(queueCreateInfos)
		createInfo.pEnabledFeatures = &deviceFeatures

		if vk.CreateDevice(physicalDevice, &createInfo, nil, &device) != .SUCCESS
		{
			fmt.eprintf("Error: Failed to create logical device for vulkan")
			os.exit(1)
		}
		vk.GetDeviceQueue(device, cast(u32)queueIndices[.Graphics], 0, &graphicsQueue)
		vk.GetDeviceQueue(device, cast(u32)queueIndices[.Present], 0, &presentQueue)
	}

	for !glfw.WindowShouldClose(window)
	{
		glfw.PollEvents()
	}

	vk.DestroyInstance(instance, nil)

}
