ImGui :: #import "imgui";
for_expansion :: ImGui.for_expansion;

ImGui_ImplSDL2_InitForVulkan :: (window: *SDL_Window) -> bool
{
	if (!ImGui_ImplSDL2_Init(window, null, null))
        return false;
    bd := ImGui_ImplSDL2_GetBackendData();
    bd.UseVulkan = true;
    return true;
}

ImGui_ImplSDL2_Shutdown :: ()
{
	bd := ImGui_ImplSDL2_GetBackendData();
	assert(bd != null, "No platform backend to shutdown, or already shutdown?");
	io := ImGui.GetIO();
	platform_io := ImGui.GetPlatformIO();
	
	ImGui_ImplSDL2_ShutdownPlatformInterface();
	
	if bd.ClipboardTextData then SDL_free(bd.ClipboardTextData);
	
	for i: 0..ImGui.MouseCursor.COUNT - 1 SDL_FreeCursor(bd.MouseCursors[i]);
	
	io.BackendPlatformName = null;
    io.BackendPlatformUserData = null;
    io.BackendFlags_ &= ~(
    	.HasMouseCursors | 
    	.HasSetMousePos | 
    	.HasGamepad | 
    	.PlatformHasViewports | 
    	.HasMouseHoveredViewport
    );
    free(bd);
}

ImGui_ImplSDL2_NewFrame :: ()
{
	bd := ImGui_ImplSDL2_GetBackendData();
	assert(bd != null, "Context or backend not initialized! Did you call ImGui_ImplSDL2_Init()?");
	io := ImGui.GetIO();
	
	w, h: s32;
	display_w, display_h: s32;
	
	SDL_GetWindowSize(bd.Window, *w, *h);
	if SDL_GetWindowFlags(bd.Window) & .SDL_WINDOW_MINIMIZED
	{
		w = 0;
		h = 0;
	}
	
	if bd.Renderer != null
		SDL_GetRendererOutputSize(bd.Renderer, *display_w, *display_h);
	else
		SDL_GL_GetDrawableSize(bd.Window, *display_w, *display_h);
		
	io.DisplaySize = ImGui.ImVec2.{cast(float32) w, cast(float32) h};
	
	if w > 0 && h > 0
		io.DisplayFramebufferScale = ImGui.ImVec2.{
			cast(float32) display_w / w, cast(float32) display_h / h};
	
	if bd.WantUpdateMonitors then ImGui_ImplSDL2_UpdateMonitors();
	
	frequency := SDL_GetPerformanceFrequency();
	current_time := SDL_GetPerformanceCounter();
	if current_time <= bd.Time
		current_time = bd.Time + 1;
	io.DeltaTime = ifx bd.Time > 0
	{
		cast(float32)(cast(float64)(current_time - bd.Time) / frequency);
	}
	else
	{
		cast(float32) (1.0 / 60);
	}
	
	bd.Time = current_time;
	
	if bd.MouseLastLeaveFrame && bd.MouseLastLeaveFrame >= ImGui.GetFrameCount() && bd.MouseButtonsDown == 0
	{
		bd.MouseWindowID = 0;
		bd.MouseLastLeaveFrame = 0;
		io.AddMousePosEvent(io, -FLOAT32_MAX, -FLOAT32_MAX);
	}
	
	if bd.MouseCanReportHoveredViewport && ImGui.GetDragDropPayload() == null
		io.BackendFlags_ |= .HasMouseHoveredViewport;
	else
		io.BackendFlags_ &= ~.HasMouseHoveredViewport;
		
	ImGui_ImplSDL2_UpdateMouseData();
    ImGui_ImplSDL2_UpdateMouseCursor();

    // Update game controllers (if enabled and available)
    ImGui_ImplSDL2_UpdateGamepads();
}

ImGui_ImplSDL2_ProcessEvent :: (event: *SDL_Event) -> bool
{
	
    bd := ImGui_ImplSDL2_GetBackendData();
    assert(bd != null, "Context or backend not initialized! Did you call ImGui_ImplSDL2_Init()?");
    io := ImGui.GetIO();

    if event.type ==
    {
        case SDL_MOUSEMOTION;
        {
            mouse_pos := ImGui.ImVec2.{cast(float32)event.motion.x, cast(float32)event.motion.y};
            if (io.ConfigFlags_ & .ViewportsEnable)
            {
                window_x, window_y: s32;
                SDL_GetWindowPosition(SDL_GetWindowFromID(event.motion.windowID), *window_x, *window_y);
                mouse_pos.x += window_x;
                mouse_pos.y += window_y;
            }
            io.AddMouseSourceEvent(io, .Mouse);
            io.AddMousePosEvent(io, mouse_pos.x, mouse_pos.y);
            return true;
        }
        case SDL_MOUSEWHEEL;
        {
            wheel_x:float = xx -event.wheel.x;
            wheel_y:float = xx event.wheel.y;

            io.AddMouseSourceEvent(io, .Mouse);
            io.AddMouseWheelEvent(io, wheel_x, wheel_y);
            return true;
        }
        case SDL_MOUSEBUTTONDOWN; #through;
        case SDL_MOUSEBUTTONUP;
        {
            mouse_button: s32= -1;
            if (event.button.button == SDL_BUTTON_LEFT) { mouse_button = 0; }
            if (event.button.button == SDL_BUTTON_RIGHT) { mouse_button = 1; }
            if (event.button.button == SDL_BUTTON_MIDDLE) { mouse_button = 2; }
            if (event.button.button == SDL_BUTTON_X1) { mouse_button = 3; }
            if (event.button.button == SDL_BUTTON_X2) { mouse_button = 4; }
            if (mouse_button == -1)
                return false;
            io.AddMouseSourceEvent(io, .Mouse);
            io.AddMouseButtonEvent(io, mouse_button, (event.type == SDL_MOUSEBUTTONDOWN));
            bd.MouseButtonsDown = xx ifx (event.type == SDL_MOUSEBUTTONDOWN) then (bd.MouseButtonsDown | (1 << mouse_button)) else (bd.MouseButtonsDown & ~(1 << mouse_button));
            return true;
        }
        case SDL_TEXTINPUT;
        {
            io.AddInputCharactersUTF8(io, cast(*u8) event.text.text.data);
            return true;
        }
        case SDL_KEYDOWN; #through;
        case SDL_KEYUP;
        {
            ImGui_ImplSDL2_UpdateKeyModifiers(cast(SDL_Keymod)event.key.keysym.mod);
            key := ImGui_ImplSDL2_KeycodeToImGuiKey(event.key.keysym.sym);
            io.AddKeyEvent(io, key, (event.type == SDL_KEYDOWN));
            // To support legacy indexing (<1.87 user code). Legacy backend uses SDLK_*** as indices to IsKeyXXX() functions.
            io.SetKeyEventNativeData(io, key, cast(s32) event.key.keysym.sym, cast(s32) event.key.keysym.scancode, cast(s32) event.key.keysym.scancode); 
            return true;
        }
        case SDL_DISPLAYEVENT;
        {
            // 2.0.26 has SDL_DISPLAYEVENT_CONNECTED/SDL_DISPLAYEVENT_DISCONNECTED/SDL_DISPLAYEVENT_ORIENTATION,
            // so change of DPI/Scaling are not reflected in this event. (SDL3 has it)
            bd.WantUpdateMonitors = true;
            return true;
        }
        case SDL_WINDOWEVENT;
        {
            // - When capturing mouse, SDL will send a bunch of conflicting LEAVE/ENTER event on every mouse move, but the final ENTER tends to be right.
            // - However we won't get a correct LEAVE event for a captured window.
            // - In some cases, when detaching a window from main viewport SDL may send SDL_WINDOWEVENT_ENTER one frame too late,
            //   causing SDL_WINDOWEVENT_LEAVE on previous frame to interrupt drag operation by clear mouse position. This is why
            //   we delay process the SDL_WINDOWEVENT_LEAVE events by one frame. See issue #5012 for details.
            window_event := event.window.event;
            if (window_event == SDL_WINDOWEVENT_ENTER)
            {
                bd.MouseWindowID = event.window.windowID;
                bd.MouseLastLeaveFrame = 0;
            }
            
            if (window_event == SDL_WINDOWEVENT_LEAVE)
                bd.MouseLastLeaveFrame = ImGui.GetFrameCount() + 1;
            if (window_event == SDL_WINDOWEVENT_FOCUS_GAINED)
                io.AddFocusEvent(io, true);
            else if (window_event == SDL_WINDOWEVENT_FOCUS_LOST)
                io.AddFocusEvent(io, false);
            if (window_event == SDL_WINDOWEVENT_CLOSE || window_event == SDL_WINDOWEVENT_MOVED || window_event == SDL_WINDOWEVENT_RESIZED)
            {
            	viewport := ImGui.FindViewportByPlatformHandle(cast(*void)SDL_GetWindowFromID(event.window.windowID));
                if (viewport)
                {
                    if (window_event == SDL_WINDOWEVENT_CLOSE)
                        viewport.PlatformRequestClose = true;
                    if (window_event == SDL_WINDOWEVENT_MOVED)
                        viewport.PlatformRequestMove = true;
                    if (window_event == SDL_WINDOWEVENT_RESIZED)
                        viewport.PlatformRequestResize = true;
                    return true;
                }
            }	
            return true;
        }
        case SDL_CONTROLLERDEVICEADDED; #through;
        case SDL_CONTROLLERDEVICEREMOVED;
        {
            bd.WantUpdateGamepadsList = true;
            return true;
        }
    }
    return false;
}

ImGui_ImplSDL2_GamepadMode :: enum
{
	AutoFirst;
	AutoAll;
	Manual;
}

