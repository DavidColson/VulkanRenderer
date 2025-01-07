PipelineBuilder :: struct {
	shaderStages: [2]VkPipelineShaderStageCreateInfo;
	inputAssembly: VkPipelineInputAssemblyStateCreateInfo;
	rasterizer: VkPipelineRasterizationStateCreateInfo;
	colorBlendAttachment: VkPipelineColorBlendAttachmentState;
	multisampling: VkPipelineMultisampleStateCreateInfo;
	pipelineLayout: VkPipelineLayout;
	depthStencil: VkPipelineDepthStencilStateCreateInfo;
	renderInfo: VkPipelineRenderingCreateInfo;
	colorAttachmentFormat: VkFormat;
}

build_pipeline :: (builder: *PipelineBuilder, s: *GfxDevice) -> VkPipeline {
	// some default options
	builder.inputAssembly.primitiveRestartEnable = VK_FALSE;
	builder.rasterizer.lineWidth = 1.0;

	// set everything up
	viewportState: VkPipelineViewportStateCreateInfo;
	viewportState.viewportCount = 1;
	viewportState.scissorCount = 1;

	colorBlending: VkPipelineColorBlendStateCreateInfo;
	colorBlending.logicOpEnable = VK_FALSE;
	colorBlending.logicOp = .COPY;
	colorBlending.attachmentCount = 1;
	colorBlending.pAttachments = *builder.colorBlendAttachment;

	vertexInputInfo: VkPipelineVertexInputStateCreateInfo;

	pipelineInfo: VkGraphicsPipelineCreateInfo;
	pipelineInfo.pNext = *builder.renderInfo;
	pipelineInfo.stageCount = builder.shaderStages.count;
	pipelineInfo.pStages = builder.shaderStages.data;
	pipelineInfo.pVertexInputState = *vertexInputInfo;
	pipelineInfo.pInputAssemblyState = *builder.inputAssembly;
	pipelineInfo.pViewportState = *viewportState;
	pipelineInfo.pRasterizationState = *builder.rasterizer;
	pipelineInfo.pMultisampleState = *builder.multisampling;
	pipelineInfo.pColorBlendState = *colorBlending;
	pipelineInfo.pDepthStencilState = *builder.depthStencil;
	pipelineInfo.layout = builder.pipelineLayout;

	state: []VkDynamicState = .[.VIEWPORT, .SCISSOR];
	dynamicInfo: VkPipelineDynamicStateCreateInfo;
	dynamicInfo.pDynamicStates = state.data;
	dynamicInfo.dynamicStateCount = xx state.count;
	pipelineInfo.pDynamicState = *dynamicInfo;

	pipeline: VkPipeline;
	if vkCreateGraphicsPipelines(s.device, VK_NULL_HANDLE, 1, *pipelineInfo, null, *pipeline) == .SUCCESS {
		return pipeline;
	}
	else {
		// @todo: should probably crash the program here tbh
		print("Failed to create pipeline");
		return pipeline;
	}
}

builder_set_shaders :: (using builder: *PipelineBuilder, vertex: VkShaderModule, fragment: VkShaderModule) {
	shaderStages[0].stage = .VERTEX_BIT;
	shaderStages[0].module = vertex;
	shaderStages[0].pName = "main";

	shaderStages[1].stage = .FRAGMENT_BIT;
	shaderStages[1].module = fragment;
	shaderStages[1].pName = "main";
}

builder_set_multisample_none :: (using builder: *PipelineBuilder) {
	multisampling.sampleShadingEnable = VK_FALSE;
	multisampling.rasterizationSamples = .VK_SAMPLE_COUNT_1_BIT;
	multisampling.minSampleShading = 1.0;
	multisampling.pSampleMask = null;
	multisampling.alphaToCoverageEnable = VK_FALSE;
	multisampling.alphaToOneEnable = VK_FALSE;
}

builder_disable_blending :: (using builder: *PipelineBuilder) {
	colorBlendAttachment.colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT;
	colorBlendAttachment.blendEnable = VK_FALSE;
}

builder_set_color_attachment_format :: (using builder: *PipelineBuilder, format: VkFormat) {
	colorAttachmentFormat = format;
	renderInfo.colorAttachmentCount = 1;
	renderInfo.pColorAttachmentFormats = *colorAttachmentFormat;
}

builder_set_depth_attachment_format :: (using builder: *PipelineBuilder, format: VkFormat) {
	renderInfo.depthAttachmentFormat = format;
}

builder_enable_depthtest :: (using builder: *PipelineBuilder, depthWriteEnable: bool, op: VkCompareOp) {
	depthStencil.depthTestEnable = VK_TRUE;
	depthStencil.depthWriteEnable = cast(VkBool32) depthWriteEnable;
	depthStencil.depthCompareOp = op;
	depthStencil.depthBoundsTestEnable = VK_FALSE;
	depthStencil.stencilTestEnable = VK_FALSE;
	depthStencil.front = .{};
	depthStencil.back = .{};
	depthStencil.minDepthBounds = 0.0;
	depthStencil.maxDepthBounds = 1.0;
}
