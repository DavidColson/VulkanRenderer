// Bindings for Dear ImGui.

ImVec2      :: Vector2;
ImVec4      :: Vector4;
ImColor     :: Vector4;

ImVector :: struct (T: Type) {
    Size: s32;
    Capacity: s32;
    Data: *T;
}

for_expansion :: (vector: ImVector, body: Code, flags: For_Flags) #expand {
	for i: 0..vector.Size - 1 {
		`it_index := i;
		`it := vector.Data[i];
		
		#insert body;
	}
}

vector_push_back :: (vector: *ImVector($T), data: T) #no_abc {
	vector_maybe_grow(vector);
	vector.Data[vector.Size] = data;
	vector.Size += 1;
}

ImDrawCallback :: #type (parent_list: *ImDrawList, cmd: *ImDrawCmd) #c_call;

#scope_module

#import "Basic";
#import "Math";

#if OS == .WINDOWS {
    #load "windows.jai";
    #system_library,link_always "user32"; // Needed by imgui unless ImGui is compiled it with "IMGUI_DISABLE_WIN32_DEFAULT_CLIPBOARD_FUNCS"
	#system_library,link_always "shell32";
} else {
    #load "unix.jai";
}

#scope_file

vector_maybe_grow :: (vector: *ImVector($T))
{
	if vector.Size >= vector.Capacity {
		reserve := 2 * vector.Capacity;
		if reserve < 8 then reserve = 8;
		
		vector_reserve(vector, reserve, xx size_of(T));
	}
}

vector_reserve :: (vector: *ImVector, desired_items: s32, size: s32) {
	if desired_items <= vector.Capacity then return;
	
	// ImVector doesn't store the allocator, so I assume the one 
	// in the context was used to allocate the data
	vector.Data = realloc(vector.Data, desired_items * size, vector.Capacity * size);
	assert(vector.Data != null);
	vector.Capacity = desired_items;
}