ImGui_ImplSDL2_SetGamepadMode :: (
	mode: ImGui_ImplSDL2_GamepadMode, 
	manual_gamepads_array: **SDL_GameController = null, 
	manual_gamepads_count: s32 = -1
)
{
	bd := ImGui_ImplSDL2_GetBackendData();
	ImGui_ImplSDL2_CloseGamepads();
	if mode == .Manual
	{
		assert(manual_gamepads_array != null && manual_gamepads_count > 0);
		for i: 0..manual_gamepads_count - 1
			ImGui.vector_push_back(*bd.Gamepads, manual_gamepads_array[i]);
	}
	else
	{
		assert(manual_gamepads_array == null && manual_gamepads_count <= 0);
		bd.WantUpdateGamepadsList = true;
	}
	
	bd.GamepadMode = mode;
}
ImGui_ImplVulkan_InitInfo :: struct
{
	Instance: VkInstance;
	PhysicalDevice: VkPhysicalDevice;
	Device: VkDevice;
	QueueFamily: u32;
	Queue: VkQueue;
	DescriptorPool: VkDescriptorPool;
	RenderPass: VkRenderPass;
	MinImageCount: u32;
	ImageCount: u32;
	MSAASamples: VkSampleCountFlagBits;
	
	PipelineCache: VkPipelineCache;
	Subpass: u32;
	
	UseDynamicRendering: bool;
	
	#if IMGUI_IMPL_VULKAN_HAS_DYNAMIC_RENDERING 
	{
		PipelineRenderingCreateInfo: VkPipelineRenderingCreateInfoKHR;
	}
	
	Allocator: *VkAllocationCallbacks;
	CheckVkResultFn: #type (err: VkResult);
	MinAllocationSize: VkDeviceSize;
}

ImGui_ImplVulkan_Init :: (info: *ImGui_ImplVulkan_InitInfo) -> bool
{
	io := ImGui.GetIO();
	assert(io.BackendRendererUserData == null, "Already initialized a renderer backend!");
	
	bd := New(ImGui_ImplVulkan_Data);
	io.BackendRendererUserData = bd;
	io.BackendRendererName = "imgui_impl_vulkan";
	// We can honor the ImDrawCmd::VtxOffset field, allowing for large meshes.
    io.BackendFlags_ |= .RendererHasVtxOffset;  
    // We can create multi-viewports on the Renderer side (optional)
    io.BackendFlags_ |= .RendererHasViewports;  
    
    assert(info.Instance != VK_NULL_HANDLE);
    assert(info.PhysicalDevice != VK_NULL_HANDLE);
    assert(info.Device != VK_NULL_HANDLE);
    assert(info.Queue != VK_NULL_HANDLE);
    assert(info.DescriptorPool != VK_NULL_HANDLE);
    assert(info.MinImageCount >= 2);
    assert(info.ImageCount >= info.MinImageCount, tprint("ImageCount (%) should be superior or equal to MinImageCount (%)", info.ImageCount, info.MinImageCount));
    if (info.UseDynamicRendering == false)
        assert(info.RenderPass != VK_NULL_HANDLE);
        
    bd.VulkanInitInfo = <<info;
    
    ImGui_ImplVulkan_CreateDeviceObjects();
    
	// main_viewport := ImGui.GetMainViewport();
	// main_viewport.RendererUserData = New(ImGui_ImplVulkan_ViewportData);

	// if (io.ConfigFlags_ & .ViewportsEnable)
	//     ImGui_ImplVulkan_InitPlatformInterface();

    return true;
}

ImGui_ImplVulkan_Shutdown :: ()
{
	bd := ImGui_ImplVulkan_GetBackendData();
	assert(bd != null, "No renderer backend to shutdown, or already shutdown?");
	io := ImGui.GetIO();
	v := *bd.VulkanInitInfo;
	
	for i: 0..bd.MainWindowRenderBuffers.Count - 1
	{
		ImGui_ImplVulkan_DestroyFrameRenderBuffers(v.Device, *bd.MainWindowRenderBuffers.FrameRenderBuffers[i], v.Allocator);
	}
	free(bd.MainWindowRenderBuffers.FrameRenderBuffers);
	
	ImGui_ImplVulkan_DestroyDeviceObjects();
	main_viewport := ImGui.GetMainViewport();
	
	// vd := cast(*ImGui_ImplVulkan_ViewportData) main_viewport.RendererUserData;
	// if vd then free(vd);
	// main_viewport.RendererUserData = null;
	
	ImGui_ImplVulkan_ShutdownPlatformInterface();

    io.BackendRendererName = null;
    io.BackendRendererUserData = null;
    io.BackendFlags_ &= ~(.RendererHasVtxOffset | .RendererHasViewports);
    free(bd);
}

ImGui_ImplVulkan_NewFrame :: ()
{
	bd := ImGui_ImplVulkan_GetBackendData();
	assert(bd != null, "Context or backend not initialized! Did you call ImGui_ImplVulkan_Init()?");
	
	if !bd.FontDescriptorSet then ImGui_ImplVulkan_CreateFontsTexture();
}

ImGui_ImplVulkan_RenderDrawData :: (
	draw_data: *ImGui.ImDrawData, 
	command_buffer: VkCommandBuffer, 
	pipeline: VkPipeline = VK_NULL_HANDLE
)
{
	fb_width := cast(s32)(draw_data.DisplaySize.x * draw_data.FramebufferScale.x);
	fb_height := cast(s32)(draw_data.DisplaySize.y * draw_data.FramebufferScale.y);
	if fb_width <= 0 || fb_height <= 0 then return;
	
	bd := ImGui_ImplVulkan_GetBackendData();
	v := bd.VulkanInitInfo;
	if pipeline == VK_NULL_HANDLE then pipeline = bd.Pipeline;
	
	wrb := *bd.MainWindowRenderBuffers;
	if wrb.FrameRenderBuffers == null
	{
		wrb.Index = 0;
		wrb.Count = v.ImageCount;
		wrb.FrameRenderBuffers = alloc(size_of(ImGui_ImplVulkan_FrameRenderBuffers) * wrb.Count);
		memset(wrb.FrameRenderBuffers, 0, size_of(ImGui_ImplVulkan_FrameRenderBuffers) * wrb.Count);
	}
	assert(wrb.Count == v.ImageCount);
	wrb.Index = (wrb.Index + 1) % wrb.Count;
	rb := *wrb.FrameRenderBuffers[wrb.Index];
	
	if draw_data.TotalVtxCount > 0
	{
		vertex_size := AlignBufferSize(cast(u64) draw_data.TotalVtxCount * size_of(ImGui.ImDrawVert), bd.BufferMemoryAlignment);
		index_size := AlignBufferSize(cast(u64) draw_data.TotalIdxCount * size_of(ImGui.ImDrawIdx), bd.BufferMemoryAlignment);
		
		if rb.VertexBuffer == VK_NULL_HANDLE || rb.VertexBufferSize < vertex_size
			CreateOrResizeBuffer(*rb.VertexBuffer, *rb.VertexBufferMemory, *rb.VertexBufferSize, vertex_size, .VERTEX_BUFFER_BIT);
		
		if rb.IndexBuffer == VK_NULL_HANDLE || rb.IndexBufferSize < index_size
			CreateOrResizeBuffer(*rb.IndexBuffer, *rb.IndexBufferMemory, *rb.IndexBufferSize, index_size, .INDEX_BUFFER_BIT);
			
		vtx_dst: *ImGui.ImDrawVert;
		idx_dst: *ImGui.ImDrawIdx;
		
		err := vkMapMemory(v.Device, rb.VertexBufferMemory, 0, vertex_size, 0, cast(**void)*vtx_dst);
		check_vk_result(err);
		
		err = vkMapMemory(v.Device, rb.IndexBufferMemory, 0, index_size, 0, cast(**void)*idx_dst);
		check_vk_result(err);
		
		for draw_data.CmdLists
		{
			memcpy(vtx_dst, it.VtxBuffer.Data, it.VtxBuffer.Size * size_of(ImGui.ImDrawVert));
			memcpy(idx_dst, it.IdxBuffer.Data, it.IdxBuffer.Size * size_of(ImGui.ImDrawIdx));
			vtx_dst += it.VtxBuffer.Size;
			idx_dst += it.IdxBuffer.Size;
		}
		
		range: [2] VkMappedMemoryRange;
		range[0].memory = rb.VertexBufferMemory;
		range[0].size = VK_WHOLE_SIZE;
		range[1].memory = rb.IndexBufferMemory;
		range[1].size = VK_WHOLE_SIZE;
		
		err = vkFlushMappedMemoryRanges(v.Device, range.count, range.data);
		check_vk_result(err);
		
		vkUnmapMemory(v.Device, rb.VertexBufferMemory);
		vkUnmapMemory(v.Device, rb.IndexBufferMemory);
	}
	
	ImGui_ImplVulkan_SetupRenderState(draw_data, pipeline, command_buffer, rb, fb_width, fb_height);
	
	clip_off := draw_data.DisplayPos;
	clip_scale := draw_data.FramebufferScale;
	
	global_vtx_offset: s32;
	global_idx_offset: s32;
	for cmd_list: draw_data.CmdLists
	{
		for pcmd: cmd_list.CmdBuffer
		{
			if pcmd.UserCallback != null
			{
				if pcmd.UserCallback == xx ImDrawCallback_ResetRenderState
					ImGui_ImplVulkan_SetupRenderState(draw_data, pipeline, command_buffer, rb, fb_width, fb_height);
				else
					pcmd.UserCallback(cmd_list, *pcmd);
			}
			else
			{
				clip_min := ImGui.ImVec2.{
					(pcmd.ClipRect.x - clip_off.x) * clip_scale.x, 
					(pcmd.ClipRect.y - clip_off.y) * clip_scale.y
				};
				
				clip_max := ImGui.ImVec2.{
					(pcmd.ClipRect.z - clip_off.x) * clip_scale.x, 
					(pcmd.ClipRect.w - clip_off.y) * clip_scale.y
				};
				
				if clip_min.x < 0.0 then clip_min.x = 0.0;
				if clip_min.y < 0.0 then clip_min.y = 0.0;
				if clip_max.x > xx fb_width then clip_max.x = xx fb_width;
				if clip_max.y > xx fb_height then clip_max.y = xx fb_height;
				if clip_max.x <= clip_min.x || clip_max.y <= clip_min.y then continue;
				
				scissor: VkRect2D;
				scissor.offset.x = xx clip_min.x;
				scissor.offset.y = xx clip_min.y;
				scissor.extent.width = xx (clip_max.x - clip_min.x);
				scissor.extent.height = xx (clip_max.y - clip_min.y);
				vkCmdSetScissor(command_buffer, 0, 1, *scissor);
				
				desc_set := VkDescriptorSet.[cast(VkDescriptorSet) pcmd.TextureId];
				#if size_of(ImGui.ImTextureID) < size_of(ImGui.ImU64)
				{
					assert(pcmd.TextureId == cast(ImGui.ImTextureID) bd.FontDescriptorSet);
					desc_set[0] = bd.FontDescriptorSet;
				}
				
				vkCmdBindDescriptorSets(command_buffer, .GRAPHICS, bd.PipelineLayout, 0, 1, desc_set.data, 0, null);
				
				index_offset: u32 = pcmd.IdxOffset + xx global_idx_offset;
				vertex_offset: s32 = (xx pcmd.VtxOffset) + global_vtx_offset;
				vkCmdDrawIndexed(
					command_buffer, 
					pcmd.ElemCount, 
					1, 
					index_offset, 
					vertex_offset, 
					0
				);
			}
		}
		
		global_idx_offset += cmd_list.IdxBuffer.Size;
		global_vtx_offset += cmd_list.VtxBuffer.Size;
	}
	
	scissor := VkRect2D.{.{0, 0}, .{xx fb_width, xx fb_height}};
	vkCmdSetScissor(command_buffer, 0, 1, *scissor);
}

