package src
import "odinlib:util"
import "odinlib:file_load"
import "core:log"
import "core:math/rand"
import "core:thread"
import "core:time"
import "core:fmt"
import "core:math"
import "core:os"
import "core:sync"
import "core:math/bits"
import stbtt "vendor:stb/truetype"
import stbi "vendor:stb/image"

vec2 :: util.vec2
vec2f :: util.vec2f

PLATFORM_BACKEND :: #config(BACKEND, "native")

THUMBSTICK_THRESHOLD :: 0.5

MAP_DIMS := vec2{5, 7}

map_ :=[?]i32 {
	1, 1, 1, 1, 1,
	0, 0, 1, 0, 0,
	0, 1, 1, 1, 0,
	0, 0, 1, 0, 0,
	0, 1, 0, 0, 0,
	0, 1, 0, 0, 0,
	1, 1, 1, 1, 1,
}

FONT_PATH :: "resources/DejaVu Sans Mono_512x512x16x16.png"

// Struct to initialize the game
Game_Init :: struct {
    // gl_set_proc_address=win.gl_set_proc_address,
    set_gamepad_rumble_proc: proc(weak, strong: f32),
    platform_command_proc: proc(_: util.Platform_Command),
    get_window_dpi: proc() -> i32,
    window_size: vec2,
    pixel_format: util.Pixel_Format
}

Game_Update :: struct {
	window_size: vec2,
    gamepad_state: util.Gamepad_State,
    is_gamepad_connected: bool,
    framebuffer: util.Pixmap,
}

Game_Context :: struct {
    running: bool,
    update_info: Game_Update,
    mouse_position: vec2,
    player_position: vec2f,
    position: vec2f,
    target_direction: enum {None, Up, Down, Left, Right},
    direction: vec2f,
    input_state: util.Input_State,
    font_atlas: util.Pixmap
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

    load_ok: bool
    game.font_atlas, load_ok = file_load.load_png(FONT_PATH)
    assert(load_ok)

    return true
}

game_shutdown :: proc() {

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

game_update_render :: proc(game_update: Game_Update) -> bool {
	if !game.running {
		game_shutdown()
		return false
	}
	game.update_info = game_update
	game.input_state.gamepad = game_update.gamepad_state
	move_player()
	game.position += game.direction
    // game.position = cast(vec2f)game.mouse_position
    game.position.x = math.clamp(game.position.x, 0, cast(f32)game_update.framebuffer.w)
    game.position.y = math.clamp(game.position.y, 0, cast(f32)game_update.framebuffer.h)
    pixmap_fill(
        game_update.framebuffer,
        color_black
    )
    blit(game_update.framebuffer, game.font_atlas, {0, 0})
    for tile in map_ {
  		tile_rect := Rect {}
    	tile_color := color_black if tile != 0 else color_blue
     	// TODO: draw tile rect
     }
    }
    set_direction_from_input()
    if game.target_direction != nil {
    	log.debug(game.target_direction)
    }
    rect_color := color_orange
    rect_color.a = 1.0
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
            case util.KEY_ESCAPE:
                game.running = false
            }
        }
    case .Window_Close:
    	game.running = false
    }
}
