#import "Basic"()(MEMORY_DEBUGGER = BUILD_TYPE != .RELEASE, ENABLE_ASSERT = BUILD_TYPE != .RELEASE);

#import "SDL"(VULKAN = true);
#import "Print_Color";
#import "String";
#import "Math";
#import "stb_image";

#load "rhi_device.jai";
#load "rhi_command_buffer.jai";


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

// @todo not used yet
RendererState :: struct {
	device: Device;
	meshPipeline: Pipeline;
}

ComputePushConstants :: struct {
	data1: Vector4;
	data2: Vector4;
	data3: Vector4;
	data4: Vector4;
}

Vertex :: struct {
	position: Vector3;
	uv_x: float;
	normal: Vector3;
	uv_y: float;
	color: Vector4;
}

GpuMeshBuffers :: struct {
	indexBuffer: Buffer;
	vertexBuffer: Buffer;
}

GpuDrawPushConstants :: struct {
	worldMatrix: Matrix4;
	vertexBuffer: DeviceAddress;
}

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

	device: Device;
	init_render_hardware(*device, window, WIDTH, HEIGHT);
	init_compute_pipeline(*device);
	init_mesh_pipeline(*device);
	init_cube_mesh(*device);

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
			// ImGui_ImplSDL2_ProcessEvent(*event);
		}
		draw(*device);
		reset_temporary_storage();
		// reset_temporary_memory(*device);
	}
}

