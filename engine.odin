#+feature dynamic-literals
package main
import "odinlib:util"
import "odinlib:file_load"
import "core:log"
import "core:math/rand"
import "core:thread"
import "core:time"
import "core:fmt"
import "core:slice"
import "core:math"
import "core:os"
import "core:dynlib"
import "core:sync"
import "core:math/bits"
import stbtt "vendor:stb/truetype"
import stbi "vendor:stb/image"

Sim_Tick :: int

vec2f :: util.vec2f
color_cyan_4b :: Color4b {0, 0xff, 0xff, 0xff}
color_yellow_4b :: Color4b {0xff, 0xff, 0x00, 0xff}
color_green_4b :: Color4b {0, 0xff, 0, 0xff}
color_blue_4b :: Color4b {0, 0x00, 0xff, 0xff}
color_red_4b :: Color4b {0xff, 0, 0, 0xff}
color_grey_4b :: Color4b {0x7f, 0x7f, 0x7f, 0xff}
color_white_4b :: Color4b {0xff, 0xff, 0xff, 0xff}
color_black_4b :: Color4b {0x00, 0x00, 0x00, 0xff}
color_purple_4b :: Color4b {0xb0, 0x00, 0xff, 0xff}
color_brown_4b :: Color4b{0x8f, 0x51, 0x29, 0xff}
color_tortilla_4b :: Color4b{0x99, 0x79, 0x50, 0xff}
color_lemon_4b :: Color4b {0xef, 0xfd, 0x5f, 0xff}

PLATFORM_BACKEND :: #config(BACKEND, "native")

THUMBSTICK_THRESHOLD :: 0.5

CELL_SIZE: i32 : 8
CELL_DIMS :: vec2{CELL_SIZE, CELL_SIZE}
COLS: i32 : 28
ROWS: i32 : 36
PLAYER_SIZE_CELLS :: 2
PLAYER_SIZE: i32 : PLAYER_SIZE_CELLS * CELL_SIZE
PLAYER_DIMS :: vec2{PLAYER_SIZE, PLAYER_SIZE}
INTERN_FRAMEBUFFER_WIDTH  :: CELL_SIZE * COLS
INTERN_FRAMEBUFFER_HEIGHT :: CELL_SIZE * ROWS
INTERN_FRAMEBUFFER_DIMS :: vec2{INTERN_FRAMEBUFFER_WIDTH, INTERN_FRAMEBUFFER_HEIGHT}
DEBUG_TEXT_WIDTH: i32 :64*CELL_SIZE

MAX_FRAMEBUFFER_SCALE: i32 : 4

// Struct to initialize the game
Engine_Init :: struct #all_or_none {
    // gl_set_proc_address=win.gl_set_proc_address,
    set_gamepad_rumble_proc: proc(weak, strong: f32),
    platform_command_proc: proc(_: util.Platform_Command),
    get_window_dpi: proc() -> i32,
    pixel_format: util.Pixel_Format
}

Engine_Update :: struct #all_or_none {
	window_dims: vec2,
    gamepad_state: util.Gamepad_State,
    is_gamepad_connected: bool,
    framebuffer: util.Pixmap,
}

