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

PACMAN_RIGHT_FRAMES := [?]i32 {0, 2, 4}
PACMAN_DOWN_FRAMES := [?]i32{1, 3, 4}

window_sizes := [?]vec2 {
	1 * INTERN_FRAMEBUFFER_DIMS,
	2 * INTERN_FRAMEBUFFER_DIMS,
	3 * INTERN_FRAMEBUFFER_DIMS,
	4 * INTERN_FRAMEBUFFER_DIMS,
}

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
    step_mode: bool,
    init_info: Engine_Init,
    update_info: Engine_Update,
    mouse_position: vec2,
    debug_mode: Debug_Mode,
    position: vec2f,
    player_target_direction: Direction,
    editor: Editor_State,
    internal_framebuffer: []ColorU32, // [512*512]u8,
    input_file_op: enum {None, Record, Read,},
    recorded_input_file: ^os.File,
    // Row-major
    tile_map, full_tile_map: [ROWS*COLS]Tile_Type,
    marker_map: [ROWS*COLS]Marker_Tile_Type,
    input_state: util.Input_State,
    player_spritesheet:  util.Pixmap,
    player: Player,
    tile_spritesheet: Pixmap,
    text_spritesheet: Pixmap,
    ghost_spritesheet: Pixmap,
    ghost_global_mode: Ghost_Global_Mode,
    ghosts: [Ghost_Type]Ghost_Actor,
    eaten_ghost: Maybe(Ghost_Type),
    ghost_pass_tile_coord, ghost_revive_tile_coord: Tile_Coord,
    render_group: Render_Group,
    last_frame_tick: time.Tick,
    sim_ticks, frame_counter: int,
    sim_pause_end_tick: int,
    lag: time.Duration,
    rects_collide: bool,
    anim, ghost_anim: Sprite_Animator,
    window_size: vec2,
    window_size_index: int,
    palette: Palette,
    frightened_end_tick: int,
    paused: bool,
    ghost_eat_count: i32,
    max_num_dots, dots_remaining: i32,


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

Tile_Sprite :: struct {
	rect: Rect,
	flip: [2]bool,
}

Module_Init_Proc         :: #type proc(_: ^Engine_Context)
Module_Update_Proc       :: #type proc()
Module_Handle_Event_Proc :: #type proc(event: util.Window_Event)
Module_Shutdown_Proc     :: #type proc()

game: ^Engine_Context
// Game "world" updates 60 times per second
SIM_UPDATE_HZ :: 60
SIM_UPDATE_INTERVAL :: (time.Duration)(cast(f32)time.Second/cast(f32)SIM_UPDATE_HZ)
SIM_LAG_MAX :: 3 * SIM_UPDATE_INTERVAL

eng_init :: proc(init_info: Engine_Init) -> bool {
    game = new(Engine_Context)
    game.running = true
    game.init_info = init_info
    game.window_size_index = 2
    game.window_size = window_sizes[game.window_size_index]
    init_info.platform_command_proc(util.Platform_Command{
    	type=.Rename_Window,
    	title="Puckman"
    })
    init_info.platform_command_proc(util.Platform_Command {
        type=.Set_Window_Min_Size,
        size=window_sizes[0],
    })
    init_info.platform_command_proc(util.Platform_Command {
        type=.Set_Window_Max_Size,
        size=window_sizes[len(window_sizes)-1],
    })
    init_info.platform_command_proc(util.Platform_Command{
    	type=.Resize_Window,
    	size=window_sizes[game.window_size_index],
    })
    init_info.platform_command_proc(util.Platform_Command {
    	type=.Change_Window_Icon,
    	path="textures/icon.ico",
    })

    game.player.direction = .None
    game.player.num_lives = 3

    game.render_group.palette = game.palette

    game.internal_framebuffer = make([]ColorU32, INTERN_FRAMEBUFFER_WIDTH * INTERN_FRAMEBUFFER_HEIGHT)

    input_file_err: os.Error
    game.recorded_input_file, input_file_err = os.open("input.txt", {.Write, .Create, .Trunc})
    assert(input_file_err == nil)

    load_ok: bool
    game.player_spritesheet, load_ok = load_bmp_indexed("textures/pacman.bmp")
    assert(load_ok)
    game.text_spritesheet, load_ok = load_bmp_indexed("textures/text.bmp")
    assert(load_ok)
    game.tile_spritesheet, load_ok = load_bmp_indexed("textures/wall.bmp", &game.palette, game.init_info.pixel_format)
    assert(load_ok)
    game.ghost_spritesheet, load_ok = load_bmp_indexed("textures/ghost.bmp")
    assert(load_ok)

    load_tile_map()
    reset_level()

    game.paused = true
    game.lag = SIM_UPDATE_INTERVAL

    game.ghosts[.Blinky].direction = .Left
    game.ghosts[.Pinky].direction = .Right
    game.ghosts[.Inky].direction = .Up
    game.ghosts[.Clyde].direction = .Down

    game.debug_mode = .Ghost_Target


    game.anim = Sprite_Animator {
   		end_frame=2,
    	frame_interval=50*time.Millisecond,
    	repeat_mode=.Ping_Pong,
    	inc=1,
    }

    game.ghost_anim = Sprite_Animator {
    	end_frame=1,
	    frame_interval=100*time.Millisecond,
	    repeat_mode=.Ping_Pong,
		inc=1,
    }

    // load_module()

    game.input_file_op = .Record
    for arg in os.args {
        if arg == "-input" {
            game.input_file_op = .Read
        }
    }
    if game.module.init != nil {
        game.module.init(game)
    }
    log.debug("GAME ENGINE SIZE:", size_of(game^))

    return true
}