init_compute_pipeline :: (using dev: *Device) {
	computeBindGroupLayout = create_bind_group_layout(dev, .{
		debugName = "Compute Layout",
		bindings = .[
			.{0, .STORAGE_IMAGE, .COMPUTE }
		]
	});

	computeBindGroup = create_bind_group(dev, .{
		debugName = "Compute Bind Group",
		layout = computeBindGroupLayout,
		resources = .[
			.{slot = 0, texture = drawImage }
		]
	});

	computePipeline = create_compute_pipeline(dev, .{
		debugName = "Compute Pipeline",
		layouts = .[
			computeBindGroupLayout
		],
		pushConstants = .[
			.{ .COMPUTE, size_of(ComputePushConstants), 0 }
		],
		shader = create_shader(dev, #run SHADER_GET("gradient.comp"), "gradient.comp"),
	});
}

init_mesh_pipeline :: (using dev: *Device) {
	 
	// create global bindless pool
	dev.globalBindlessPool = create_bindless_pool(dev, .{
		debugName="bindless texture pool",
		resourceTypes = .[
			.{ .SAMPLED_IMAGE, 16 }
		]
	});

	// load the texture for the cube
	{
		x, y: s32;
		comp: s32;
		imageData: *u8 = stbi_load("crate.png", *x, *y, *comp, 4);

		crateTexture = create_texture(dev, .{
			debugName = "crate.png",
			format = .RGBA8,
			size = .{ width = x, height = y, depth=1},
			usage = .READ_SHADER,
			data = imageData
		});
	}

	linearSampler = create_sampler(dev, .{
		debugName = "Linear Sampler",
		magFilter = .LINEAR,
		minFilter = .LINEAR,
	});

	cubeMaterialBindGroupLayout = create_bind_group_layout(dev, .{
		debugName = "Cube Material Layout",
		bindings = .[
			.{ 0, .SAMPLED_IMAGE, .PIXEL },
			.{ 1, .SAMPLER, .PIXEL },
		]
	});

	cubeMaterialBindGroup = create_bind_group(dev, .{
		debugName = "Cube Material",
		layout = cubeMaterialBindGroupLayout,
		resources = .[
			.{slot = 0, texture = crateTexture},
			.{slot = 1, sampler = linearSampler}
		]
	});

	update_bindless_pool(dev, .{
		pool = dev.globalBindlessPool,
		resources = .[
			.{ slot = 0, index = 0, texture = crateTexture }
		]
	});

	meshPipeline = create_pipeline(dev, .{
		debugName = "Mesh Pipeline",
		layouts = .[
			cubeMaterialBindGroupLayout
		],
		bindlessPool = dev.globalBindlessPool,
		pushConstants = .[
			.{ .VERTEX, size_of(GpuDrawPushConstants), 0 }
		],
		vertexShader = create_shader(dev, #run SHADER_GET("colored_triangle_mesh.vert"), "colored_triangle_mesh.vert"),
		fragmentShader = create_shader(dev, #run SHADER_GET("colored_triangle.frag"), "colored_triangle.frag"),
		topology = .TRIANGLE_LIST,
		rasterizer = .{
			polygonMode = .FILL,
			cullMode = .NONE,
			frontFace = .CLOCKWISE,
		},
		colorTargetCount = 1,
		colorTargets = .[.{
			format = drawImage.format
		}],
		depthTargetFormat = depthImage.format,
		depth = .{
			depthWriteEnabled = true,
			depthTestEnabled = true,
			compareOp = .GREATER_OR_EQUAL
		}
	});
}

init_cube_mesh :: (using dev: *Device) {
	cubeVerts : [8]Vertex;
	
	// front side
	cubeVerts[0].position = .{-0.5, -0.5, 0.5};
	cubeVerts[0].uv_x = 0.0;
	cubeVerts[0].uv_y = 0.0;
	cubeVerts[1].position = .{0.5, -0.5, 0.5};
	cubeVerts[1].uv_x = 1.0;
	cubeVerts[1].uv_y = 0.0;
	cubeVerts[2].position = .{-0.5, 0.5, 0.5};
	cubeVerts[2].uv_x = 0.0;
	cubeVerts[2].uv_y = 1.0;
	cubeVerts[3].position = .{0.5, 0.5, 0.5};
	cubeVerts[3].uv_x = 1.0;
	cubeVerts[3].uv_y = 1.0;

	// back side
	cubeVerts[4].position = .{-0.5, -0.5, -0.5};
	cubeVerts[4].uv_x = 1.0;
	cubeVerts[4].uv_y = 0.0;
	cubeVerts[5].position = .{0.5, -0.5, -0.5};
	cubeVerts[5].uv_x = 0.0;
	cubeVerts[5].uv_y = 0.0;
	cubeVerts[6].position = .{-0.5, 0.5, -0.5};
	cubeVerts[6].uv_x = 1.0;
	cubeVerts[6].uv_y = 1.0;
	cubeVerts[7].position = .{0.5, 0.5, -0.5};
	cubeVerts[7].uv_x = 0.0;
	cubeVerts[7].uv_y = 1.0;

	cubeVerts[0].color = .{0, 0, 0, 1};
	cubeVerts[1].color = .{0.5, 0.5, 0.5, 1};
	cubeVerts[2].color = .{1, 0, 0, 1};
	cubeVerts[3].color = .{0, 1, 0, 1};
	cubeVerts[4].color = .{0, 0, 0, 1};
	cubeVerts[5].color = .{0.5, 0.5, 0.5, 1};
	cubeVerts[6].color = .{1, 0, 0, 1};
	cubeVerts[7].color = .{0, 1, 0, 1};

	cubeIndices : []u32 = .[
		//Top
        2, 6, 7,
        2, 3, 7,

        //Bottom
        0, 4, 5,
        0, 1, 5,

        //Left
        0, 2, 6,
        0, 4, 6,

        //Right
        1, 3, 7,
        1, 5, 7,

        //Front
        0, 2, 3,
        0, 1, 3,

        //Back
        4, 6, 7,
        4, 5, 7
	];

	cubeMesh = upload_mesh(dev, cubeIndices, cubeVerts, "Cube Mesh");
}

upload_mesh :: (dev: *Device, indices: []u32, vertices: []Vertex, debugName: string) -> GpuMeshBuffers {
	vertexBufferSize := vertices.count * size_of(Vertex);
	indexBufferSize := indices.count * size_of(u32);

	mesh: GpuMeshBuffers;

	mesh.vertexBuffer = create_buffer(dev, .{
		debugName = tprint("% - Vertex Buffer", debugName),
		size = xx vertexBufferSize,
		usage = .READ_AND_WRITE | .COPY_DST | .SHADER_DEVICE_ADDRESS,
		memory = .GPU_ONLY
	});

	mesh.indexBuffer = create_buffer(dev, .{
		debugName = tprint("% - Index Buffer", debugName),
		size = xx indexBufferSize,
		usage = .INDEX_BUFFER | .COPY_DST,
		memory = .GPU_ONLY
	});

	// here's where the actual data upload happens
	// it's doing a full immediate submit, should research how to do this better
	staging := create_buffer(dev, .{
		size = xx (vertexBufferSize + indexBufferSize),
		usage = .COPY_SRC,
		memory = .CPU_ONLY
	});

	data := staging.info.pMappedData;

	memcpy(data, vertices.data, vertexBufferSize);
	memcpy(cast(*u8)data + vertexBufferSize, indices.data, indexBufferSize);

	cmd := acquire_command_buffer(dev);

	copy_buffer_to_buffer(cmd, .{
		src=staging,
		dst=mesh.vertexBuffer,
		size=vertexBufferSize
	});

	copy_buffer_to_buffer(cmd, .{
		src=staging,
		dst=mesh.indexBuffer,
		srcOffset=vertexBufferSize,
		size=indexBufferSize
	});

	submit(cmd);
	destroy_buffer(dev, *staging);
	return mesh;
}

draw :: (dev: *Device) {
	// ImGui_ImplVulkan_NewFrame();
	// ImGui_ImplSDL2_NewFrame();
	// ImGui.NewFrame();


	// ImGui.ShowDemoWindow();

	// if ImGui.Begin("Background") {
	// 	ImGui.InputFloat4("data1", *state.pc.data1.component);
	// 	ImGui.InputFloat4("data2", *state.pc.data2.component);
	// 	ImGui.InputFloat4("data3", *state.pc.data3.component);
	// 	ImGui.InputFloat4("data4", *state.pc.data4.component);
	// }
	// ImGui.End();

	// ImGui.Render();

	cmd := acquire_command_buffer(dev);

	swapchainTexture := wait_and_acquire_swapchain_texture(cmd);

	dev.drawExtent.width = xx dev.drawImage.size.width;
	dev.drawExtent.height = xx dev.drawImage.size.height;

	marker_start(cmd, "Compute Drawing");

	// barrier for starting compute pass (draw image goes to write)
	barrier(cmd, .[.{dev.drawImage, .NONE, .READ_WRITE_COMPUTE}]);

	// draw background with compute
	////////////////////////////////

	// compute to draw our gradient
	set_pipeline(cmd, .COMPUTE, dev.computePipeline);
	set_bind_group(cmd, .COMPUTE, 0, dev.computeBindGroup);
	set_push_constants(cmd, .COMPUTE, 0, size_of(ComputePushConstants), *dev.pc);
	dispatch(cmd, xx ceil(dev.drawExtent.width / 16.0), xx ceil(dev.drawExtent.width / 16.0), 1);

	marker_end(cmd);

	barrier(cmd, .[
		.{dev.drawImage, .READ_WRITE_COMPUTE, .WRITE_RENDER_TARGET},
		.{dev.depthImage, .NONE, .WRITE_RENDER_TARGET}
	]);
	draw_geometry(cmd, dev);

	// blit our frame onto the swapchain
	barrier(cmd, .[
		.{dev.drawImage, .WRITE_RENDER_TARGET, .COPY_SRC},
		.{swapchainTexture, .NONE, .COPY_DST}
	]);

	copy_image_to_image(cmd, .{
		src = dev.drawImage,
		dst = swapchainTexture,
		srcRect = .{ 0,0, xx dev.drawExtent.width, xx dev.drawExtent.height },
		dstRect = .{ 0,0, xx dev.swapchainExtent.width, xx dev.swapchainExtent.height },}
	);

	barrier(cmd, .[.{swapchainTexture, .COPY_DST, .WRITE_RENDER_TARGET}]);

	// draw imgui render lists
	// begin_rendering(cmd, .{
	// 	renderArea = .{0, 0, xx dev.swapchainExtent.width, xx dev.swapchainExtent.height},
	// 	colorAttachments = .[ .{image = swapchainTexture, loadOp=.LOAD, storeOp=.STORE} ]
	// });

	// ImGui_ImplVulkan_RenderDrawData(ImGui.GetDrawData(), cmd.platformHandle);

	// end_rendering(cmd);

	barrier(cmd, .[.{swapchainTexture, .WRITE_RENDER_TARGET, .PRESENT}]);

	submit(cmd);
}

draw_geometry :: (cmd: *CommandBuffer, dev: *Device) {
	marker_start(cmd, "Drawing Geometry");

	begin_rendering(cmd, .{
		renderArea = .{0, 0, xx dev.drawExtent.width, xx dev.drawExtent.height},
		colorAttachments = .[ .{image = dev.drawImage, loadOp=.LOAD, storeOp=.STORE} ],
		depthAttachment = .{image = dev.depthImage, loadOp=.CLEAR, storeOp=.STORE, clear.depth = 0.0}
	});

	set_viewport(cmd, .{
		x = 0, y = 0,
		width = xx dev.drawExtent.width,
		height = xx dev.drawExtent.height,
		minDepth = 0, maxDepth = 1
	});
	set_scissor(cmd, .{
		x = 0, y = 0,
		width = xx dev.drawExtent.width,
		height = xx dev.drawExtent.height,
	});

	// draw mesh cube
	set_pipeline(cmd, .GRAPHICS, dev.meshPipeline);
	set_bindless_pool(cmd, .GRAPHICS, 1, dev.globalBindlessPool);
	set_bind_group(cmd, .GRAPHICS, 0, dev.cubeMaterialBindGroup);

	projection := make_projection_matrix(60.0 * PI / 180.0, cast(float)WIDTH/cast(float)HEIGHT, 1000.0, 0.01, 0.0, 0.0, true);
	projection._11 *= -1; // @todo eh?
	view := make_translation_matrix4(.{0.0, 0.0, -4.0});

	rotation: Quaternion;
	set_from_axis_and_angle(*rotation, .{0, 1, 0}, xx seconds_since_init() * 0.5);
	model := rotation_matrix(Matrix4, rotation);

	// beware, jai matrixes are row-major (designed for hlsl)
	pushConstants: GpuDrawPushConstants;
	pushConstants.worldMatrix = transpose(projection * view * model);
	pushConstants.vertexBuffer = dev.cubeMesh.vertexBuffer.deviceAddress;
	set_push_constants(cmd, .VERTEX, 0, size_of(GpuDrawPushConstants), *pushConstants);
	set_index_buffer(cmd, dev.cubeMesh.indexBuffer, 32);

	draw_indexed(cmd, 36, 1, 0, 0, 0);

	end_rendering(cmd);
	marker_end(cmd);
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