Engine_Context :: struct {
    running: bool,
    state: Game_State,
    title_screen_end_sim_ticks: Sim_Tick,
    step_mode: bool,
    input_rle: Input_RLE,
    init_info: Engine_Init,
    update_info: Engine_Update,
    mouse_position: vec2,
    scaled_framebuffer_dims: vec2,
    debug_mode: Debug_Mode,
    position: vec2f,
    user_input_direction: Direction,
    action_buttons_pressed: [2]bool,
    editor: Editor_State,
    internal_framebuffer: [INTERN_FRAMEBUFFER_WIDTH*INTERN_FRAMEBUFFER_HEIGHT]ColorU32,
    input_file: ^os.File,
    // Row-major
    tile_map, full_tile_map: [ROWS*COLS]Tile_Type,
    marker_map: [ROWS*COLS]Marker_Tile_Type,
    // Double buffer of input states
    input_state_dbuff: [2]util.Input_State,
    // These swap every frame
    input_state, old_input_state: ^util.Input_State,
    player_spritesheet:  util.Pixmap,
    player: Player,
    spritesheet: Pixmap,
    ghost_global_mode: Ghost_Global_Mode,
    ghost_mode_switch_interval_index: int,
    ghosts: [Ghost_Type]Ghost_Actor,
    eaten_ghost: Ghost_Type,
    ghost_pass_tile_coord, ghost_revive_tile_coord,  ghost_exit_tile_coord: Tile_Coord,
    render_group: Render_Group,
    last_frame_cpu_tick: time.Tick,
    rumble_end_sim_tick: Sim_Tick,
    sim_ticks: Sim_Tick,
    frame_counter: int,
    mode_switch_sim_ticks_remaining, frightened_sim_ticks_remaining: Sim_Tick,
    freeze_end_sim_tick: Sim_Tick,
    rumble_end_cpu_tick: Maybe(time.Tick),
    freeze_type: Freeze_Type,
    dbgtext: Dbg_Text,
    lag: time.Duration,
    anim, death_anim, ghost_anim: Sprite_Animator,
    window_size: vec2,
    framebuffer_scale: i32,
    palette: Palette,
    paused: bool,
    ghost_eat_count: i32,
    level_count, max_num_dots, dots_remaining: i32,
    text_src_offset_map: map[rune]vec2,
    enable_debug_text: bool,
    attract_mode: bool,
    input_buffer: [4096]u8,
    quit_input_cpu_tick: time.Tick,
}

game: ^Engine_Context
// Game "world" updates 60 times per second
SIM_UPDATE_HZ :: 60
SIM_UPDATE_INTERVAL :: (time.Duration)(cast(f32)time.Second/cast(f32)SIM_UPDATE_HZ)
SIM_LAG_MAX :: 30 * SIM_UPDATE_INTERVAL

