#import "Basic";
#import "Compiler";
#import "File";
#import "Process";

BUILD_DEBUG_DIR :: "run/debug";
BUILD_OPTIMIZED_DIR :: "run/optimized";
BUILD_RELEASE_DIR :: "run/release";



build :: ()
{
    w := compiler_create_workspace();

    target_options := get_build_options(w);
    args := target_options.compile_time_command_line;
    
    buildOptimized := false;
    buildRelease := false;
    
    for arg: args
    {
    	if arg ==
    	{
    		case "optimized";
    			buildOptimized = true;
    		case "release";
    			buildRelease = true;
    	}
    }
    
	// build shaders
	make_directory_if_it_does_not_exist(".build/");
	build_shader :: (input: string, output: string) {
		processResult, outputStr, errorStr := run_command("glslc", input, "-o", output, print_captured_output=true);
		if processResult.exit_code != 0 compiler_report(errorStr);
	}

	build_shader("shaders/gradient.comp", ".build/gradient.comp.bin");
	build_shader("shaders/imgui.frag", ".build/imgui.frag.bin");
	build_shader("shaders/imgui.vert", ".build/imgui.vert.bin");
	build_shader("shaders/colored_triangle_mesh.vert", ".build/colored_triangle_mesh.vert.bin");
	build_shader("shaders/colored_triangle.vert", ".build/colored_triangle.vert.bin");
	build_shader("shaders/colored_triangle.frag", ".build/colored_triangle.frag.bin");

    target_options.output_executable_name = "vulkan";
	set_build_options(target_options, w);
    
    // There are 3 target types in this program :
    // 	- Debug : Not optimized and has debug info
    // 	- Optimized : Optimized and has debug info
    // 	- Release : Very optimized and doesn't have debug info
    if buildRelease then build_release(w);
    else if buildOptimized then build_optimized(w);
    else build_debug(w);
    
	// add some helpers and defines
	add_build_string(#string DONE
	SHADER_GET :: (name: string) -> [] u8 {
		#import "File";
		#import "Basic";
		return xx read_entire_file(tprint(".build/%.bin", name));
	}
	BuildType :: enum u8
	{
		DEBUG;
		OPTIMIZED;
		RELEASE;
	}
	GfxBackend :: enum u8
	{
		VULKAN;
		DX12;
	}
	GFX_BACKEND :: GfxBackend.VULKAN;
	DONE, w);

    add_build_file("src/main.jai", w);
    
    set_build_options_dc(.{do_output=false});
}

build_debug :: (w: Workspace)
{
    target_options := get_build_options(w);
    target_options.backend =.X64; 
    target_options.output_path = BUILD_DEBUG_DIR;
    set_optimization(*target_options, Optimization_Type.DEBUG, true);
    set_build_options(target_options, w);
    add_build_string("BUILD_TYPE :: BuildType.DEBUG;", w);
}

build_optimized :: (w: Workspace)
{
    target_options := get_build_options(w);
    target_options.backend = .X64;
    target_options.output_path = BUILD_OPTIMIZED_DIR;
    set_optimization(*target_options, Optimization_Type.OPTIMIZED);   
    set_build_options(target_options, w);
    add_build_string("BUILD_TYPE :: BuildType.OPTIMIZED;", w);
}

build_release :: (w: Workspace)
{
    target_options := get_build_options(w);
    target_options.backend = .LLVM;
    target_options.output_path = BUILD_RELEASE_DIR;
    target_options.emit_debug_info=.NONE;
    target_options.enable_bytecode_inliner = true;
    set_optimization(*target_options, Optimization_Type.VERY_OPTIMIZED);   
    set_build_options(target_options, w);
    add_build_string("BUILD_TYPE :: BuildType.RELEASE;", w);
}

main :: () {}

#run build();
