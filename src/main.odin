package src
import "odinlib:util"
import "core:log"
import "core:math/rand"
import "core:thread"
import "core:os"

vec2 :: util.vec2
vec2f :: util.vec2f

PLATFORM_BACKEND :: #config(BACKEND, "native")

map_ :=[?]i32 {
	0, 0, 1, 0, 0,
	0, 1, 1, 1, 0,
	0, 0, 1, 0, 0,
	0, 1, 0, 0, 0,
	0, 1, 0, 0, 0,
}

// Struct to initialize the game
Game_Init :: struct {
    // gl_set_proc_address=win.gl_set_proc_address,
    set_gamepad_rumble_proc: proc(weak, strong: f32),
    platform_command_proc: proc(_: util.Platform_Command),
    get_window_dpi: proc() -> i32,
    window_size: vec2,
}

Game_Update :: struct {
    window_size: vec2,
    gamepad_state: util.Gamepad_State,
    is_gamepad_connected: bool,
    framebuffer: util.Pixmap,
}

Game_Context :: struct {
    running: bool,
    mouse_position: vec2,
    player_position: vec2f,
    position: vec2f,
    direction: vec2f,
    thread_pool: thread.Pool,
    input_state: util.Input_State,
}

game: Game_Context

game_init :: proc(game_init: Game_Init) -> bool {
    game.running = true
    game_init.platform_command_proc(util.Platform_Command{
    	type=.Rename_Window,
    	title="Puckman"
    })
    game_init.platform_command_proc(util.Platform_Command{
    	type=.Resize_Window,
    	size=vec2{640, 480},
    })
    return true
}

move_player :: proc() {
	if util.bit_test(game.input_state.keyboard[:], cast(uint) util.KEY_UP) {
		game.direction = vec2f{0, -1}
	}
	if util.bit_test(game.input_state.keyboard[:], cast(uint) util.KEY_DOWN) {
		game.direction = vec2f{0, 1}
	}
	if util.bit_test(game.input_state.keyboard[:], cast(uint) util.KEY_LEFT) {
		game.direction = vec2f{-1, 0}
	}
	if util.bit_test(game.input_state.keyboard[:], cast(uint) util.KEY_RIGHT) {
		game.direction = vec2f{1, 0}
	}
}

game_update_render :: proc(game_update: Game_Update) -> bool {
	game.input_state.gamepad = game_update.gamepad_state
	game.position += game.direction
    game.position = cast(vec2f)game.mouse_position
    move_player()
    pixmap_fill(
        game_update.framebuffer,
        color_black
    )
    rect_color := color_orange
    rect_color.a = 0.2
    fill_rect(
        game_update.framebuffer,
        util.rect_to_centered(
            Rect{cast(i32)game.position.x, cast(i32)game.position.y, 100, 100}
        ),
        rect_color
    )
    game.input_state.transient = {}
    return game.running
}

game_handle_event :: proc(window_event: util.Window_Event) {
	util.set_input_state_from_event(&game.input_state, window_event)
	#partial switch window_event.type {
    case .Mouse_Move:
        game.mouse_position = window_event.vec2
    case .Key:
        if window_event.key.pressed {
            switch window_event.key.keycode{
            case util.KEY_ESCAPE: {
                game.running = false
            }
            case util.KEY_UP:
               game.direction = {0, -1}
            case util.KEY_DOWN:
               game.direction = {0, 1}
            case util.KEY_LEFT:
               game.direction = {-1, 0}
            case util.KEY_RIGHT:
               game.direction = {1, 0}
            }
        }
    }
    log.debug(window_event)
}