eng_init :: proc(init_info: Engine_Init) -> bool {
    game = new(Engine_Context)
    game.running = true
    game.init_info = init_info
    for arg in os.args {
        if true || arg == "-debug" {
            game.enable_debug_text = true
            open_err: os.Error
            game.input_file, open_err = os.open("input.txt", {.Create, .Trunc, .Write})
            assert(open_err == nil)
        } 
        if arg == "--show-input" {
            os.close(game.input_file)
            input_data, read_err := os.read_entire_file_from_path("input.txt", context.allocator)
            assert(read_err == nil, "Could not open 'input.txt'")
            // TODO: Output input data
            os.exit(0)
        }
    }
    game.input_rle.buffer = game.input_buffer[:]
    game.framebuffer_scale = 2
    init_info.platform_command_proc(util.Platform_Command{
    	type=.Rename_Window,
    	title="Puckman"
    })
    init_info.platform_command_proc(util.Platform_Command {
        type=.Set_Window_Min_Size,
        size=INTERN_FRAMEBUFFER_DIMS,
    })
    new_size := game.framebuffer_scale*INTERN_FRAMEBUFFER_DIMS
    if game.enable_debug_text {
        new_size.x += DEBUG_TEXT_WIDTH
    }
    init_info.platform_command_proc(util.Platform_Command{
    	type=.Resize_Window,
        size=new_size,
    })
    init_info.platform_command_proc(util.Platform_Command {
    	type=.Change_Window_Icon,
    	path="textures/icon.ico",
    })

    game.input_state = &game.input_state_dbuff[0]
    game.old_input_state = &game.input_state_dbuff[1]

    rg_init()
    dbgtext_init(&game.dbgtext)

    // DELETE:
    game.level_count = 1

    game.player.direction = .None
    game.player.num_lives = 3

    game.render_group.palette = game.palette

    load_ok: bool
    game.spritesheet, load_ok = load_bmp_indexed("textures/spritesheet.bmp", &game.palette, init_info.pixel_format)
    assert(load_ok)

    load_tile_map()
    reset_level()
    game.state = .Maze

    game.paused = true
    game.lag = SIM_UPDATE_INTERVAL

    game.debug_mode = .Ghost_Target

    game.ghost_mode_switch_interval_index = 0

    game.anim = Sprite_Animator {
   		end_frame=2,
    	frame_interval=50*time.Millisecond,
    	repeat_mode=.Ping_Pong,
    	inc=1,
    }

    game.last_frame_cpu_tick = time.tick_now()

    anim_reset(&game.anim, game.last_frame_cpu_tick)

    game.death_anim = Sprite_Animator {
        end_frame=len(PACMAN_DEATH_FRAMES)-1,
        frame_interval=250*time.Millisecond,
        repeat_mode=.None,
        inc=1,
    }

    game.ghost_anim = Sprite_Animator {
    	end_frame=1,
	    frame_interval=100*time.Millisecond,
	    repeat_mode=.Ping_Pong,
		inc=1,
    }
    anim_reset(&game.ghost_anim, game.last_frame_cpu_tick)
    set_freeze_type(.Ready, 2*SIM_UPDATE_HZ)

    game.text_src_offset_map = {
        'A' = {0*CELL_SIZE, 40},
        'B' = {1*CELL_SIZE, 40},
        'C' = {2*CELL_SIZE, 40},
        'D' = {3*CELL_SIZE, 40},
        'E' = {4*CELL_SIZE, 40},
        'F' = {5*CELL_SIZE, 40},
        'G' = {6*CELL_SIZE, 40},
        'H' = {7*CELL_SIZE, 40},
        'I' = {8*CELL_SIZE, 40},
        'J' = {9*CELL_SIZE, 40},
        'K' = {10*CELL_SIZE, 40},
        'L' = {11*CELL_SIZE, 40},
        'M' = {12*CELL_SIZE, 40},
        'N' = {13*CELL_SIZE, 40},
        'O' = {14*CELL_SIZE, 40},
        'P' = {15*CELL_SIZE, 40},
        'Q' = {16*CELL_SIZE, 40},
        'R' = {17*CELL_SIZE, 40},
        'S' = {18*CELL_SIZE, 40},
        'T' = {19*CELL_SIZE, 40},
        'U' = {20*CELL_SIZE, 40},
        'V' = {21*CELL_SIZE, 40},
        'W' = {22*CELL_SIZE, 40},
        'X' = {23*CELL_SIZE, 40},
        'Y' = {24*CELL_SIZE, 40},
        'Z' = {25*CELL_SIZE, 40},
        '0' = {26*CELL_SIZE, 40},
        '1' = {27*CELL_SIZE, 40},
        '2' = {28*CELL_SIZE, 40},
        '3' = {29*CELL_SIZE, 40},
        '4' = {0*CELL_SIZE, 48},
        '5' = {1*CELL_SIZE, 48},
        '6' = {2*CELL_SIZE, 48},
        '7' = {3*CELL_SIZE, 48},
        '8' = {4*CELL_SIZE, 48},
        '9' = {5*CELL_SIZE, 48},
        '!' = {6*CELL_SIZE, 48},
        ':' = {7*CELL_SIZE, 48},
        '.' = {8*CELL_SIZE, 48},
        ',' = {9*CELL_SIZE, 48},
        '?' = {10*CELL_SIZE, 48},
        '"' = {11*CELL_SIZE, 48},
        '-' = {12*CELL_SIZE, 48},
        '_' = {12*CELL_SIZE, 48},
        '/' = {13*CELL_SIZE, 48},
        '%' = {14*CELL_SIZE, 48},
        '=' = {15*CELL_SIZE, 48},
        '(' = {16*CELL_SIZE, 48},
        ')' = {17*CELL_SIZE, 48},
        '[' = {18*CELL_SIZE, 48},
        ']' = {19*CELL_SIZE, 48},
    }

    // load_module()

    for arg in os.args {
        if arg == "-input" {
            // TODO:
        }
    }
    log.debug("GAME ENGINE SIZE:", size_of(game^))

    return true
}

eng_shutdown :: proc() {
    os.write(game.input_file, game.input_rle.buffer[:game.input_rle.write_index])
    os.close(game.input_file)
}

