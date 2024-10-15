#import "Basic"()(MEMORY_DEBUGGER = BUILD_TYPE != .RELEASE, ENABLE_ASSERT = BUILD_TYPE != .RELEASE);

#import "SDL"(VULKAN = true);
#import "vulkan";
#import "vma";
#import "Print_Color";
#import "String";
#import "Math";

VALIDATION_ENABLED :: BUILD_TYPE != .RELEASE;
REQUIRED_VALIDATION_LAYERS :: (*u8).["VK_LAYER_KHRONOS_validation"];

WIDTH :: 800;
HEIGHT :: 600;

FrameData :: struct
{
	commandPool: VkCommandPool;
	mainCommandBuffer: VkCommandBuffer;
	swapchainSemaphore: VkSemaphore;
	renderSempahore: VkSemaphore;
	renderFence: VkFence;
}

AllocatedImage :: struct {
	image: VkImage;
	imageView: VkImageView;
	allocation: VmaAllocation;
	imageExtent: VkExtent3D;
	imageFormat: VkFormat;
}

FRAMES_OVERLAP :: 2;

State :: struct {
	window: *SDL_Window;

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

	gpuAllocator: VmaAllocator;

	drawImage: AllocatedImage;
	drawExtent: VkExtent2D;
	frames: [..] FrameData;
	frame_number: int;
}

BuildType :: enum u8
{
	DEBUG;
	OPTIMIZED;
	RELEASE;
}

main :: () {
	context.logger = logger;

	print("Hello World!");

	state: State;
	init(*state);

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
		}
		draw(*state);
	}
}

draw :: (s: *State) {
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

	// Actually clear our screen
	clear_value: VkClearColorValue;
	flash := abs(sin(cast(float32)s.frame_number / 1020.0));
	clear_value._float32 = float32.[0.0, 0.0, xx flash, 1.0];
	 
	clear_range := image_subresource_range(.COLOR_BIT);
	vkCmdClearColorImage(cmd, s.drawImage.image, .GENERAL, *clear_value, 1, *clear_range);

	// blit our frame onto the swapchain
	transition_image(cmd, s.drawImage.image, .GENERAL, .TRANSFER_SRC_OPTIMAL);
	transition_image(cmd, s.swapchainImages[swapchain_image_index], .UNDEFINED, .TRANSFER_DST_OPTIMAL);

	copy_image_to_image(cmd, s.drawImage.image, s.swapchainImages[swapchain_image_index], s.drawExtent, s.swapchainExtent);

	transition_image(cmd, s.swapchainImages[swapchain_image_index], .TRANSFER_DST_OPTIMAL, .PRESENT_SRC_KHR);

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

init :: (s: *State) {
	result_sdl := SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER | SDL_INIT_GAMECONTROLLER);
	if result_sdl != 0
	{
		log_error("Could not load SDL : %\n", to_string(SDL_GetError()));
	}

	sdl_flags: SDL_WindowFlags = SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI | SDL_WINDOW_VULKAN;
	s.window = SDL_CreateWindow("Hello Vulkan with Jai", SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, WIDTH, HEIGHT, sdl_flags);
	if s.window == null 
	{
		log_error("Could not create window: %\n", to_string(SDL_GetError()));
	}

	init_vulkan(s);
	init_swapchain(s);
	init_commands(s);
	init_sync_structures(s);
}

init_vulkan :: (state: *State) -> bool {
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

init_swapchain :: (state: *State) {
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

	drawImage.imageExtent = VkExtent3D.{width = WIDTH, height = HEIGHT, depth=1};
	drawImage.imageFormat = .R16G16B16A16_SFLOAT; 

	drawImageUsageFlags : VkImageUsageFlags;
	drawImageUsageFlags |= .VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
	drawImageUsageFlags |= .VK_IMAGE_USAGE_TRANSFER_DST_BIT;
	drawImageUsageFlags |= .VK_IMAGE_USAGE_STORAGE_BIT;
	drawImageUsageFlags |= .VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

	imageInfo := image_create_info(drawImage.imageFormat, drawImageUsageFlags, drawImage.imageExtent);

	imgAllocInfo: VmaAllocationCreateInfo;
	imgAllocInfo.usage = .GPU_ONLY;
	imgAllocInfo.requiredFlags = .DEVICE_LOCAL_BIT;

	vmaCreateImage(gpuAllocator, *imageInfo, *imgAllocInfo, *drawImage.image, *drawImage.allocation, null);

	imageViewInfo := image_view_create_info(drawImage.imageFormat, drawImage.image, .VK_IMAGE_ASPECT_COLOR_BIT);

	vkCreateImageView(device, *imageViewInfo, null, *drawImage.imageView);
}

init_commands :: (state: *State) {
	using state;
	
	
	command_pool_info := VkCommandPoolCreateInfo.{
		flags = .RESET_COMMAND_BUFFER_BIT,
		queueFamilyIndex = xx graphicsQueueFamily
	};

	for frames
	{
		result := vkCreateCommandPool(device, *command_pool_info, null, *it.commandPool);
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

init_sync_structures :: (state: *State) {
	using state;
	
	fence_create_info := VkFenceCreateInfo.{
		flags = .SIGNALED_BIT
	};
	semaphore_create_info := VkSemaphoreCreateInfo.{
		flags = 0
	};
	
	for frames
	{
		result := vkCreateFence(device, *fence_create_info, null, *it.renderFence);
		assert(result == .SUCCESS, "Could not create fence.");

		result = vkCreateSemaphore(device, *semaphore_create_info, null, *it.swapchainSemaphore);
		assert(result == .SUCCESS, "Could not create semaphore.");
		
		result = vkCreateSemaphore(device, *semaphore_create_info, null, *it.renderSempahore);
		assert(result == .SUCCESS, "Could not create semaphore.");
	}
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

get_current_frame :: (s: *State) -> *FrameData
{
	return *s.frames[s.frame_number % s.frames.count];
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

get_required_extensions :: (state: *State) -> [..] *u8, bool {
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


// createinfos

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

image_create_info :: (format: VkFormat, usageFlags: VkImageUsageFlags, extent: VkExtent3D) -> VkImageCreateInfo {
	info: VkImageCreateInfo;
	info.imageType = .VK_IMAGE_TYPE_2D;
	info.format = format;
	info.extent = extent;
	info.mipLevels = 1;
	info.arrayLayers = 1;
	info.samples = .VK_SAMPLE_COUNT_1_BIT;
	info.tiling = .VK_IMAGE_TILING_OPTIMAL;
	info.usage = usageFlags;
	return info;
}

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
