package main
import "odinlib:util"
import "odinlib:file_load"
import "core:log"
import "core:math/rand"
import "core:thread"
import "core:time"
import "core:fmt"
import "core:math"
import "core:os"
import "core:dynlib"
import "core:sync"
import "core:math/bits"
import stbtt "vendor:stb/truetype"
import stbi "vendor:stb/image"


// TODO: Rename eng_ and Engine_ to eng_ and Engine_
// Purpose of this abstraction layer is to hotload "modules" (the actual game code)

vec2f :: util.vec2f

PLATFORM_BACKEND :: #config(BACKEND, "native")

THUMBSTICK_THRESHOLD :: 0.5

FONT_PATH :: "resources/DejaVu Sans Mono_512x512x16x16.png"

// Struct to initialize the game
Engine_Init :: struct #all_or_none {
    // gl_set_proc_address=win.gl_set_proc_address,
    set_gamepad_rumble_proc: proc(weak, strong: f32),
    platform_command_proc: proc(_: util.Platform_Command),
    get_window_dpi: proc() -> i32,
    pixel_format: util.Pixel_Format
}

Engine_Update :: struct #all_or_none {
	window_size: vec2,
    gamepad_state: util.Gamepad_State,
    is_gamepad_connected: bool,
    framebuffer: util.Pixmap,
}

Engine_Context :: struct {
    running: bool,
    init_info: Engine_Init,
    update_info: Engine_Update,
    mouse_position: vec2,
    player_position: vec2f,
    position: vec2f,
    target_direction: enum {None, Up, Down, Left, Right},
    direction: vec2f,
    input_state: util.Input_State,
    font_atlas: util.Pixmap,
    render_group: Render_Group,

    module: struct {
        dynlib_ptr: dynlib.Library,
        last_compile_attempt: time.Time,
        using procs: struct {
            init: Module_Init_Proc,
            update_render: Module_Update_Proc,
            handle_event: Module_Handle_Event_Proc,
            shutdown: Module_Shutdown_Proc,
        }
    }
}

Module_Init_Proc         :: #type proc(_: ^Engine_Context)
Module_Update_Proc       :: #type proc()
Module_Handle_Event_Proc :: #type proc(event: util.Window_Event)
Module_Shutdown_Proc     :: #type proc()

game: ^Engine_Context

eng_init :: proc(init_info: Engine_Init) -> bool {
    game = new(Engine_Context)
    game.running = true
    game.init_info = init_info
    init_info.platform_command_proc(util.Platform_Command{
    	type=.Rename_Window,
    	title="Puckman"
    })
    init_info.platform_command_proc(util.Platform_Command{
    	type=.Resize_Window,
    	size=vec2{640, 480},
    })

    load_ok: bool
    game.font_atlas, load_ok = file_load.load_png(FONT_PATH, init_info.pixel_format)
    assert(load_ok)

    load_module()

    if game.module.init != nil {
        game.module.init(game)
    }

    return true
}

eng_shutdown :: proc() {
    if game.module.shutdown != nil {
        game.module.shutdown()
    }
}

eng_update_render :: proc(update_info: Engine_Update) -> bool {
    if game == nil {
        return true
    }
	if !game.running {
		eng_shutdown()
		return false
	}
	game.update_info = update_info
	game.input_state.gamepad = update_info.gamepad_state
	move_player()
    render_group_push(&game.render_group, color_yellow)
    render_group_push(&game.render_group, Render_Pixmap{pixmap=game.font_atlas})
    set_direction_from_input()
    if game.target_direction != nil {
    	log.debug(game.target_direction)
    }
    rect_color := color_orange
    rect_color.a = 1.0
    render_group_push(
        &game.render_group,
        Render_Fill_Rect{
        rect=util.rect_to_centered(
            Rectf{game.position.x, game.position.y, 100, 100}
        ),
        color=rect_color,
    })


    if game.module.update_render != nil {
        game.module.update_render()
    }
    render_group_to_output(&game.render_group, game.update_info.framebuffer)
    game.input_state.transient = {}
    return game.running
}

eng_handle_event :: proc(window_event: util.Window_Event) {
	util.set_input_state_from_event(&game.input_state, window_event)
	#partial switch window_event.type {
    case .Mouse_Move:
        game.mouse_position = window_event.vec2
    case .Key:
        if window_event.key.pressed {
            switch window_event.key.keycode{
            case util.KEY_ESCAPE:
                game.running = false
            }
        }
    case .Window_Close:
    	game.running = false
    }

    if game.module.handle_event != nil {
        game.module.handle_event(window_event)
    }
}

move_player :: proc() {
	#partial switch game.target_direction {
	case .Left:
		game.direction = vec2f{-1, 0}
	case .Right:
		game.direction = vec2f{1, 0}
	case .Up:
		game.direction = vec2f{0, -1}
	case .Down:
		game.direction = vec2f{0, 1}
	}
}

// Sets player's target direction from input.
// Gamepad input has priority over keyboard
set_direction_from_input :: proc() {
	game.target_direction = nil
	switch {
	case .LEFT in game.input_state.gamepad.hat:
		game.target_direction = .Left
	case .RIGHT in game.input_state.gamepad.hat:
		game.target_direction = .Right
	case .UP in game.input_state.gamepad.hat:
		game.target_direction = .Up
	case .DOWN in game.input_state.gamepad.hat:
		game.target_direction = .Down
	}
	// Read thumbstick input if dpad is not pressed
	if game.target_direction == nil {
		switch {
		case game.input_state.gamepad.axes[.LEFT_X] < -THUMBSTICK_THRESHOLD:
			game.target_direction = .Left
		case game.input_state.gamepad.axes[.LEFT_X] > THUMBSTICK_THRESHOLD:
			game.target_direction = .Right
		case game.input_state.gamepad.axes[.LEFT_Y] < -THUMBSTICK_THRESHOLD:
			game.target_direction = .Up
		case game.input_state.gamepad.axes[.LEFT_Y] > THUMBSTICK_THRESHOLD:
			game.target_direction = .Down
		}
	}
	// Read keyboard input if not input from gamepad
	if game.target_direction == nil {
		switch {
		case util.bit_test(game.input_state.keyboard[:], util.KEY_LEFT):
			game.target_direction = .Left
		case util.bit_test(game.input_state.keyboard[:], util.KEY_RIGHT):
			game.target_direction = .Right
		case util.bit_test(game.input_state.keyboard[:], util.KEY_UP):
			game.target_direction = .Up
		case util.bit_test(game.input_state.keyboard[:], util.KEY_DOWN):
			game.target_direction = .Down
		}
	}
}