update_world :: proc() {
	if game.freeze_type == .None {
		update_player()
	}
    if game.freeze_type == .None || game.freeze_type == .Eat_Ghost {
        update_ghosts()
    }
    if game.frightened_sim_ticks_remaining == 0 {
        unfrighten_all()
    }
    // Only decrement frightened_ticks_remaining if not frozen
    if game.sim_ticks > game.freeze_end_sim_tick {
        if game.frightened_sim_ticks_remaining > -1 {
            game.frightened_sim_ticks_remaining -= 1
        }
    }
    calculate_ghost_targets()
    for ghost_index in Ghost_Type {
    	ghost_actor := &game.ghosts[ghost_index]
        // Check player collision with ghosts
        if ghost_actor.tile_coord == game.player.tile_coord {
            if ghost_actor.mode == .Frightened {
                ghost_actor.mode = .Eaten
                set_freeze_type(.Eat_Ghost)
                game.ghost_eat_count += 1
                game.player.score += (i32)(1 << cast(u32)game.ghost_eat_count) * 100
                game.eaten_ghost = ghost_index
                set_rumble(300*time.Millisecond, 0.5)
            } else if ghost_actor.mode != .Eaten {
                if game.freeze_type == .None {
                    set_freeze_type(.Death1)
                    set_rumble(700*time.Millisecond, 0.7)
                }
            }
            break
        }
    }
    if game.state == .Maze {
        if game.sim_ticks >= game.freeze_end_sim_tick {
            switch game.freeze_type {
            case .None:
            case .Cold_Start_Ready:
                game.level_count = 1
                set_freeze_type(.None)
            case .Ready:
                set_freeze_type(.None)
            case .Death1:
                set_freeze_type(.Death2, 3*SIM_UPDATE_HZ)
                anim_reset(&game.death_anim, game.last_frame_cpu_tick)
            case .Death2:
                // TODO: check lives left
                // If none, set to game over
                reset_actors()
                game.player.num_lives -= 1
                if game.player.num_lives < 0 {
                    set_freeze_type(.Game_Over, 2*SIM_UPDATE_HZ)
                } else {
                    set_freeze_type(.Ready, 2*SIM_UPDATE_HZ)
                }
            case .Clear_Maze1:
                set_freeze_type(.Clear_Maze2)
            case .Clear_Maze2:
                game.level_count += 1
                reset_level()
                set_freeze_type(.Ready, 2*SIM_UPDATE_HZ)
            case .Game_Over:
                game.level_count = 0
                game.attract_mode = true
                // TODO: back to attract mode
            case .Eat_Ghost:
                set_freeze_type(.None)
            }
        }
    }
}