ImGui_ImplVulkan_CreateFontsTexture :: () -> bool
{
	io := ImGui.GetIO();
	bd := ImGui_ImplVulkan_GetBackendData();
	v := *bd.VulkanInitInfo;
	err: VkResult;
	
	if bd.FontView || bd.FontImage || bd.FontMemory || bd.FontDescriptorSet
	{
		vkQueueWaitIdle(v.Queue);
		ImGui_ImplVulkan_DestroyFontsTexture();
	}
	
	if bd.FontCommandPool == VK_NULL_HANDLE
	{
		info: VkCommandPoolCreateInfo;
		info.queueFamilyIndex = v.QueueFamily;
		err = vkCreateCommandPool(v.Device, *info, v.Allocator, *bd.FontCommandPool);
		check_vk_result(err);
	}
	
	if bd.FontCommandBuffer == VK_NULL_HANDLE
	{
		info: VkCommandBufferAllocateInfo;
		info.commandPool = bd.FontCommandPool;
		info.commandBufferCount = 1;
		err = vkAllocateCommandBuffers(v.Device, *info, *bd.FontCommandBuffer);
		check_vk_result(err);
	}
	
	{
		err = vkResetCommandPool(v.Device, bd.FontCommandPool, 0);
		check_vk_result(err);
		begin_info: VkCommandBufferBeginInfo;
		begin_info.flags |= .ONE_TIME_SUBMIT_BIT;
		err = vkBeginCommandBuffer(bd.FontCommandBuffer, *begin_info);
		check_vk_result(err);
	}
	
	pixels: *u8;
	width, height: s32;
	
	ImGui.ImFontAtlas.GetTexDataAsRGBA32(io.Fonts, *pixels, *width, *height);
	upload_size: u64 = cast(u64) width * cast(u64) height * 4 * size_of(u8);
	
	{
		info: VkImageCreateInfo;
		info.imageType = ._2D;
		info.format = .R8G8B8A8_UNORM;
		info.extent.width = xx width;
		info.extent.height = xx height;
		info.extent.depth = 1;
		info.mipLevels = 1;
		info.arrayLayers = 1;
		info.samples = ._1_BIT;
		info.tiling = .OPTIMAL;
		info.usage = .SAMPLED_BIT | .TRANSFER_DST_BIT;
		info.sharingMode = .EXCLUSIVE;
		info.initialLayout = .UNDEFINED;
		err = vkCreateImage(v.Device, *info, v.Allocator, *bd.FontImage);
		check_vk_result(err);
		
		req: VkMemoryRequirements;
		vkGetImageMemoryRequirements(v.Device, bd.FontImage, *req);
		
		alloc_info: VkMemoryAllocateInfo;
		alloc_info.allocationSize = max(v.MinAllocationSize, req.size);
		alloc_info.memoryTypeIndex = ImGui_ImplVulkan_MemoryType(.DEVICE_LOCAL_BIT, req.memoryTypeBits);
		err = vkAllocateMemory(v.Device, *alloc_info, v.Allocator, *bd.FontMemory);
		check_vk_result(err);
		
		err = vkBindImageMemory(v.Device, bd.FontImage, bd.FontMemory, 0);
		check_vk_result(err);
	}
	
	{
		info: VkImageViewCreateInfo;
		info.image = bd.FontImage;
		info.viewType = ._2D;
		info.format = .R8G8B8A8_UNORM;
		info.subresourceRange.aspectMask = .COLOR_BIT;
		info.subresourceRange.levelCount = 1;
		info.subresourceRange.layerCount = 1;
		err = vkCreateImageView(v.Device, *info, v.Allocator, *bd.FontView);
		check_vk_result(err);
	}
	
	bd.FontDescriptorSet = cast(VkDescriptorSet) ImGui_ImplVulkan_AddTexture(bd.FontSampler, bd.FontView, .SHADER_READ_ONLY_OPTIMAL);
	
	upload_buffer_memory: VkDeviceMemory;
	upload_buffer: VkBuffer;
	{
		buffer_info: VkBufferCreateInfo;
		buffer_info.size = upload_size;
		buffer_info.usage = .TRANSFER_SRC_BIT;
		buffer_info.sharingMode = .EXCLUSIVE;
		err = vkCreateBuffer(v.Device, *buffer_info, v.Allocator, *upload_buffer);
		check_vk_result(err);
		
		req: VkMemoryRequirements;
		vkGetBufferMemoryRequirements(v.Device, upload_buffer, *req);
		bd.BufferMemoryAlignment = ifx bd.BufferMemoryAlignment > req.alignment then bd.BufferMemoryAlignment else req.alignment;
		
		alloc_info: VkMemoryAllocateInfo;
		alloc_info.allocationSize = max(v.MinAllocationSize, req.size);
		alloc_info.memoryTypeIndex = ImGui_ImplVulkan_MemoryType(.HOST_VISIBLE_BIT, req.memoryTypeBits);
		err = vkAllocateMemory(v.Device, *alloc_info, v.Allocator, *upload_buffer_memory);
		check_vk_result(err);
		
		err = vkBindBufferMemory(v.Device, upload_buffer, upload_buffer_memory, 0);
		check_vk_result(err);
	}
	
	{
		map: *u8;
		err = vkMapMemory(v.Device, upload_buffer_memory, 0, upload_size, 0, cast(**void)(*map));
		check_vk_result(err);
		
		memcpy(map, pixels, xx upload_size);
		
		range: [1] VkMappedMemoryRange;
		range[0].memory = upload_buffer_memory;
		range[0].size = upload_size;
		
		err = vkFlushMappedMemoryRanges(v.Device, 1, range.data);
		check_vk_result(err);
		
		vkUnmapMemory(v.Device, upload_buffer_memory);
	}
	
	{
		copy_barrier: [1] VkImageMemoryBarrier;
		copy_barrier[0].dstAccessMask = .TRANSFER_WRITE_BIT;
        copy_barrier[0].oldLayout = .UNDEFINED;
        copy_barrier[0].newLayout = .TRANSFER_DST_OPTIMAL;
        copy_barrier[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        copy_barrier[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        copy_barrier[0].image = bd.FontImage;
        copy_barrier[0].subresourceRange.aspectMask = .COLOR_BIT;
        copy_barrier[0].subresourceRange.levelCount = 1;
        copy_barrier[0].subresourceRange.layerCount = 1;
        vkCmdPipelineBarrier(bd.FontCommandBuffer, .HOST_BIT, .TRANSFER_BIT, 0, 0, null, 0, null, 1, copy_barrier.data);
        
        region: VkBufferImageCopy;
        region.imageSubresource.aspectMask = .COLOR_BIT;
        region.imageSubresource.layerCount = 1;
        region.imageExtent.width = xx width;
        region.imageExtent.height = xx height;
        region.imageExtent.depth = 1;
        vkCmdCopyBufferToImage(bd.FontCommandBuffer, upload_buffer, bd.FontImage, .TRANSFER_DST_OPTIMAL, 1, *region);
        
        use_barrier: [1] VkImageMemoryBarrier;
        use_barrier[0].sType = .IMAGE_MEMORY_BARRIER;
        use_barrier[0].srcAccessMask = .TRANSFER_WRITE_BIT;
        use_barrier[0].dstAccessMask = .SHADER_READ_BIT;
        use_barrier[0].oldLayout = .TRANSFER_DST_OPTIMAL;
        use_barrier[0].newLayout = .SHADER_READ_ONLY_OPTIMAL;
        use_barrier[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        use_barrier[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        use_barrier[0].image = bd.FontImage;
        use_barrier[0].subresourceRange.aspectMask = .COLOR_BIT;
        use_barrier[0].subresourceRange.levelCount = 1;
        use_barrier[0].subresourceRange.layerCount = 1;
        vkCmdPipelineBarrier(bd.FontCommandBuffer, .TRANSFER_BIT, .FRAGMENT_SHADER_BIT, 0, 0, null, 0, null, 1, use_barrier.data);
	}
	
	io.Fonts.TexID = cast(ImGui.ImTextureID) bd.FontDescriptorSet;
	
	end_info: VkSubmitInfo;
	end_info.commandBufferCount = 1;
	end_info.pCommandBuffers = *bd.FontCommandBuffer;
	err = vkEndCommandBuffer(bd.FontCommandBuffer);
	check_vk_result(err);
	
	err = vkQueueSubmit(v.Queue, 1, *end_info, VK_NULL_HANDLE);
	check_vk_result(err);
	
	err = vkQueueWaitIdle(v.Queue);
	check_vk_result(err);
	
	vkDestroyBuffer(v.Device, upload_buffer, v.Allocator);
	vkFreeMemory(v.Device, upload_buffer_memory, v.Allocator);
	
	return true;
}

ImGui_ImplVulkan_DestroyFontsTexture :: ()
{
	io := ImGui.GetIO();
	bd := ImGui_ImplVulkan_GetBackendData();
	v := *bd.VulkanInitInfo;
	
	if bd.FontDescriptorSet
	{
		ImGui_ImplVulkan_RemoveTexture(bd.FontDescriptorSet);
		bd.FontDescriptorSet = VK_NULL_HANDLE;
		io.Fonts.TexID = cast(ImGui.ImTextureID) 0;
	}
	
	if bd.FontView 
	{
		vkDestroyImageView(v.Device, bd.FontView, v.Allocator);
		bd.FontView = VK_NULL_HANDLE;
	}
	
	if bd.FontImage
	{
		vkDestroyImage(v.Device, bd.FontImage, v.Allocator);
		bd.FontImage = VK_NULL_HANDLE;
	}
	
	if bd.FontMemory
	{
		vkFreeMemory(v.Device, bd.FontMemory, v.Allocator);
		bd.FontMemory = VK_NULL_HANDLE;
	}
}

ImGui_ImplVulkan_SetMinImageCount :: (min_image_count: u32)
{
	bd := ImGui_ImplVulkan_GetBackendData();
	assert(min_image_count >= 2);
	if bd.VulkanInitInfo.MinImageCount == min_image_count then return;
	
	// That's what the C++ does...
	assert(false, "FIXME-VIEWPORT: Unsupported. Need to recreate all swap chains!");
	
	v := bd.VulkanInitInfo;
	err := vkDeviceWaitIdle(v.Device);
	check_vk_result(err);
	
	// ImGui_ImplVulkanH_DestroyAllViewportsRenderBuffers(v.Device, v.Allocator);
	
	bd.VulkanInitInfo.MinImageCount = min_image_count;
}

ImGui_ImplVulkan_AddTexture :: (
	sampler: VkSampler, 
	image_view: VkImageView, 
	image_layout: VkImageLayout
) -> VkDescriptorSet
{
	bd := ImGui_ImplVulkan_GetBackendData();
	v := *bd.VulkanInitInfo;
	
	descriptor_set: VkDescriptorSet;
	{
		alloc_info: VkDescriptorSetAllocateInfo;
		alloc_info.descriptorPool = v.DescriptorPool;
        alloc_info.descriptorSetCount = 1;
        alloc_info.pSetLayouts = *bd.DescriptorSetLayout;
        err := vkAllocateDescriptorSets(v.Device, *alloc_info, *descriptor_set);
        check_vk_result(err);
	}
	
	{
		desc_image: [1] VkDescriptorImageInfo;
		desc_image[0].sampler = sampler;
        desc_image[0].imageView = image_view;
        desc_image[0].imageLayout = image_layout;
        
        write_desc: [1] VkWriteDescriptorSet;
        write_desc[0].dstSet = descriptor_set;
        write_desc[0].descriptorCount = 1;
        write_desc[0].descriptorType = .COMBINED_IMAGE_SAMPLER;
        write_desc[0].pImageInfo = desc_image.data;
        vkUpdateDescriptorSets(v.Device, 1, write_desc.data, 0, null);
	}
	
	return descriptor_set;
}

ImGui_ImplVulkan_RemoveTexture :: (descriptor_set: VkDescriptorSet)
{
	bd := ImGui_ImplVulkan_GetBackendData();
	v := *bd.VulkanInitInfo;
	vkFreeDescriptorSets(v.Device, v.DescriptorPool, 1, *descriptor_set);
}

#scope_file

IMGUI_IMPL_VULKAN_HAS_DYNAMIC_RENDERING :: VK_VERSION_1_3 || VK_KHR_dynamic_rendering;
ImDrawCallback_ResetRenderState :: -8;

ImGui_ImplVulkan_FrameRenderBuffers :: struct
{
	VertexBufferMemory: VkDeviceMemory;
	IndexBufferMemory: VkDeviceMemory;
	VertexBufferSize: VkDeviceSize;
    IndexBufferSize: VkDeviceSize;
    VertexBuffer: VkBuffer;
    IndexBuffer: VkBuffer;
}

ImGui_ImplVulkan_WindowRenderBuffers :: struct
{
	Index: u32;
	Count: u32;
	FrameRenderBuffers: *ImGui_ImplVulkan_FrameRenderBuffers;
}

ImGui_ImplVulkan_Data :: struct
{
	VulkanInitInfo: ImGui_ImplVulkan_InitInfo;
    BufferMemoryAlignment: VkDeviceSize;
    PipelineCreateFlags: VkPipelineCreateFlags;
    DescriptorSetLayout: VkDescriptorSetLayout;
    PipelineLayout: VkPipelineLayout;
    Pipeline: VkPipeline;
    // pipeline for secondary viewports (created by backend)
	// VkPipeline PipelineForViewports;
    ShaderModuleVert: VkShaderModule;
    ShaderModuleFrag: VkShaderModule;

    // Font data
    FontSampler: VkSampler;
    FontMemory: VkDeviceMemory;
    FontImage: VkImage;
    FontView: VkImageView;
    FontDescriptorSet: VkDescriptorSet;
    FontCommandPool: VkCommandPool;
    FontCommandBuffer: VkCommandBuffer;

    // Render buffers for main window
    MainWindowRenderBuffers: ImGui_ImplVulkan_WindowRenderBuffers;
    
    BufferMemoryAlignment = 256;
}

VERT_SHADER :: #run SHADER_GET("imgui.vert");
FRAG_SHADER :: #run SHADER_GET("imgui.frag");
	
ImGui_ImplVulkan_GetBackendData :: () -> *ImGui_ImplVulkan_Data
{
	return ifx ImGui.GetCurrentContext() then 
		cast(*ImGui_ImplVulkan_Data) ImGui.GetIO().BackendRendererUserData
	else
		null;
}

ImGui_ImplVulkan_MemoryType :: (properties: VkMemoryPropertyFlags, type_bits: u32) -> u32
{
	bd := ImGui_ImplVulkan_GetBackendData();
	v := *bd.VulkanInitInfo;
	prop: VkPhysicalDeviceMemoryProperties;
	vkGetPhysicalDeviceMemoryProperties(v.PhysicalDevice, *prop);
	for i: 0..prop.memoryTypeCount - 1
	{
		if (prop.memoryTypes[i].propertyFlags & properties) == properties && type_bits & (1 << i)
			return i;
	}
	
	return 0xFFFF_FFFF;
}

check_vk_result :: (err: VkResult)
{
	bd := ImGui_ImplVulkan_GetBackendData();
	if !bd then return;
	v := *bd.VulkanInitInfo;
	if v.CheckVkResultFn then v.CheckVkResultFn(err);
}

AlignBufferSize :: (size: VkDeviceSize, alignment: VkDeviceSize) -> VkDeviceSize
{
	return (size + alignment - 1) & ~(alignment - 1);
}

// The C++ code uses non-const references, so idk if using a pointer in this case 
// is a good equivalent for the parameters
CreateOrResizeBuffer :: (
	buffer: *VkBuffer, 
	buffer_memory: *VkDeviceMemory, 
	buffer_size: *VkDeviceSize,
	new_size: u64,
	usage: VkBufferUsageFlagBits
)
{
	bd := ImGui_ImplVulkan_GetBackendData();
	v := *bd.VulkanInitInfo;
	err: VkResult;
	if <<buffer != VK_NULL_HANDLE
	{
		vkDestroyBuffer(v.Device, <<buffer, v.Allocator);
	}
	if <<buffer_memory != VK_NULL_HANDLE 
	{
		vkFreeMemory(v.Device, <<buffer_memory, v.Allocator);
	}
	
	buffer_size_aligned := 
		AlignBufferSize(max(v.MinAllocationSize, new_size), bd.BufferMemoryAlignment);
		
	buffer_info: VkBufferCreateInfo;
	buffer_info.size = buffer_size_aligned;
	buffer_info.usage = usage;
	buffer_info.sharingMode = .EXCLUSIVE;
	err = vkCreateBuffer(v.Device, *buffer_info, v.Allocator, buffer);
	check_vk_result(err);
	
	req: VkMemoryRequirements;
	vkGetBufferMemoryRequirements(v.Device, <<buffer, *req);
	bd.BufferMemoryAlignment = ifx bd.BufferMemoryAlignment > req.alignment then 
		bd.BufferMemoryAlignment 
	else 
		req.alignment;
		
	alloc_info: VkMemoryAllocateInfo;
	alloc_info.allocationSize = req.size;
	alloc_info.memoryTypeIndex = ImGui_ImplVulkan_MemoryType(.HOST_VISIBLE_BIT, req.memoryTypeBits);
	err = vkAllocateMemory(v.Device, *alloc_info, v.Allocator, buffer_memory);
	check_vk_result(err);
	
	err = vkBindBufferMemory(v.Device, <<buffer, <<buffer_memory, 0);
	check_vk_result(err);
	<<buffer_size = buffer_size_aligned;
}

ImGui_ImplVulkan_SetupRenderState :: (
	draw_data: *ImGui.ImDrawData, 
	pipeline: VkPipeline, 
	command_buffer: VkCommandBuffer,
	rb: *ImGui_ImplVulkan_FrameRenderBuffers,
	fb_width: s32,
	fb_height: s32
)
{
	bd := ImGui_ImplVulkan_GetBackendData();
	
	vkCmdBindPipeline(command_buffer, .GRAPHICS, pipeline);
	
	if draw_data.TotalVtxCount > 0
	{
		vertex_buffers := VkBuffer.[rb.VertexBuffer];
		vertex_offset := VkDeviceSize.[0];
		vkCmdBindVertexBuffers(command_buffer, 0, 1, vertex_buffers.data, vertex_offset.data);
		index_type :: #ifx size_of(ImGui.ImDrawIdx) == 2 then VkIndexType.UINT16 else VkIndexType.UINT32;
		vkCmdBindIndexBuffer(command_buffer, rb.IndexBuffer, 0, index_type);
	}
	
	viewport: VkViewport;
	viewport.width = cast(float32) fb_width;
	viewport.height = cast(float32) fb_height;
	viewport.maxDepth = 1.0;
	vkCmdSetViewport(command_buffer, 0, 1, *viewport);
	
	scale := float32.[2.0 / draw_data.DisplaySize.x, 2.0 / draw_data.DisplaySize.y];
	translate := float32.[
		-1.0 - draw_data.DisplayPos.x * scale[0], 
		-1.0 - draw_data.DisplayPos.y * scale[1]
	];
	vkCmdPushConstants(
		command_buffer, 
		bd.PipelineLayout, 
		.VERTEX_BIT, 
		size_of(float32) * 0,
		size_of(float32) * 2,
		scale.data
	);
	vkCmdPushConstants(
		command_buffer, 
		bd.PipelineLayout, 
		.VERTEX_BIT, 
		size_of(float32) * 2,
		size_of(float32) * 2,
		translate.data
	);
}

ImGui_ImplVulkan_CreateShaderModules :: (device: VkDevice, allocator: *VkAllocationCallbacks)
{
	bd := ImGui_ImplVulkan_GetBackendData();
	if bd.ShaderModuleVert == VK_NULL_HANDLE
	{
		buffer := cast(*u32) VERT_SHADER.data;
		
		vert_info: VkShaderModuleCreateInfo;
		vert_info.codeSize = VERT_SHADER.count;
		vert_info.pCode = buffer;
		
		err := vkCreateShaderModule(device, *vert_info, allocator, *bd.ShaderModuleVert);
		check_vk_result(err);
	}
	
	if bd.ShaderModuleFrag == VK_NULL_HANDLE
	{
		buffer := cast(*u32) FRAG_SHADER.data;
	
		frag_info: VkShaderModuleCreateInfo;
		frag_info.codeSize = FRAG_SHADER.count;
		frag_info.pCode = buffer;
		
		err := vkCreateShaderModule(device, *frag_info, allocator, *bd.ShaderModuleFrag);
		check_vk_result(err);
	}
}

ImGui_ImplVulkan_CreatePipeline :: (
	device: VkDevice, 
	allocator: *VkAllocationCallbacks, 
	pipelineCache: VkPipelineCache, 
	renderPass: VkRenderPass, 
	MSAASamples: VkSampleCountFlagBits, 
	pipeline: *VkPipeline, subpass: u32
)
{
	bd := ImGui_ImplVulkan_GetBackendData();
    ImGui_ImplVulkan_CreateShaderModules(device, allocator);
    
    stage: [2] VkPipelineShaderStageCreateInfo;
    stage[0].stage = .VERTEX_BIT;
    stage[0].module = bd.ShaderModuleVert;
    stage[0].pName = "main";
    stage[1].stage = .FRAGMENT_BIT;
    stage[1].module = bd.ShaderModuleFrag;
    stage[1].pName = "main";
    
    binding_desc: [1] VkVertexInputBindingDescription;
    binding_desc[0].stride = size_of(ImGui.ImDrawVert);
    binding_desc[0].inputRate = .VERTEX;
    
    attribute_desc: [3] VkVertexInputAttributeDescription;
    attribute_desc[0].location = 0;
    attribute_desc[0].binding = binding_desc[0].binding;
    attribute_desc[0].format = .R32G32_SFLOAT;
    attribute_desc[0].offset = xx offset_of(ImGui.ImDrawVert, #code pos);
    attribute_desc[1].location = 1;
    attribute_desc[1].binding = binding_desc[0].binding;
    attribute_desc[1].format = .R32G32_SFLOAT;
    attribute_desc[1].offset = xx offset_of(ImGui.ImDrawVert, #code uv);
    attribute_desc[2].location = 2;
    attribute_desc[2].binding = binding_desc[0].binding;
    attribute_desc[2].format = .R8G8B8A8_UNORM;
    attribute_desc[2].offset = xx offset_of(ImGui.ImDrawVert, #code col);
    
    vertex_info: VkPipelineVertexInputStateCreateInfo;
    vertex_info.vertexBindingDescriptionCount = 1;
    vertex_info.pVertexBindingDescriptions = binding_desc.data;
    vertex_info.vertexAttributeDescriptionCount = 3;
    vertex_info.pVertexAttributeDescriptions = attribute_desc.data;
    
    ia_info: VkPipelineInputAssemblyStateCreateInfo;
	ia_info.topology = .TRIANGLE_LIST;
	
	viewport_info: VkPipelineViewportStateCreateInfo;
	viewport_info.viewportCount = 1;
	viewport_info.scissorCount = 1;
    
    raster_info: VkPipelineRasterizationStateCreateInfo;
    raster_info.polygonMode = .FILL;
    raster_info.cullMode = .NONE;
    raster_info.frontFace = .COUNTER_CLOCKWISE;
    raster_info.lineWidth = 1.0;
    
    ms_info: VkPipelineMultisampleStateCreateInfo;
    ms_info.rasterizationSamples = ifx MSAASamples != 0 then MSAASamples else ._1_BIT;
    
    color_attachment: [1] VkPipelineColorBlendAttachmentState;
    color_attachment[0].blendEnable = VK_TRUE;
    color_attachment[0].srcColorBlendFactor = .SRC_ALPHA;
    color_attachment[0].dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA;
    color_attachment[0].colorBlendOp = .ADD;
    color_attachment[0].srcAlphaBlendFactor = .ONE;
    color_attachment[0].dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA;
    color_attachment[0].alphaBlendOp = .ADD;
    color_attachment[0].colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT;
    
    depth_info: VkPipelineDepthStencilStateCreateInfo;
    
    blend_info: VkPipelineColorBlendStateCreateInfo;
    blend_info.attachmentCount = 1;
    blend_info.pAttachments = color_attachment.data;
    
    dynamic_states := VkDynamicState.[.VIEWPORT, .SCISSOR];
    dynamic_state: VkPipelineDynamicStateCreateInfo;
    dynamic_state.dynamicStateCount = dynamic_states.count;
    dynamic_state.pDynamicStates = dynamic_states.data;
    
    info: VkGraphicsPipelineCreateInfo;
    info.flags = bd.PipelineCreateFlags;
    info.stageCount = 2;
    info.pStages = stage.data;
    info.pVertexInputState = *vertex_info;
    info.pInputAssemblyState = *ia_info;
    info.pViewportState = *viewport_info;
    info.pRasterizationState = *raster_info;
    info.pMultisampleState = *ms_info;
    info.pDepthStencilState = *depth_info;
    info.pColorBlendState = *blend_info;
    info.pDynamicState = *dynamic_state;
    info.layout = bd.PipelineLayout;
    info.renderPass = renderPass;
    info.subpass = subpass;
    
    #if IMGUI_IMPL_VULKAN_HAS_DYNAMIC_RENDERING
    {
    	if bd.VulkanInitInfo.UseDynamicRendering
    	{
    		assert(bd.VulkanInitInfo.PipelineRenderingCreateInfo.sType == .PIPELINE_RENDERING_CREATE_INFO_KHR, 
    			"PipelineRenderingCreateInfo sType must be VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR");
    		assert(bd.VulkanInitInfo.PipelineRenderingCreateInfo.pNext == null, "PipelineRenderingCreateInfo pNext must be null");
    		
    		info.pNext = *bd.VulkanInitInfo.PipelineRenderingCreateInfo;
    		info.renderPass = VK_NULL_HANDLE;
    	}
    }
    
    err := vkCreateGraphicsPipelines(device, pipelineCache, 1, *info, allocator, pipeline);
    check_vk_result(err);
}

ImGui_ImplVulkan_CreateDeviceObjects :: () -> bool
{
	bd := ImGui_ImplVulkan_GetBackendData();
	v := *bd.VulkanInitInfo;
	err: VkResult;
	
	if !bd.FontSampler
	{
		info: VkSamplerCreateInfo;
		info.magFilter = .LINEAR;
        info.minFilter = .LINEAR;
        info.mipmapMode = .LINEAR;
        info.addressModeU = .REPEAT;
        info.addressModeV = .REPEAT;
        info.addressModeW = .REPEAT;
        info.minLod = -1000;
        info.maxLod = 1000;
        info.maxAnisotropy = 1.0;
        err = vkCreateSampler(v.Device, *info, v.Allocator, *bd.FontSampler);
        check_vk_result(err);
	}
	
	if !bd.DescriptorSetLayout
	{
		binding: [1] VkDescriptorSetLayoutBinding;
		binding[0].descriptorType = .COMBINED_IMAGE_SAMPLER;
        binding[0].descriptorCount = 1;
        binding[0].stageFlags = .FRAGMENT_BIT;
        
        info: VkDescriptorSetLayoutCreateInfo; 
        info.bindingCount = 1;
        info.pBindings = binding.data;
        err = vkCreateDescriptorSetLayout(v.Device, *info, v.Allocator, *bd.DescriptorSetLayout);
        check_vk_result(err);
	}
	
	if !bd.PipelineLayout
	{
		push_constants: [1] VkPushConstantRange;
		push_constants[0].stageFlags = .VERTEX_BIT;
        push_constants[0].offset = size_of(float32) * 0;
        push_constants[0].size = size_of(float32) * 4;
        
        set_layout: [1] VkDescriptorSetLayout = VkDescriptorSetLayout.[ bd.DescriptorSetLayout ];
        
        layout_info: VkPipelineLayoutCreateInfo; 
        layout_info.setLayoutCount = 1;
        layout_info.pSetLayouts = set_layout.data;
        layout_info.pushConstantRangeCount = 1;
        layout_info.pPushConstantRanges = push_constants.data;
        err = vkCreatePipelineLayout(v.Device, *layout_info, v.Allocator, *bd.PipelineLayout);
        check_vk_result(err);
	}
	
	ImGui_ImplVulkan_CreatePipeline(v.Device, v.Allocator, v.PipelineCache, v.RenderPass, v.MSAASamples, *bd.Pipeline, v.Subpass);
	
	return true;
}

ImGui_ImplVulkan_DestroyDeviceObjects :: ()
{
	bd := ImGui_ImplVulkan_GetBackendData();
	v := *bd.VulkanInitInfo;
	
	// ImGui_ImplVulkanH_DestroyAllViewportsRenderBuffers(v.Device, v.Allocator);
    ImGui_ImplVulkan_DestroyFontsTexture();
    
    if bd.FontCommandBuffer
    {
    	vkFreeCommandBuffers(v.Device, bd.FontCommandPool, 1, *bd.FontCommandBuffer);
    	bd.FontCommandBuffer = VK_NULL_HANDLE;
    }
    
    if bd.FontCommandPool
    {
    	vkDestroyCommandPool(v.Device, bd.FontCommandPool, v.Allocator);
    	bd.FontCommandPool = VK_NULL_HANDLE;
    }
    
    if bd.ShaderModuleVert
    {
    	vkDestroyShaderModule(v.Device, bd.ShaderModuleVert, v.Allocator);
    	bd.ShaderModuleVert = VK_NULL_HANDLE;
    }
    
    if bd.ShaderModuleFrag
    {
    	vkDestroyShaderModule(v.Device, bd.ShaderModuleFrag, v.Allocator); 
    	bd.ShaderModuleFrag = VK_NULL_HANDLE;
    }
    
    if bd.FontSampler
    {
    	vkDestroySampler(v.Device, bd.FontSampler, v.Allocator);
    	bd.FontSampler = VK_NULL_HANDLE;
    }
    
    if bd.DescriptorSetLayout
    {
    	vkDestroyDescriptorSetLayout(v.Device, bd.DescriptorSetLayout, v.Allocator);
    	bd.DescriptorSetLayout = VK_NULL_HANDLE;
    }
    
    if bd.PipelineLayout
    {
    	vkDestroyPipelineLayout(v.Device, bd.PipelineLayout, v.Allocator);
    	bd.PipelineLayout = VK_NULL_HANDLE;
    }
    
    if bd.Pipeline
    {
    	vkDestroyPipeline(v.Device, bd.Pipeline, v.Allocator);
    	bd.Pipeline = VK_NULL_HANDLE;
    }
    
	// if bd.PipelineForViewports
	// {
	// 	vkDestroyPipeline(v.Device, bd.PipelineForViewports, v.Allocator);
	// 	bd.PipelineForViewports = VK_NULL_HANDLE;
	// }
}

// ImGui_ImplVulkanH_DestroyAllViewportsRenderBuffers :: (device: VkDevice, allocator: *VkAllocationCallbacks)
// {

// }

ImGui_ImplVulkan_ShutdownPlatformInterface :: ()
{
	ImGui.DestroyPlatformWindows();
}

ImGui_ImplVulkan_DestroyFrameRenderBuffers :: (
	device: VkDevice, 
	buffers: *ImGui_ImplVulkan_FrameRenderBuffers, 
	allocator: *VkAllocationCallbacks
)
{
	if buffers.VertexBuffer
	{
		vkDestroyBuffer(device, buffers.VertexBuffer, allocator);
		buffers.VertexBuffer = VK_NULL_HANDLE;
	}
	
	if buffers.VertexBufferMemory
	{
		vkFreeMemory(device, buffers.VertexBufferMemory, allocator);
		buffers.VertexBufferMemory = VK_NULL_HANDLE;
	}
	
	if buffers.IndexBuffer
	{
		vkDestroyBuffer(device, buffers.IndexBuffer, allocator);
		buffers.IndexBuffer = VK_NULL_HANDLE;
	}
	
	if buffers.IndexBufferMemory
	{
		vkFreeMemory(device, buffers.IndexBufferMemory, allocator);
		buffers.IndexBufferMemory = VK_NULL_HANDLE;
	}
	
	buffers.VertexBufferSize = 0;
    buffers.IndexBufferSize = 0;
}

offset_of :: ($T: Type, ident: Code) -> s64 #expand 
{
	t: T = ---;
	return cast(*void) (*t.#insert ident) - cast(*void) *t;
}


#scope_file

// In C++ this is defined as : 
//	#if SDL_VERSION_ATLEAST(2, 0, 4) && !defined(__EMSCRIPTEN__) && \
//	!defined(__ANDROID__) && !(defined(__APPLE__) && TARGET_OS_IOS) && \
//	!defined(__amigaos4__)
//	#define SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE 1
//	#else
//	#define SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE 0
//	#endif
SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE :: OS != .ANDROID && OS != .MACOS;

ImGui_ImplSDL2_Data :: struct
{
	Window: *SDL_Window;
	Renderer: *SDL_Renderer;
	Time: u64;
	ClipboardTextData: *u8;
	UseVulkan: bool;
	WantUpdateMonitors: bool;
	
	// Mouse handling
	MouseWindowID: u32;
	MouseButtonsDown: s32;
	MouseCursors: [ImGui.MouseCursor.COUNT] *SDL_Cursor;
	MouseLastCursor: *SDL_Cursor;
	MouseLastLeaveFrame: s32;
	MouseCanUseGlobalState: bool;
	MouseCanReportHoveredViewport: bool;
	
	// Gamepad handling
	Gamepads: ImGui.ImVector(*SDL_GameController);
	GamepadMode: ImGui_ImplSDL2_GamepadMode;
	WantUpdateGamepadsList: bool;
}

ImGui_ImplSDL2_GetBackendData :: () -> *ImGui_ImplSDL2_Data #c_call
{
	return ifx ImGui.GetCurrentContext()
	{
		cast(*ImGui_ImplSDL2_Data)ImGui.GetIO().BackendPlatformUserData;
	}
	else
	{
		null;
	};
}

ImGui_ImplSDL2_GetClipboardText :: (_: *void) -> *u8 #c_call
{
	bd := ImGui_ImplSDL2_GetBackendData();
    if bd.ClipboardTextData then SDL_free(bd.ClipboardTextData);
    bd.ClipboardTextData = SDL_GetClipboardText();
    return bd.ClipboardTextData;
}

ImGui_ImplSDL2_SetClipboardText :: (_: *void, text: *u8) #c_call
{
	SDL_SetClipboardText(text);
}

ImGui_ImplSDL2_SetPlatformImeData :: (viewport: *ImGui.Viewport, data: *ImGui.PlatformImeData) #c_call
{
	if !data.WantVisible then return;
	
	r: SDL_Rect;
	r.x = cast(s32)(data.InputPos.x - viewport.Pos.x);
    r.y = cast(s32)(data.InputPos.y - viewport.Pos.y + data.InputLineHeight);
    r.w = 1;
    r.h = cast(s32)data.InputLineHeight;
    SDL_SetTextInputRect(*r);
}

ImGui_ImplSDL2_KeycodeToImGuiKey :: (keycode: SDL_Keycode) -> ImGui.Key
{
	if keycode == 
    {
        case SDLK_TAB; return .ImGuiKey_Tab;
        case SDLK_LEFT; return .ImGuiKey_LeftArrow;
        case SDLK_RIGHT; return .ImGuiKey_RightArrow;
        case SDLK_UP; return .ImGuiKey_UpArrow;
        case SDLK_DOWN; return .ImGuiKey_DownArrow;
        case SDLK_PAGEUP; return .ImGuiKey_PageUp;
        case SDLK_PAGEDOWN; return .ImGuiKey_PageDown;
        case SDLK_HOME; return .ImGuiKey_Home;
        case SDLK_END; return .ImGuiKey_End;
        case SDLK_INSERT; return .ImGuiKey_Insert;
        case SDLK_DELETE; return .ImGuiKey_Delete;
        case SDLK_BACKSPACE; return .ImGuiKey_Backspace;
        case SDLK_SPACE; return .ImGuiKey_Space;
        case SDLK_RETURN; return .ImGuiKey_Enter;
        case SDLK_ESCAPE; return .ImGuiKey_Escape;
        case SDLK_QUOTE; return .ImGuiKey_Apostrophe;
        case SDLK_COMMA; return .ImGuiKey_Comma;
        case SDLK_MINUS; return .ImGuiKey_Minus;
        case SDLK_PERIOD; return .ImGuiKey_Period;
        case SDLK_SLASH; return .ImGuiKey_Slash;
        case SDLK_SEMICOLON; return .ImGuiKey_Semicolon;
        case SDLK_EQUALS; return .ImGuiKey_Equal;
        case SDLK_LEFTBRACKET; return .ImGuiKey_LeftBracket;
        case SDLK_BACKSLASH; return .ImGuiKey_Backslash;
        case SDLK_RIGHTBRACKET; return .ImGuiKey_RightBracket;
        case SDLK_BACKQUOTE; return .ImGuiKey_GraveAccent;
        case SDLK_CAPSLOCK; return .ImGuiKey_CapsLock;
        case SDLK_SCROLLLOCK; return .ImGuiKey_ScrollLock;
        case SDLK_NUMLOCKCLEAR; return .ImGuiKey_NumLock;
        case SDLK_PRINTSCREEN; return .ImGuiKey_PrintScreen;
        case SDLK_PAUSE; return .ImGuiKey_Pause;
        case SDLK_KP_0; return .ImGuiKey_Keypad0;
        case SDLK_KP_1; return .ImGuiKey_Keypad1;
        case SDLK_KP_2; return .ImGuiKey_Keypad2;
        case SDLK_KP_3; return .ImGuiKey_Keypad3;
        case SDLK_KP_4; return .ImGuiKey_Keypad4;
        case SDLK_KP_5; return .ImGuiKey_Keypad5;
        case SDLK_KP_6; return .ImGuiKey_Keypad6;
        case SDLK_KP_7; return .ImGuiKey_Keypad7;
        case SDLK_KP_8; return .ImGuiKey_Keypad8;
        case SDLK_KP_9; return .ImGuiKey_Keypad9;
        case SDLK_KP_PERIOD; return .ImGuiKey_KeypadDecimal;
        case SDLK_KP_DIVIDE; return .ImGuiKey_KeypadDivide;
        case SDLK_KP_MULTIPLY; return .ImGuiKey_KeypadMultiply;
        case SDLK_KP_MINUS; return .ImGuiKey_KeypadSubtract;
        case SDLK_KP_PLUS; return .ImGuiKey_KeypadAdd;
        case SDLK_KP_ENTER; return .ImGuiKey_KeypadEnter;
        case SDLK_KP_EQUALS; return .ImGuiKey_KeypadEqual;
        case SDLK_LCTRL; return .ImGuiKey_LeftCtrl;
        case SDLK_LSHIFT; return .ImGuiKey_LeftShift;
        case SDLK_LALT; return .ImGuiKey_LeftAlt;
        case SDLK_LGUI; return .ImGuiKey_LeftSuper;
        case SDLK_RCTRL; return .ImGuiKey_RightCtrl;
        case SDLK_RSHIFT; return .ImGuiKey_RightShift;
        case SDLK_RALT; return .ImGuiKey_RightAlt;
        case SDLK_RGUI; return .ImGuiKey_RightSuper;
        case SDLK_APPLICATION; return .ImGuiKey_Menu;
        case SDLK_0; return .ImGuiKey_0;
        case SDLK_1; return .ImGuiKey_1;
        case SDLK_2; return .ImGuiKey_2;
        case SDLK_3; return .ImGuiKey_3;
        case SDLK_4; return .ImGuiKey_4;
        case SDLK_5; return .ImGuiKey_5;
        case SDLK_6; return .ImGuiKey_6;
        case SDLK_7; return .ImGuiKey_7;
        case SDLK_8; return .ImGuiKey_8;
        case SDLK_9; return .ImGuiKey_9;
        case SDLK_a; return .ImGuiKey_A;
        case SDLK_b; return .ImGuiKey_B;
        case SDLK_c; return .ImGuiKey_C;
        case SDLK_d; return .ImGuiKey_D;
        case SDLK_e; return .ImGuiKey_E;
        case SDLK_f; return .ImGuiKey_F;
        case SDLK_g; return .ImGuiKey_G;
        case SDLK_h; return .ImGuiKey_H;
        case SDLK_i; return .ImGuiKey_I;
        case SDLK_j; return .ImGuiKey_J;
        case SDLK_k; return .ImGuiKey_K;
        case SDLK_l; return .ImGuiKey_L;
        case SDLK_m; return .ImGuiKey_M;
        case SDLK_n; return .ImGuiKey_N;
        case SDLK_o; return .ImGuiKey_O;
        case SDLK_p; return .ImGuiKey_P;
        case SDLK_q; return .ImGuiKey_Q;
        case SDLK_r; return .ImGuiKey_R;
        case SDLK_s; return .ImGuiKey_S;
        case SDLK_t; return .ImGuiKey_T;
        case SDLK_u; return .ImGuiKey_U;
        case SDLK_v; return .ImGuiKey_V;
        case SDLK_w; return .ImGuiKey_W;
        case SDLK_x; return .ImGuiKey_X;
        case SDLK_y; return .ImGuiKey_Y;
        case SDLK_z; return .ImGuiKey_Z;
        case SDLK_F1; return .ImGuiKey_F1;
        case SDLK_F2; return .ImGuiKey_F2;
        case SDLK_F3; return .ImGuiKey_F3;
        case SDLK_F4; return .ImGuiKey_F4;
        case SDLK_F5; return .ImGuiKey_F5;
        case SDLK_F6; return .ImGuiKey_F6;
        case SDLK_F7; return .ImGuiKey_F7;
        case SDLK_F8; return .ImGuiKey_F8;
        case SDLK_F9; return .ImGuiKey_F9;
        case SDLK_F10; return .ImGuiKey_F10;
        case SDLK_F11; return .ImGuiKey_F11;
        case SDLK_F12; return .ImGuiKey_F12;
        case SDLK_F13; return .ImGuiKey_F13;
        case SDLK_F14; return .ImGuiKey_F14;
        case SDLK_F15; return .ImGuiKey_F15;
        case SDLK_F16; return .ImGuiKey_F16;
        case SDLK_F17; return .ImGuiKey_F17;
        case SDLK_F18; return .ImGuiKey_F18;
        case SDLK_F19; return .ImGuiKey_F19;
        case SDLK_F20; return .ImGuiKey_F20;
        case SDLK_F21; return .ImGuiKey_F21;
        case SDLK_F22; return .ImGuiKey_F22;
        case SDLK_F23; return .ImGuiKey_F23;
        case SDLK_F24; return .ImGuiKey_F24;
        case SDLK_AC_BACK; return .ImGuiKey_AppBack;
        case SDLK_AC_FORWARD; return .ImGuiKey_AppForward;
    }
    return .ImGuiKey_None;
}

ImGui_ImplSDL2_UpdateKeyModifiers :: (sdl_key_mods: SDL_Keymod)
{
	io := ImGui.GetIO();
	io.AddKeyEvent(io, ImGui.Key.Mod_Ctrl, (sdl_key_mods & KMOD_CTRL) != 0);
    io.AddKeyEvent(io, ImGui.Key.Mod_Shift, (sdl_key_mods & KMOD_SHIFT) != 0);
    io.AddKeyEvent(io, ImGui.Key.Mod_Alt, (sdl_key_mods & KMOD_ALT) != 0);
    io.AddKeyEvent(io, ImGui.Key.Mod_Super, (sdl_key_mods & KMOD_GUI) != 0);
}

ImGui_ImplSDL2_Init :: (window: *SDL_Window, renderer: *SDL_Renderer, sdl_gl_context: *void) -> bool
{
	io := ImGui.GetIO();
	assert(io.BackendPlatformUserData == null, "Already initialized a platform backend!");
	
	mouse_can_use_global_state := false;
	
	#if SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE
	{
		sdl_backend := SDL_GetCurrentVideoDriver();
		global_mouse_whitelist :: (*u8).["windows\0", "cocoa\0", "x11\0", "DIVE\0", "VMAN\0"];
		
		for global_mouse_whitelist
		{
			if strcmp(sdl_backend, it) == 0 then mouse_can_use_global_state = true;
		}
	}
	
	bd := New(ImGui_ImplSDL2_Data);
	io.BackendPlatformUserData = cast(*void)bd;
  	io.BackendPlatformName = "imgui_impl_sdl2";
  	io.BackendFlags_ |= .HasMouseCursors; 
  	io.BackendFlags_ |= .HasSetMousePos; 
  	
	if (mouse_can_use_global_state)
	{
		io.BackendFlags_ |= .PlatformHasViewports;
	}
	
	bd.Window = window;
	bd.Renderer = renderer;
	
	bd.MouseCanUseGlobalState = mouse_can_use_global_state;
	
	#if OS == .MACOS
	{
		bd.MouseCanReportHoveredViewport = bd.MouseCanUseGlobalState;
	}
	else
	{
		bd.MouseCanReportHoveredViewport = false;
	}
	
	bd.WantUpdateMonitors = true;
	
	io.SetClipboardTextFn = ImGui_ImplSDL2_SetClipboardText;
    io.GetClipboardTextFn = ImGui_ImplSDL2_GetClipboardText;
    io.ClipboardUserData = null;
    
    bd.GamepadMode = .AutoFirst;
    bd.WantUpdateGamepadsList = true;
    
    bd.MouseCursors[ImGui.MouseCursor.Arrow] = SDL_CreateSystemCursor(.ARROW);
    bd.MouseCursors[ImGui.MouseCursor.TextInput] = SDL_CreateSystemCursor(.IBEAM);
    bd.MouseCursors[ImGui.MouseCursor.ResizeAll] = SDL_CreateSystemCursor(.SIZEALL);
    bd.MouseCursors[ImGui.MouseCursor.ResizeNS] = SDL_CreateSystemCursor(.SIZENS);
    bd.MouseCursors[ImGui.MouseCursor.ResizeEW] = SDL_CreateSystemCursor(.SIZEWE);
    bd.MouseCursors[ImGui.MouseCursor.ResizeNESW] = SDL_CreateSystemCursor(.SIZENESW);
    bd.MouseCursors[ImGui.MouseCursor.ResizeNWSE] = SDL_CreateSystemCursor(.SIZENWSE);
    bd.MouseCursors[ImGui.MouseCursor.Hand] = SDL_CreateSystemCursor(.HAND);
    bd.MouseCursors[ImGui.MouseCursor.NotAllowed] = SDL_CreateSystemCursor(.NO);
    
    main_viewport := ImGui.GetMainViewport();
    main_viewport.PlatformHandle = cast(*void) window;
    main_viewport.PlatformHandleRaw = null;
    
    info: SDL_SysWMinfo;
    SDL_VERSION(*info.version);
    
    if SDL_GetWindowWMInfo(window, *info)
    {
    	#if OS == .WINDOWS
    		main_viewport.PlatformHandleRaw = cast(*void)info.info.win.window;
    }
    
    SDL_SetHint(SDL_HINT_MOUSE_FOCUS_CLICKTHROUGH, "1");
    // These hints are not set in the SDL bindings, maybe I should add them
    // but IDK if the version has it
	// SDL_SetHint(SDL_HINT_IME_SHOW_UI, "1");
	// SDL_SetHint(SDL_HINT_MOUSE_AUTO_CAPTURE, "0");
	
	// TODO Add that once and if viewports functions are done
	// if (io.ConfigFlags_ & .ViewportsEnable) && (io.BackendFlags_ & .PlatformHasViewports)
	//     ImGui_ImplSDL2_InitPlatformInterface(window, sdl_gl_context);
	
	return true;
}

ImGui_ImplSDL2_InitPlatformInterface :: (window: *SDL_Window, sdl_gl_context: *void)
{
	// TODO Add that once and if viewports functions are done
	// 	ImGuiPlatformIO& platform_io = ImGui::GetPlatformIO();
	//     platform_io.Platform_CreateWindow = ImGui_ImplSDL2_CreateWindow;
	//     platform_io.Platform_DestroyWindow = ImGui_ImplSDL2_DestroyWindow;
	//     platform_io.Platform_ShowWindow = ImGui_ImplSDL2_ShowWindow;
	//     platform_io.Platform_SetWindowPos = ImGui_ImplSDL2_SetWindowPos;
	//     platform_io.Platform_GetWindowPos = ImGui_ImplSDL2_GetWindowPos;
	//     platform_io.Platform_SetWindowSize = ImGui_ImplSDL2_SetWindowSize;
	//     platform_io.Platform_GetWindowSize = ImGui_ImplSDL2_GetWindowSize;
	//     platform_io.Platform_SetWindowFocus = ImGui_ImplSDL2_SetWindowFocus;
	//     platform_io.Platform_GetWindowFocus = ImGui_ImplSDL2_GetWindowFocus;
	//     platform_io.Platform_GetWindowMinimized = ImGui_ImplSDL2_GetWindowMinimized;
	//     platform_io.Platform_SetWindowTitle = ImGui_ImplSDL2_SetWindowTitle;
	//     platform_io.Platform_RenderWindow = ImGui_ImplSDL2_RenderWindow;
	//     platform_io.Platform_SwapBuffers = ImGui_ImplSDL2_SwapBuffers;
	// #if SDL_HAS_WINDOW_ALPHA
	//     platform_io.Platform_SetWindowAlpha = ImGui_ImplSDL2_SetWindowAlpha;
	// #endif
	// #if SDL_HAS_VULKAN
	//     platform_io.Platform_CreateVkSurface = ImGui_ImplSDL2_CreateVkSurface;
	// #endif
    // io.SetPlatformImeDataFn = ImGui_ImplSDL2_SetPlatformImeData;

	//     // Register main window handle (which is owned by the main application, not by us)
	// // This is mostly for simplicity and consistency, so that our code (e.g. mouse handling etc.) can use same logic for main and secondary viewports.
	// ImGuiViewport* main_viewport = ImGui::GetMainViewport();
	// ImGui_ImplSDL2_ViewportData* vd = IM_NEW(ImGui_ImplSDL2_ViewportData)();
	// vd->Window = window;
	// vd->WindowID = SDL_GetWindowID(window);
	// vd->WindowOwned = false;
	// vd->GLContext = sdl_gl_context;
	// main_viewport->PlatformUserData = vd;
	// main_viewport->PlatformHandle = vd->Window;
}

ImGui_ImplSDL2_ShutdownPlatformInterface :: ()
{
	ImGui.DestroyPlatformWindows();
}

ImGui_ImplSDL2_UpdateMouseData :: ()
{
	bd := ImGui_ImplSDL2_GetBackendData();
	io := ImGui.GetIO();
	
	#if SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE
	{
		SDL_CaptureMouse(ifx bd.MouseButtonsDown != 0 then SDL_TRUE else SDL_FALSE);
		focused_window := SDL_GetKeyboardFocus();
		if focused_window then bd.Window = focused_window;
		is_app_focused := 
			focused_window && 
			(bd.Window || 
			ImGui.FindViewportByPlatformHandle(cast(*void) focused_window));
	}
	else
	{
		focused_window := bd.Window;
		is_app_focused := SDL_GetWindowFlags(bd.Window) & SDL_WINDOW_INPUT_FOCUS != 0;
	}
	
	if is_app_focused
	{
		if io.WantSetMousePos
		{
			#if SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE
			{
				if io.ConfigFlags_ & .ViewportsEnable
				{
					SDL_WarpMouseGlobal(xx io.MousePos.x, xx io.MousePos.y);
				}
				else
				{
					SDL_WarpMouseInWindow(bd.Window, xx io.MousePos.x, xx io.MousePos.y);
				}
			}
			else
			{
				SDL_WarpMouseInWindow(bd.Window, xx io.MousePos.x, xx io.MousePos.y);
			}
		}
		
		if bd.MouseCanUseGlobalState && bd.MouseButtonsDown == 0
		{
			mouse_x, mouse_y, window_x, window_y: s32;
			SDL_GetGlobalMouseState(*mouse_x, *mouse_y);
			
			if !(io.ConfigFlags_ & .ViewportsEnable)
			{
				SDL_GetWindowPosition(focused_window, *window_x, *window_y);
				mouse_x -= window_x;
				mouse_y -= window_y;
			}
			
			io.AddMousePosEvent(io, cast(float32) mouse_x, cast(float32) mouse_y);
		}
	}
	
	if io.BackendFlags_ & .HasMouseHoveredViewport
	{
		mouse_viewport_id: ImGui.ID = 0;
		sdl_mouse_window := SDL_GetWindowFromID(bd.MouseWindowID);
		if sdl_mouse_window
		{
			mouse_viewport := ImGui.FindViewportByPlatformHandle(cast(*void) sdl_mouse_window);
			if mouse_viewport
			{
				mouse_viewport_id = mouse_viewport.ID_;
				io.AddMouseViewportEvent(io, mouse_viewport_id);
			}
		}
	}
}

ImGui_ImplSDL2_UpdateMouseCursor :: ()
{
	io := ImGui.GetIO();
	if io.ConfigFlags_ & .NoMouseCursorChange then return;
	
	bd := ImGui_ImplSDL2_GetBackendData();
	imgui_cursor := ImGui.GetMouseCursor();
	if io.MouseDrawCursor || imgui_cursor == .None
	{
		SDL_ShowCursor(xx SDL_FALSE);
	}
	else
	{
		expected_cursor := ifx bd.MouseCursors[imgui_cursor] then
		{
			bd.MouseCursors[imgui_cursor];
		}
		else
		{
			bd.MouseCursors[ImGui.MouseCursor.Arrow];
		}
		
		if bd.MouseLastCursor != expected_cursor
		{
			SDL_SetCursor(expected_cursor);
			bd.MouseLastCursor = expected_cursor;
		}
		
		SDL_ShowCursor(xx SDL_TRUE);
	}
}

ImGui_ImplSDL2_CloseGamepads :: ()
{
	bd := ImGui_ImplSDL2_GetBackendData();
	if bd.GamepadMode != .Manual then for bd.Gamepads SDL_GameControllerClose(it);
		
	bd.Gamepads.Size = 0;
}

ImGui_ImplSDL2_UpdateGamepadButton :: (
	bd: *ImGui_ImplSDL2_Data, 
	io: *ImGui.IO, 
	key: ImGui.Key, 
	button_no: SDL_GameControllerButton
)
{
	merged_value := false;
	for bd.Gamepads merged_value |= SDL_GameControllerGetButton(it, button_no) != 0;
	io.AddKeyEvent(io, key, merged_value);
}

Saturate :: (v: float32) -> float32
{
	return ifx v < 0.0 then 
		0.0
	else 
		ifx v > 1.0 then 
			1.0
		else 
			v;
}

ImGui_ImplSDL2_UpdateGamepadAnalog :: (
	bd: *ImGui_ImplSDL2_Data, 
	io: *ImGui.IO, 
	key: ImGui.Key, 
	axis_no: SDL_GameControllerAxis, 
	v0: float32, 
	v1: float32
)
{
	merged_value := 0.0;
	for gamepad: bd.Gamepads
	{
		axis_value := SDL_GameControllerGetAxis(gamepad, axis_no);
		vn := Saturate(cast(float32) (axis_value - v0) / cast(float32) (v1 - v0));
		
		if merged_value < vn then merged_value = vn;
	}
	
	io.AddKeyAnalogEvent(io, key, merged_value > 0.1, merged_value);
}


ImGui_ImplSDL2_UpdateGamepads :: ()
{
	bd := ImGui_ImplSDL2_GetBackendData();
	io := ImGui.GetIO();
	
	if bd.WantUpdateGamepadsList && bd.GamepadMode != .Manual
	{
		ImGui_ImplSDL2_CloseGamepads();
		joystick_count := SDL_NumJoysticks();
		for i: 0..joystick_count - 1
		{
			if !SDL_IsGameController(i) then continue;
			
			gamepad := SDL_GameControllerOpen(i);
			if gamepad == null then continue;
			
			ImGui.vector_push_back(*bd.Gamepads, gamepad);
			if bd.GamepadMode == .AutoFirst then break;
		}
		
		bd.WantUpdateGamepadsList = false;
	}
	
	if (io.ConfigFlags_ & .NavEnableGamepad) == 0 then return;
	io.BackendFlags_ &= ~.HasGamepad;
	if bd.Gamepads.Size == 0 then return;
	io.BackendFlags_ |= .HasGamepad;
	
	thumb_dead_zone: s32 = 8000;
	
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadStart, SDL_CONTROLLER_BUTTON_START);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadBack, SDL_CONTROLLER_BUTTON_BACK);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadFaceLeft,
		SDL_CONTROLLER_BUTTON_X); // Xbox X, PS Square
	ImGui_ImplSDL2_UpdateGamepadButton(
		bd, io, .GamepadFaceRight,
		SDL_CONTROLLER_BUTTON_B); // Xbox B, PS Circle
	ImGui_ImplSDL2_UpdateGamepadButton(
		bd, io, .GamepadFaceUp,
		SDL_CONTROLLER_BUTTON_Y); // Xbox Y, PS Triangle
	ImGui_ImplSDL2_UpdateGamepadButton(
		bd, io, .GamepadFaceDown,
		SDL_CONTROLLER_BUTTON_A); // Xbox A, PS Cross
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadDpadLeft,
									   SDL_CONTROLLER_BUTTON_DPAD_LEFT);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadDpadRight,
									   SDL_CONTROLLER_BUTTON_DPAD_RIGHT);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadDpadUp,
									   SDL_CONTROLLER_BUTTON_DPAD_UP);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadDpadDown,
									   SDL_CONTROLLER_BUTTON_DPAD_DOWN);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadL1,
									   SDL_CONTROLLER_BUTTON_LEFTSHOULDER);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadR1,
									   SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);
	ImGui_ImplSDL2_UpdateGamepadAnalog(
		bd, io, .GamepadL2, SDL_CONTROLLER_AXIS_TRIGGERLEFT, 0.0, 32767);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadR2,
									   SDL_CONTROLLER_AXIS_TRIGGERRIGHT, 0.0,
									   32767);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadL3,
									   SDL_CONTROLLER_BUTTON_LEFTSTICK);
	ImGui_ImplSDL2_UpdateGamepadButton(bd, io, .GamepadR3,
									   SDL_CONTROLLER_BUTTON_RIGHTSTICK);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadLStickLeft,
									   SDL_CONTROLLER_AXIS_LEFTX,
									   xx -thumb_dead_zone, -32768);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadLStickRight,
									   SDL_CONTROLLER_AXIS_LEFTX,
									   xx +thumb_dead_zone, +32767);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadLStickUp,
									   SDL_CONTROLLER_AXIS_LEFTY,
									   xx -thumb_dead_zone, -32768);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadLStickDown,
									   SDL_CONTROLLER_AXIS_LEFTY,
									   xx +thumb_dead_zone, +32767);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadRStickLeft,
									   SDL_CONTROLLER_AXIS_RIGHTX,
									   xx -thumb_dead_zone, -32768);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadRStickRight,
									   SDL_CONTROLLER_AXIS_RIGHTX,
									   xx +thumb_dead_zone, +32767);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadRStickUp,
									   SDL_CONTROLLER_AXIS_RIGHTY,
									   xx -thumb_dead_zone, -32768);
	ImGui_ImplSDL2_UpdateGamepadAnalog(bd, io, .GamepadRStickDown,
									   SDL_CONTROLLER_AXIS_RIGHTY,
									   xx +thumb_dead_zone, +32767);
}

