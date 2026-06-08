package main

import "core:os"
import "core:fmt"
import "core:log"
import "core:time"
import "core:dynlib"

MODULE_DIRPATH :: "game"
// TODO: use when
when ODIN_OS == .Windows {
	MODULE_DYNLIB_FILENAME :: MODULE_DIRPATH + ".dll"
} else when ODIN_OS == .Linux {
	MODULE_DYNLIB_FILENAME :: MODULE_DIRPATH + ".so"
}

when ODIN_OS == .Windows {
	ARG_BUILD_MODE :: "-build-mode:dll"
} else when ODIN_OS == .Linux {
	ARG_BUILD_MODE :: "-build-mode:shared"
}

ARG_OUTPUT :: "-out:" + MODULE_DYNLIB_FILENAME

// Returns true if a source file in the module's package directory is more up to date
// than dynlib.
// TODO: need to store another time indicating last compile attempt
module_needs_update :: proc() -> bool {
    module_dynlib_time, err := os.modification_time_by_path(MODULE_DYNLIB_FILENAME)
    if err != nil {
        return true
    }
    walker := os.walker_create(MODULE_DIRPATH)
    defer os.walker_destroy(&walker)
    for info in os.walker_walk(&walker) {
        _ = os.walker_error(&walker) or_break
        time_diff := time.diff(module_dynlib_time, info.modification_time)
        if time_diff > 0 {
            return true
        }
    }
    return false
}


compile_module :: proc() -> bool {
	compile_commmad := []string {
        "odin",
        "build",
        MODULE_DIRPATH,
        "-debug",
        ARG_BUILD_MODE,
        ARG_OUTPUT,
        "-collection:odinlib=../odinlib",
        "-define:BACKEND=none"
	}

	cwd, _ := os.get_working_directory(context.allocator)
	process_state, stdout_str, stderr_str, _ := os.process_exec(
		os.Process_Desc {
			working_dir=cwd,
			command=compile_commmad,
			stdin=os.stdin,
		},
		context.allocator
	)
    game.module.last_compile_attempt = time.now()

	fmt.printfln(transmute(string)stdout_str)
	fmt.printfln(transmute(string)stderr_str)

	log.debugf("Compile status: %v", process_state.exit_code)
    return process_state.exit_code == 0
}

load_module :: proc() {
	if game.module.dynlib_ptr != nil {
		if game.module.procs.shutdown != nil {
	        game.module.procs.shutdown()
	    }
	    dynlib.unload_library(game.module.dynlib_ptr)
	}
    game.module = {}
    if module_needs_update() {
        compile_module()
        time.sleep(500 * time.Millisecond)
    }

	did_load: bool
	game.module.dynlib_ptr, did_load = dynlib.load_library(MODULE_DYNLIB_FILENAME)
    if did_load {
		init_proc := dynlib.symbol_address(game.module.dynlib_ptr, "module_init")
        update_render_proc := dynlib.symbol_address(game.module.dynlib_ptr, "module_update_render")
		handle_event_proc := dynlib.symbol_address(game.module.dynlib_ptr, "module_handle_event")
		shutdown_proc := dynlib.symbol_address(game.module.dynlib_ptr, "module_shutdown")
        if init_proc != nil &&
            update_render_proc != nil &&
            handle_event_proc != nil &&
            shutdown_proc != nil
        {
            game.module.procs =  {
                init=cast(Module_Init_Proc)init_proc,
                update_render=cast(Module_Update_Proc)update_render_proc,
                handle_event=cast(Module_Handle_Event_Proc)handle_event_proc,
                shutdown=cast(Module_Shutdown_Proc)shutdown_proc,
            }
        } else {
        	// TODO: Handle if all required procs weren't loaded
        }
	}
}