eng_update_render :: proc(update_info: Engine_Update) -> bool {
	game.frame_counter += 1
    if game == nil {
        return true
    }
	if !game.running {
		eng_shutdown()
		return false
	}
	game.update_info = update_info
	game.input_state.gamepad = update_info.gamepad_state

	now := time.tick_now()
    diff := time.tick_diff(game.last_frame_cpu_tick, now)
	if !game.step_mode {
		game.lag += diff
	}
    game.last_frame_cpu_tick = now
    // Clear rumble if it's time
    if rumble_end_cpu_tick, is_set := game.rumble_end_cpu_tick.?; is_set {
        if time.tick_diff(rumble_end_cpu_tick, game.last_frame_cpu_tick) > 0 {
            game.init_info.set_gamepad_rumble_proc(0.0, 0.0)
            game.rumble_end_cpu_tick = nil
        }
    }

    util.set_axes_buttons(game.input_state, 0.5, 0.5)
    update_user_input_direction()
    if is_button_pressed(.BUMPER_LEFT) {
        change_debug_mode(-1)
    } else if is_button_pressed(.BUMPER_RIGHT) {
        change_debug_mode(1)
    }
    if is_button_pressed(.TRIGGER_LEFT) {
        increment_scale(-1)
    } else if is_button_pressed(.TRIGGER_RIGHT) {
        increment_scale(1)
    }
    #partial switch game.state {
    case .Maze:
        if is_button_pressed(.START) || is_key_pressed(util.KEY_ESCAPE) {
            game.paused = !game.paused
        }
        if is_any_key_pressed(util.KEY_F4, util.KEY_F5)  {
            game.running = false
        }
        if game.paused && (are_all_buttons_held({.SOUTH, .EAST}) || is_key_held(util.KEY_BACKSPACE))
        {
            if game.quit_input_cpu_tick == cast(time.Tick){} {
                game.quit_input_cpu_tick = game.last_frame_cpu_tick
            } else {
                diff := time.tick_diff(game.quit_input_cpu_tick, game.last_frame_cpu_tick)
                if diff > time.Second {
                    game.running = false
                }

            }
        } else {
            game.quit_input_cpu_tick = cast(time.Tick){}
        }
    case .Title: 
        if is_button_pressed(.START) || is_any_key_pressed(util.KEY_RETURN, util.KEY_SPACE) 
        {
            // TODO: start game
        }
    }
    

    do_update_sim := !game.paused && game.debug_mode != .Editor
    for do_update_sim && game.lag >= SIM_UPDATE_INTERVAL {
	    // Only update once if diff is too big (likely due to debugging)
	    if game.lag > SIM_LAG_MAX {
			game.lag = SIM_UPDATE_INTERVAL
	    }

        input_rle_record(&game.input_rle, game.user_input_direction)
        update_world()
        game.sim_ticks += 1
        game.lag -= SIM_UPDATE_INTERVAL
    }
    fb_pixmap := Pixmap {
        pixels=raw_data(game.internal_framebuffer[:]),
        w=INTERN_FRAMEBUFFER_WIDTH,
        h=INTERN_FRAMEBUFFER_HEIGHT,
        pitch=INTERN_FRAMEBUFFER_WIDTH*4,
        format=game.init_info.pixel_format,
    }
    game.render_group.palette = game.palette
    rg_texture(game.spritesheet)
    rg_clear(Color4b{80, 0, 0, 255} if game.step_mode else Color4b{0, 0, 27, 255})

    draw_maze()
    draw_player()
    draw_ghosts()
    rg_palette(1, color_white_4b)

    // Blacken screen if paused or in Ready freeze
    sim_tick_diff := game.freeze_end_sim_tick - game.sim_ticks 
    if game.debug_mode != .Editor && (game.paused || game.freeze_type == .Ready && sim_tick_diff > READY_BLANK_TICK_DIFF_MIN)
    {
        rg_clear(color_black_4b)
        if game.paused && game.debug_mode != .Editor {
            draw_text("paused!", get_position_from_tile_coord({9,18}))
            draw_text("Hold  or backspace to quit", get_position_from_tile_coord({0,21}))
            south_offset := get_position_from_tile_coord({4, 21})+4 + 100 * {0, cast(i32)triangle_func(cast(f32)game.input_state.mouse_position.x, 100)}
            // South
            blit_sprite( .Small, south_offset, vec2{15*CELL_SIZE, 32})
            // East
            blit_sprite( .Small, south_offset+{4,-4}, vec2{15*CELL_SIZE, 32})
            rg_palette(1, color_grey_4b)
            // North
            blit_sprite( .Small, south_offset+{0,-8}, vec2{15*CELL_SIZE, 32})
            // West
            blit_sprite( .Small, south_offset+{-4,-4}, vec2{15*CELL_SIZE, 32})
        }
    }
    #partial switch game.debug_mode {
   	case .None:
	    draw_text("HIGH SCORE", get_position_from_tile_coord({11, 0}))
	    score_text := fmt.tprintf("%02d", game.player.score)
	    draw_text(score_text, get_position_from_tile_coord({5, 1}))
    case .Ghost_Target:
        draw_text("TARGET", {0, 0})
	case .Editor:
		draw_text("EDITOR", {0, 0})
		src_xoffset: i32 = 22 if game.editor.unlocked else 21
		blit_sprite(.Small, {6*CELL_SIZE, 0}, vec2{src_xoffset * CELL_SIZE, 48})
	case .Grid:
		draw_text("GRID", {0, 0})
		mouse_tile_coord := get_tile_coord_from_position(
            (vec2)(cast(vec2f)game.input_state.mouse_position * cast(vec2f)INTERN_FRAMEBUFFER_DIMS / cast(vec2f)game.scaled_framebuffer_dims)
        )
		mouse_grid_coord_text := fmt.tprintf(
			"(%02v, %02v)",
		 	mouse_tile_coord.x,
		 	mouse_tile_coord.y,
		)
		draw_text(mouse_grid_coord_text, get_position_from_tile_coord({6, 0}))
	}
	if game.debug_mode == .Editor {
		update_editor()
	}
    rg_to_output(fb_pixmap)
    rg_clear(color_black_4b)
    rg_texture(fb_pixmap)
    game.scaled_framebuffer_dims = vec2{
        math.clamp(
            cast(i32)(cast(f32)game.update_info.framebuffer.h*0.7777),
            0,
            game.update_info.framebuffer.w,
        ),
        game.update_info.framebuffer.h,
    }
    game.dbgtext.origin = cast(vec2f)vec2{game.scaled_framebuffer_dims.x, 0}
    game.dbgtext.scale = 2
    dbgtext_scroll_delta := (f32)(-game.input_state.mouse_wheel_delta.y*CELL_SIZE*2)
    if game.update_info.is_gamepad_connected {
        right_y := game.input_state.gamepad.axes[.RIGHT_Y]
        if math.abs(right_y) > 0.2 {
            dbgtext_scroll_delta += game.input_state.gamepad.axes[.RIGHT_Y]*5.0
        }
    }

    rg_blit(
     	{0, 0},
    	dst_dims=game.scaled_framebuffer_dims,
    )
    dbgtext_frame(&game.dbgtext, game.scaled_framebuffer_dims, {0, dbgtext_scroll_delta})
    dbgtext_print("player target dir:", game.user_input_direction)
    dbgtext_print("Freeze state:", game.freeze_type)
    dbgtext_print("Freeze rem:", game.freeze_end_sim_tick - game.sim_ticks)
    dbgtext_print("Dots rem:", game.dots_remaining)
    dbgtext_print("Ghost state:", game.ghost_global_mode)
    dbgtext_print("Ghost mode switch rem:", game.mode_switch_sim_ticks_remaining)
    dbgtext_print("Ghost mode switch idx:", game.ghost_mode_switch_interval_index)
    dbgtext_printf("Player pos: %.01f", game.player.position, color=color_yellow_4b)
    dbgtext_printf("Blinky pos: %.01f", game.ghosts[.Blinky].position, color=GHOST_COLORS[.Blinky])
    dbgtext_printf("Pinky pos: %.01f", game.ghosts[.Pinky].position, color=GHOST_COLORS[.Pinky])
    dbgtext_printf("Inky pos: %.01f", game.ghosts[.Inky].position, color=GHOST_COLORS[.Inky])
    dbgtext_printf("Clyde pos: %.01f", game.ghosts[.Clyde].position, color=GHOST_COLORS[.Clyde])
    dbgtext_print("Blinky mode:", game.ghosts[.Blinky].mode, color=GHOST_COLORS[.Blinky])
    dbgtext_print("Pinky mode:", game.ghosts[.Pinky].mode, color=GHOST_COLORS[.Pinky])
    dbgtext_print("Inky mode:", game.ghosts[.Inky].mode, color=GHOST_COLORS[.Inky])
    dbgtext_print("Clyde mode:", game.ghosts[.Clyde].mode, color=GHOST_COLORS[.Clyde])
    dbgtext_print("Blinky leave rem:", game.ghosts[.Blinky].leave_remaining_sim_ticks , color=GHOST_COLORS[.Blinky])
    dbgtext_print("Pinky leave rem:",  game.ghosts[.Pinky].leave_remaining_sim_ticks  , color=GHOST_COLORS[.Pinky])
    dbgtext_print("Inky leave rem:",   game.ghosts[.Inky].leave_remaining_sim_ticks   , color=GHOST_COLORS[.Inky])
    dbgtext_print("Clyde leave rem:",  game.ghosts[.Clyde].leave_remaining_sim_ticks  , color=GHOST_COLORS[.Clyde])
    dbgtext_print("Ghost eat count:", game.ghost_eat_count)
    dbgtext_print("Level", game.level_count)
    dbgtext_print("Rumble rem:", game.rumble_end_sim_tick - game.sim_ticks)
    dbgtext_print("L Trigger:", game.input_state.gamepad.axes[.TRIGGER_LEFT])
    dbgtext_print("R Trigger:", game.input_state.gamepad.axes[.TRIGGER_RIGHT])
    if game.debug_mode == .Editor || game.debug_mode == .Grid {
   		rg_grid(
     		Rect {
         		0,
          		0,
              	game.scaled_framebuffer_dims.x,
               	game.scaled_framebuffer_dims.y
      		},
           	cast(f32)CELL_SIZE * (cast(vec2f)game.scaled_framebuffer_dims / cast(vec2f)INTERN_FRAMEBUFFER_DIMS),
            color_green
  		)
    } else {
    }
    
    rg_to_output(game.update_info.framebuffer)
    // Input state buffer swap
    game.input_state, game.old_input_state = game.old_input_state, game.input_state
    game.input_state.transient = {}
    game.input_state.persistent = game.old_input_state.persistent
    free_all(context.temp_allocator)

    return game.running
}