eng_shutdown :: proc() {
    if game.module.shutdown != nil {
        game.module.shutdown()
    }
    os.write_string(game.recorded_input_file, "OK")
    os.close(game.recorded_input_file)
}

update_world :: proc() {
	if game.sim_ticks >= game.sim_pause_end_tick {
		game.eaten_ghost = nil
		update_player()
		update_ghosts()
	}
    if game.sim_ticks == game.frightened_end_tick {
        unfrighten_all()
    }
    calculate_ghost_targets()
    anim_update(&game.ghost_anim, game.last_frame_tick)
    for ghost_index in Ghost_Type {
    	ghost_actor := &game.ghosts[ghost_index]
        // Check player collision with ghosts
        if ghost_actor.tile_coord == game.player.tile_coord {
            if ghost_actor.mode == .Frightened {
                ghost_actor.mode = .Eaten
                game.ghost_eat_count += 1
                game.player.score += (i32)(1 << cast(u32)game.ghost_eat_count) * 100
                if !game.step_mode {
	                game.sim_pause_end_tick = game.sim_ticks + 30
                }
                game.eaten_ghost = ghost_index
                // TODO: set hesitate time
            } else if ghost_actor.mode != .Eaten {
                // TODO: kill pacman
                reset_level()
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
    framebuffer_dims := cast(vec2f)vec2{
        game.update_info.framebuffer.w,
        game.update_info.framebuffer.h
    }

	now := time.tick_now()
    diff := time.tick_diff(game.last_frame_tick, now)
	if !game.step_mode {
		game.lag += diff
	}
    game.last_frame_tick = now

    set_direction_from_input()
    do_update_sim := !game.paused && game.debug_mode != .Editor
    for do_update_sim && game.lag >= SIM_UPDATE_INTERVAL {
	    // Only update once if diff is too big (likely due to debugging)
	    if game.lag > SIM_LAG_MAX {
			game.lag = SIM_UPDATE_INTERVAL
	    }

        if game.input_file_op == .Record {
            input_char: rune
            switch game.player_target_direction {
            case .None:
                input_char = '0'
            case .Up:
                input_char = 'U'
            case .Down:
                input_char = 'D'
            case .Left:
                input_char = 'L'
            case .Right:
                input_char = 'R'
            }
            os.write_byte(game.recorded_input_file, cast(u8)input_char)
            os.flush(game.recorded_input_file)
        }
        update_world()
        game.sim_ticks += 1
        game.lag -= SIM_UPDATE_INTERVAL
    }
    fb_pixmap := Pixmap {
        pixels=raw_data(game.internal_framebuffer),
        w=INTERN_FRAMEBUFFER_WIDTH,
        h=INTERN_FRAMEBUFFER_HEIGHT,
        pitch=INTERN_FRAMEBUFFER_WIDTH*4,
        format=game.init_info.pixel_format,
    }
    game.render_group.palette = game.palette
    rg_clear(Color4b{80, 0, 0, 255} if game.step_mode else Color4b{0, 0, 27, 255})

    v := (u8)(util.time_sin() * 255.0)
    rg_palette(1, {v, v, v, 255})

    draw_maze()
    draw_player()
    draw_ghosts()
    if game.paused && game.debug_mode != .Editor {
    	draw_text("PAUSED!", get_position_from_tile_coord({13,13}))
    }
    tile_pos := get_position_from_tile_coord(game.player.tile_coord)
    #partial switch game.debug_mode {
   	case .None:
	    draw_text("HIGH SCORE", get_position_from_tile_coord({11, 0}))
	    score_text := fmt.tprintf("%02d", game.player.score)
	    draw_text(score_text, get_position_from_tile_coord({5, 1}))
    case .Ghost_Target:
        draw_text("TARGET", {0, 0})
        // blinky_tile_coord := game.ghosts[.Blinky].tile_coord
        // blinky_next_tile_coord := game.ghosts[.Blinky].next_tile_coord
        // text := fmt.tprintf("B Tile: (%02v, %02v)", blinky_tile_coord.x, blinky_tile_coord.y)
        // draw_text(text, get_position_from_tile_coord({0, 1}))
        // text = fmt.tprintf("B Next: (%02v, %02v)", blinky_next_tile_coord.x, blinky_next_tile_coord.y)
        // draw_text(text, get_position_from_tile_coord({0, 2}))
        // text = fmt.tprintf("Dir: %v", game.ghosts[.Blinky].direction)
        // draw_text(text, get_position_from_tile_coord({17, 2}))

        text := fmt.tprintf("P Tile: (%02v, %02v)", game.player.tile_coord.x, game.player.tile_coord.y)
        draw_text(text, get_position_from_tile_coord({0, 1}))
        text = fmt.tprintf("Dots: %03d", game.dots_remaining)
        draw_text(text, get_position_from_tile_coord({0, 2}))
	case .Editor:
		draw_text("EDITOR", {0, 0})
		src_xoffset: i32 = 52 if game.editor.unlocked else 51
		blit_sprite(.Small, {6*CELL_SIZE, 0}, vec2{src_xoffset * CELL_SIZE, 0})
	case .Grid:
		draw_text("GRID", {0, 0})
		mouse_tile_coord := get_tile_coord_from_position(
            (vec2)(cast(vec2f)game.input_state.mouse_position * cast(vec2f)INTERN_FRAMEBUFFER_DIMS / framebuffer_dims)
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
    rg_texture(fb_pixmap)
    rg_blit(
     	{0, 0},
    	dst_dims=vec2{
        	game.update_info.framebuffer.w,
        	game.update_info.framebuffer.h,
     	}
    )
    if game.debug_mode == .Editor || game.debug_mode == .Grid {
   		rg_grid(
     		Rect {
         		0,
          		0,
              	game.update_info.framebuffer.w,
               	game.update_info.framebuffer.h
      		},
           	cast(f32)CELL_SIZE * (framebuffer_dims / cast(vec2f)INTERN_FRAMEBUFFER_DIMS),
            color_green
  		)
    } else {
    }
    rg_to_output(game.update_info.framebuffer)
    if false && game.module.update_render != nil {
        game.module.update_render()
    }
    game.input_state.transient = {}
    free_all(context.temp_allocator)

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
            	game.paused = !game.paused
            case util.KEY_F4, util.KEY_F5:
                game.running = false
            case util.KEY_P:
           		frighten_all()
            case util.KEY_M:
	            if game.ghost_global_mode == .Scatter {
	            	game.ghost_global_mode = .Chase
	            } else {
	            	game.ghost_global_mode = .Scatter
	            }
            case util.KEY_F9:
            	game.step_mode = !game.step_mode
             	game.lag = 0
            case util.KEY_ADD:
            	game.lag = SIM_UPDATE_INTERVAL
            case util.KEY_R:
	           	reset_level()
            case util.KEY_F1:
            	mode_int := cast(int)game.debug_mode
            	mode_int = util.wrap(mode_int + 1, len(Debug_Mode))
             	game.debug_mode = cast(Debug_Mode)mode_int
	            log.debug(mode_int)
            case util.KEY_PAGEUP, util.KEY_PAGEDOWN:
            	game.window_size_index = (game.window_size_index + 1) % len(window_sizes)
	            game.init_info.platform_command_proc(util.Platform_Command{
	            	type=.Resize_Window,
	            	size=window_sizes[game.window_size_index],
	            })
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

    if game.module.handle_event != nil {
        game.module.handle_event(window_event)
    }
}

draw_maze :: proc() {
    rg_texture(game.tile_spritesheet)
    rg_palette(1, color_blue_4b)
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
				if tile_sprite.rect == {} {
					tile_sprite.rect = Rect{10*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE}
				}
		        rg_blit(
		         	CELL_SIZE * cast(vec2)get_tile_coord_from_tile_index(i),
		          	tile_sprite.rect,
		           	tile_sprite.flip,
		        )
	     	}
	    }
    }
}