ImGui_ImplSDL2_UpdateMonitors :: ()
{
	bd := ImGui_ImplSDL2_GetBackendData();
	platform_io := ImGui.GetPlatformIO();
	
	platform_io.Monitors.Size = 0;
	bd.WantUpdateMonitors = false;
	
	display_count := SDL_GetNumVideoDisplays();
	for i : 0..display_count - 1
	{
		monitor: ImGui.PlatformMonitor;
		r: SDL_Rect;
		SDL_GetDisplayBounds(i, *r);
		monitor.MainPos = ImGui.ImVec2.{cast(float32) r.x, cast(float32) r.y};
		monitor.WorkPos = monitor.MainPos;
		monitor.MainSize = ImGui.ImVec2.{cast(float32) r.w, cast(float32) r.h};
		monitor.WorkSize = monitor.MainSize;
		
		// #if SDL_HAS_USABLE_DISPLAY_BOUNDS
		SDL_GetDisplayUsableBounds(i, *r);
		monitor.WorkPos = ImGui.ImVec2.{cast(float32) r.x, cast(float32) r.y};
		monitor.WorkSize = ImGui.ImVec2.{cast(float32) r.w, cast(float32) r.h};
		// #endif
		// #if SDL_HAS_PER_MONITOR_DPI
		dpi := 0.0;
		if !SDL_GetDisplayDPI(i, *dpi, null, null)
			monitor.DpiScale = dpi / 96.0;
		// #endif
		monitor.PlatformHandle = cast(*void) cast(s64) i;
		ImGui.vector_push_back(*platform_io.Monitors, monitor);
	}
}