change_debug_mode :: proc(mode_inc: int = 1) {
    mode_int := cast(int)game.debug_mode
    mode_int = util.wrap(mode_int + mode_inc, len(Debug_Mode))
    game.debug_mode = cast(Debug_Mode)mode_int
}

increment_scale :: proc(inc: i32) {
    game.framebuffer_scale += inc
    game.framebuffer_scale = math.clamp(game.framebuffer_scale, 1, MAX_FRAMEBUFFER_SCALE)
    new_size := game.framebuffer_scale*INTERN_FRAMEBUFFER_DIMS
    if game.enable_debug_text {
        new_size.x += DEBUG_TEXT_WIDTH
    }
    game.init_info.platform_command_proc(util.Platform_Command{
        type=.Resize_Window,
        size=new_size,
    })
}

eng_handle_event :: proc(window_event: util.Window_Event) {
	util.set_input_state_from_event(game.input_state, window_event)
	#partial switch window_event.type {
    case .Mouse_Move:
        game.mouse_position = window_event.vec2
    case .Key:
        if window_event.key.pressed {
            switch window_event.key.keycode{
            case util.KEY_A:
                game.dots_remaining = 0
            case util.KEY_B:
                advance_ghost_mode_switch()
            case util.KEY_P:
                frighten_all()
            case util.KEY_F9:
            	game.step_mode = !game.step_mode
             	game.lag = 0
            case util.KEY_ADD:
            	game.lag = SIM_UPDATE_INTERVAL
            case util.KEY_R:
	           	reset_actors()
            case util.KEY_F1:
                change_debug_mode()
            case util.KEY_PAGEUP:
                increment_scale(1)
            case util.KEY_PAGEDOWN:
                increment_scale(-1)
            }
        }
    case .Window_Resize:
    	game.window_size = window_event.vec2
    case .Window_Close:
    	game.running = false
    }

    if game.debug_mode == .Editor {
	   	editor_handle_event(window_event)
    }
}

