DescriptorLayoutBuilder :: struct {
	bindings : [..]VkDescriptorSetLayoutBinding;
	bindings.allocator = temp;
}

add_binding_to_builder :: (builder: *DescriptorLayoutBuilder, binding: u32, type: VkDescriptorType) {
	newBind: VkDescriptorSetLayoutBinding;
	newBind.binding = binding;
	newBind.descriptorCount = 1;
	newBind.descriptorType = type;
	
	array_add(*builder.bindings, newBind);
}

build_descriptor_layout :: (builder: *DescriptorLayoutBuilder, device: VkDevice, shaderStages: VkShaderStageFlags, pNext: *void = null, flags: VkDescriptorSetLayoutCreateFlags = 0) -> VkDescriptorSetLayout {
	for *builder.bindings it.stageFlags |= shaderStages;

	info: VkDescriptorSetLayoutCreateInfo;
	info.pNext = pNext;
	info.pBindings = builder.bindings.data;
	info.bindingCount = xx builder.bindings.count;
	info.flags = flags;

	set: VkDescriptorSetLayout;
	result := vkCreateDescriptorSetLayout(device, *info, null, *set);
	assert(result == .SUCCESS, "Could not create descriptor set layout");
	return set;
}

DescriptorAllocator :: struct {
	pool: VkDescriptorPool;
}

PoolSizeRatio :: struct {
	type: VkDescriptorType;
	ratio: float;
}

init_pool :: (device: VkDevice, maxSets: u32, poolRatios: []PoolSizeRatio) -> DescriptorAllocator {
	poolSizes: []VkDescriptorPoolSize;
	poolSizes.count = poolRatios.count;
	poolSizes.data = temporary_alloc(poolSizes.count * size_of(VkDescriptorPoolSize));

	for poolRatios {
		poolSizes[it_index] = .{ type = it.type, descriptorCount = cast(u32) it.ratio * maxSets };
	}

	poolInfo: VkDescriptorPoolCreateInfo;
	poolInfo.flags = 0;
	poolInfo.maxSets = maxSets;
	poolInfo.poolSizeCount = xx poolSizes.count;
	poolInfo.pPoolSizes = poolSizes.data;

	allocator: DescriptorAllocator;
	result := vkCreateDescriptorPool(device, *poolInfo, null, *allocator.pool);
	assert(result == .SUCCESS, "Failed to create descriptor pool");

	return allocator;
}

clear_descriptor_allocator :: (allocator: *DescriptorAllocator, device: VkDevice) {
	result := vkResetDescriptorPool(device, allocator.pool, 0);
	assert(result == .SUCCESS, "Failed to clear descriptor allocator");
}

destroy_descriptor_allocator :: (allocator: *DescriptorAllocator, device: VkDevice) { 
	vkDestroyDescriptorPool(device, allocator.pool, null);
}

allocate_descriptor_set :: (allocator: *DescriptorAllocator, device: VkDevice, layout: VkDescriptorSetLayout) -> VkDescriptorSet {
	allocInfo: VkDescriptorSetAllocateInfo;
	allocInfo.descriptorPool = allocator.pool;
	allocInfo.descriptorSetCount = 1;
	allocInfo.pSetLayouts = *layout;

	ds: VkDescriptorSet;
	result:= vkAllocateDescriptorSets(device, *allocInfo, *ds);
	assert(result == .SUCCESS, "Failed to allocate descriptor set");
	return ds;
}