draw_maze :: proc() {
    if game.state != .Maze do return
    maze_color := color_blue_4b
    // Flash maze if completed
    if game.freeze_type == .Clear_Maze2 {
        if util.blink_state(game.sim_ticks, SIM_UPDATE_HZ/2) == 1 {
            maze_color = color_white_4b
        }
    }
    rg_palette(1, maze_color)
    rg_begin_multithread()
    if game.debug_mode == .Grid {
    	for tile, i in game.tile_map {
            tile_color := color_cyan_4b if tile in PASSABLE_TILES else color_grey_4b
	    	if tile != .None && tile != .Unused {
				pos := CELL_SIZE * get_tile_coord_from_tile_index(i)
		        rg_fill_rect(
		         	Rect{
                        pos.x,
                        pos.y,
                        CELL_SIZE,
                        CELL_SIZE,
                    },
                    tile_color,
		        )
	     	}
	    }
    } else {
    	desired_tile_map := game.full_tile_map if game.debug_mode == .Editor else game.tile_map
	    for tile, i in desired_tile_map {
	    	if tile != .None && tile != .Unused {
		    	tile_sprite := TILE_SPRITES[tile]
				if tile_sprite.src_offset == {} {
					tile_sprite.src_offset = vec2{10*CELL_SIZE, 0}
				}
		        blit_sprite(
                    .Small,
		         	CELL_SIZE * cast(vec2)get_tile_coord_from_tile_index(i),
		          	tile_sprite.src_offset,
		           	tile_sprite.flip,
		        )
	     	}
	    }
        if game.freeze_type == .Ready {
            rg_palette(1, color_yellow_4b)
            draw_text("Ready!", get_position_from_tile_coord({11, 20}))
        } else if game.freeze_type == .Game_Over {
            rg_palette(1, color_red_4b)
            draw_text("Game Over!", get_position_from_tile_coord({9, 20}))
        }
    }
    rg_end_multithread()
}
