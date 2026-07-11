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


vec2f :: util.vec2f
color_cyan_4b :: Color4b {0, 0xff, 0xff, 0xff}
color_green_4b :: Color4b {0, 0xff, 0, 0xff}
color_red_4b :: Color4b {0xff, 0, 0, 0xff}
color_grey_4b :: Color4b {0x7f, 0x7f, 0x7f, 0xff}
color_white_4b :: Color4b {0xff, 0xff, 0xff, 0xff}
color_black_4b :: Color4b {0x00, 0x00, 0x00, 0xff}

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
    init_info: Engine_Init,
    update_info: Engine_Update,
    mouse_position: vec2,
    player_position: vec2f,
    do_draw_grid: bool,
    position: vec2f,
    player_direction, player_target_direction: Direction,
    next_tile_blocked: bool,
    internal_framebuffer: []ColorU32, // [512*512]u8,
    // Row-major
    tile_map: [ROWS*COLS]Tile_Type,
    input_state: util.Input_State,
    player_spritesheet:  util.Pixmap,
    player_score: i32,
    player_num_lives: i32,
    tile_spritesheet: Pixmap,
    text_spritesheet: Pixmap,
    ghost_spritesheet: Pixmap,
    ghosts: [Ghost_Type]Ghost_Actor,
    render_group: Render_Group,
    last_frame_tick: time.Tick,
    lag: time.Duration,
    rects_collide: bool,
    anim, ghost_anim: Sprite_Animator,
    window_size_index: int,
    palette: Palette,
    frightened_sim_tick: int,
    paused: bool,
    // DELETE:
    test_pixmap: Pixmap,


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
SIM_UPDATE_INTERVAL :: 33333 * time.Microsecond
SIM_LAG_MAX :: 3 * SIM_UPDATE_INTERVAL

eng_init :: proc(init_info: Engine_Init) -> bool {
    game = new(Engine_Context)
    game.running = true
    game.init_info = init_info
    game.window_size_index = 2
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

    game.player_direction = .Left
    game.player_num_lives = 3

    game.render_group.palette = game.palette

    game.internal_framebuffer = make([]ColorU32, INTERN_FRAMEBUFFER_WIDTH * INTERN_FRAMEBUFFER_HEIGHT)

    load_ok: bool
    game.player_spritesheet, load_ok = load_bmp_indexed("textures/pacman.bmp")
    assert(load_ok)
    game.text_spritesheet, load_ok = load_bmp_indexed("textures/text.bmp")
    assert(load_ok)
    game.tile_spritesheet, load_ok = load_bmp_indexed("textures/tiles.bmp", &game.palette, game.init_info.pixel_format)
    assert(load_ok)
    game.ghost_spritesheet, load_ok = load_bmp_indexed("textures/ghost.bmp")
    assert(load_ok)

    game.test_pixmap, load_ok = file_load.load_png("resources/quadrant.png", game.init_info.pixel_format)
    assert(load_ok)

    try_setup_level()

    game.ghosts[.Blinky].direction = .Left
    game.ghosts[.Pinky].direction = .Right
    game.ghosts[.Inky].direction = .Up
    game.ghosts[.Clyde].direction = .Down

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

update_world :: proc() {
    SPEED :: 1.5
    player_tile_index := get_tile_index_from_position(cast(vec2)game.player_position)
    tile_pos := get_position_from_tile_index(player_tile_index)
    current_tile_center := tile_pos + (CELL_SIZE/2)
    next_tile, ok := get_adjacent_tile_type(player_tile_index, game.player_direction)
    next_target_tile, target_ok := get_adjacent_tile_type(player_tile_index, game.player_target_direction)
    if game.player_target_direction != nil {
        if next_target_tile in PASSABLE_TILES {
            game.player_direction = game.player_target_direction
            #partial switch game.player_direction {
            case .Up, .Down:
                // Position player x value to tile's center x if up or down
                game.player_position.x = cast(f32)current_tile_center.x
            case .Left, .Right:
                // Position player y value to tile's center y if left or right
                game.player_position.y = cast(f32)current_tile_center.y
            }
        }
    }
    game.player_position += SPEED * DIRECTION_VECTORS[game.player_direction]
    if next_tile not_in PASSABLE_TILES {
    	game.next_tile_blocked = true
        #partial switch game.player_direction {
        case .Left:
            game.player_position.x = max(cast(f32)current_tile_center.x, game.player_position.x)
        case .Right:
            game.player_position.x = min(cast(f32)current_tile_center.x, game.player_position.x)
        case .Up:
        	log.debug("UP BLOCKED!")
            game.player_position.y = max(cast(f32)current_tile_center.y, game.player_position.y)
        case .Down:
            game.player_position.y = min(cast(f32)current_tile_center.y, game.player_position.y)
        }
    } else {
	   	game.next_tile_blocked = false
	    anim_update(&game.anim, game.last_frame_tick)
    }
    player_is_horz := game.player_direction in bit_set[Direction]{.Left, .Right}
    player_is_vert := game.player_direction in bit_set[Direction]{.Up, .Down}
    if player_is_horz {
        game.player_position.y = (f32)(tile_pos.y + CELL_SIZE/2)
    } else if player_is_vert {
        game.player_position.x = (f32)(tile_pos.x + CELL_SIZE/2)
    }
    min_x := cast(f32)0
    min_y := cast(f32)CELL_SIZE*2
    max_x := (f32)(CELL_SIZE * (COLS + 1))
    max_y := (f32)(CELL_SIZE * (ROWS - 2))
    if game.player_position.x < 0 {
        game.player_position.x = max_x
    } else if game.player_position.x > max_x  {
        game.player_position.x = 0
    }
    if game.player_position.y < 0 {
        game.player_position.y = max_y
    } else if game.player_position.y > max_y {
        game.player_position.y = 0
    }
    // Eat dot
    if game.tile_map[player_tile_index] == .Dot {
        game.tile_map[player_tile_index] = .None
    } else if game.tile_map[player_tile_index] == .Pellet {
        broadcast_ghost_state(.Frightened)
        game.tile_map[player_tile_index] = .None
    }
    anim_update(&game.ghost_anim, game.last_frame_tick)
    for ghost_index in Ghost_Type {
    	ghost_actor := &game.ghosts[ghost_index]
        ghost_tile_index := get_tile_index_from_position(cast(vec2)ghost_actor.position)
        if ghost_tile_index == player_tile_index {
            if ghost_actor.state == .Frightened {
                ghost_actor.state = .Eaten
            } else {
                // TODO: kill pacman
            }
        }
    }

}

eng_update_render :: proc(update_info: Engine_Update) -> bool {
	// DELETE:
	pacman_ptr = game.player_spritesheet.pixels
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
	game.lag += diff
    game.last_frame_tick = now

    try_setup_level()
    player_is_horz, player_is_vert: bool
    for !game.paused && game.lag > SIM_UPDATE_INTERVAL {
	    // Only update once if diff is too big (likely due to debugging)
	    if game.lag > SIM_LAG_MAX {
			game.lag = SIM_UPDATE_INTERVAL
	    }
        update_world()
        game.lag -= SIM_UPDATE_INTERVAL
    }
    log.debug(game.player_position)
    set_direction_from_input()
    fb_pixmap := Pixmap {
        pixels=raw_data(game.internal_framebuffer),
        w=INTERN_FRAMEBUFFER_WIDTH,
        h=INTERN_FRAMEBUFFER_HEIGHT,
        pitch=INTERN_FRAMEBUFFER_WIDTH*4,
        format=game.init_info.pixel_format,
    }
    game.render_group.palette = game.palette
    rg_clear(Color4b{255, 127, 127, 255})

    v := (u8)(util.time_sin() * 255.0)
    rg_palette(1, {v, v, v, 255})

    log.debug(len(game.render_group.buffer))
    draw_maze()
    draw_player()
    draw_ghosts()
    text := fmt.tprintf("GRID: %v", "ON" if game.do_draw_grid else "OFF")
    if game.paused {
    	draw_text("PAUSED!", get_position_from_grid_coord({13,13}))
    }
    player_tile_index := get_tile_index_from_position(cast(vec2)game.player_position)
    tile_pos := get_tile_coord_from_tile_index(player_tile_index)
   	text = fmt.tprintf("(%v, %v)", tile_pos.x, tile_pos.y)
    draw_text(text, get_position_from_grid_coord({0, ROWS-1}))
    draw_text("HIGH SCORE", get_position_from_grid_coord({11, 0}))
    score_text := fmt.tprintf("%v", game.player_score)
    draw_text(score_text, get_position_from_grid_coord({5, 1}))
    rg_to_output(fb_pixmap)
    rg_texture(fb_pixmap)
    rg_blit(
     	{0, 0},
    	dst_dims=vec2{
        	game.update_info.framebuffer.w,
        	game.update_info.framebuffer.h,
     	}
    )
    if game.do_draw_grid {
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
    draw_text("This is on the real framebuffer", {50, 50}, 1.0 + util.time_sin())
    clip_rect := Rect{
        cast(i32)framebuffer_dims.x/4,
        cast(i32)framebuffer_dims.y/4,
        cast(i32)framebuffer_dims.x/4,
        cast(i32)framebuffer_dims.y/4,
    }
    rg_stroke_rect(clip_rect, color_green_4b)
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
            case util.KEY_SPACE:
            	game.do_draw_grid = !game.do_draw_grid
            case util.KEY_P:
           		broadcast_ghost_state(.Frightened)
            case util.KEY_R:
                try_setup_level(true)
            case util.KEY_PAGEUP, util.KEY_PAGEDOWN:
            	game.window_size_index = (game.window_size_index + 1) % len(window_sizes)
	            game.init_info.platform_command_proc(util.Platform_Command{
	            	type=.Resize_Window,
	            	size=window_sizes[game.window_size_index],
	            })
            }
        }
    case .Window_Close:
    	game.running = false
    }

    if game.module.handle_event != nil {
        game.module.handle_event(window_event)
    }
}

// Sets player's target direction from input.
// Gamepad input has priority over keyboard
set_direction_from_input :: proc "contextless" () {
	game.player_target_direction = nil
	switch {
	case .LEFT in game.input_state.gamepad.hat:
		game.player_target_direction = .Left
	case .RIGHT in game.input_state.gamepad.hat:
		game.player_target_direction = .Right
	case .UP in game.input_state.gamepad.hat:
		game.player_target_direction = .Up
	case .DOWN in game.input_state.gamepad.hat:
		game.player_target_direction = .Down
	}
	// Read thumbstick input if dpad is not pressed
	if game.player_target_direction == nil {
		switch {
		case game.input_state.gamepad.axes[.LEFT_X] < -THUMBSTICK_THRESHOLD:
			game.player_target_direction = .Left
		case game.input_state.gamepad.axes[.LEFT_X] > THUMBSTICK_THRESHOLD:
			game.player_target_direction = .Right
		case game.input_state.gamepad.axes[.LEFT_Y] < -THUMBSTICK_THRESHOLD:
			game.player_target_direction = .Up
		case game.input_state.gamepad.axes[.LEFT_Y] > THUMBSTICK_THRESHOLD:
			game.player_target_direction = .Down
		}
	}
	// Read keyboard input if not input from gamepad
	if game.player_target_direction == nil {
		switch {
		case util.bit_test(game.input_state.keyboard[:], util.KEY_LEFT):
			game.player_target_direction = .Left
		case util.bit_test(game.input_state.keyboard[:], util.KEY_RIGHT):
			game.player_target_direction = .Right
		case util.bit_test(game.input_state.keyboard[:], util.KEY_UP):
			game.player_target_direction = .Up
		case util.bit_test(game.input_state.keyboard[:], util.KEY_DOWN):
			game.player_target_direction = .Down
		}
	}
	if game.player_target_direction == nil {
		game.player_target_direction = game.player_direction
	}
}

// Set state for all ghosts
broadcast_ghost_state :: proc(state: Ghost_State) {
	for &ghost in game.ghosts {
		ghost.state = state
	}
	// TODO: change this code and apply for more states
	if state == .Frightened {
		game.frightened_sim_tick = 30*6
	}
}

// TODO: maybe assert or return maybe type if tile out of bounds
get_adjacent_tile_type :: proc "contextless" (#any_int tile_idx: i32, direction: Direction) -> (Tile_Type, bool) #optional_ok {
    adj_idx: i32
    ok: bool
    switch direction {
    case .None:
        ok = false
    case .Left:
        adj_idx = tile_idx-1
        ok = adj_idx > 0
    case .Right:
        adj_idx = tile_idx+1
        ok = (adj_idx % COLS) < COLS-1
    case .Up:
        adj_idx = tile_idx-COLS
        ok = adj_idx >= COLS
    case .Down:
        adj_idx = tile_idx+COLS
        ok = adj_idx <= (COLS-1)*(ROWS-1)
    }
    if ok {
	    return game.tile_map[adj_idx], true
    }
    return nil, false
}

get_tile_coord_from_tile_index :: #force_inline proc "contextless" (#any_int idx: i32) -> vec2 {
    return vec2{idx % COLS, idx / COLS}
}

get_tile_index_from_position :: #force_inline proc "contextless" (pos: vec2) -> i32 {
	col := pos.x / CELL_SIZE
	row := pos.y / CELL_SIZE
	return row * COLS + col
}

get_position_from_grid_coord :: #force_inline proc "contextless" (gp: vec2) -> vec2 {
	return gp * CELL_SIZE
}

get_position_from_tile_index :: #force_inline proc "contextless" (#any_int idx: i32) -> vec2 {
	return CELL_SIZE * vec2{idx % COLS, idx / COLS}
}

TEXT_SPRITESHEET_ORDER :: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!:.,?\"-/%=()"

draw_maze :: proc() {
    rg_texture(game.tile_spritesheet)
    if game.do_draw_grid {
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
	    for tile, i in game.tile_map {
	    	if tile != .None && tile != .Unused {
		    	tile_sprite := TILE_SPRITES[tile]
				if tile_sprite.rect == {} {
					tile_sprite.rect = Rect{10*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE}
				}
		        rg_blit(
		         	CELL_SIZE * get_tile_coord_from_tile_index(i),
		          	tile_sprite.rect,
		           	tile_sprite.flip,
		        )
	     	}
	    }
    }
}

draw_player :: proc() {
	player_frame: i32
    if game.player_direction == .Up || game.player_direction == .Down {
        player_frame = PACMAN_DOWN_FRAMES[game.anim.frame_index]
    } else {
        player_frame = PACMAN_RIGHT_FRAMES[game.anim.frame_index]
    }
	if game.do_draw_grid {
        player_color := Color4b{0xff, 0xff, 0, 0xff}
  		col := (i32)(cast(f32)game.player_position.x / cast(f32)CELL_SIZE)
  		row := (i32)(cast(f32)game.player_position.y / cast(f32)CELL_SIZE)
    	rg_fill_rect(
     		Rect{
	     		x=col*CELL_SIZE,
		       	y=row*CELL_SIZE,
	        	w=CELL_SIZE,
	        	h=CELL_SIZE,
       		},
         	player_color,
     	)
        // draw player's center point
        rg_fill_rect(Rect{
            cast(i32)game.player_position.x,
            cast(i32)game.player_position.y,
            1,
            1
        }, inv_color(player_color))
    } else {
	    rg_texture(game.player_spritesheet)
	    rg_blit(
            cast(vec2)game.player_position - PLAYER_DIMS/2,
	    	Rect{
		      	player_frame * PLAYER_SIZE,
		       	0,
	        	PLAYER_SIZE,
	         	PLAYER_SIZE
	     	},
			{game.player_direction == .Left, game.player_direction == .Up},
	 	)
    }
    // p := cast(vec2)game.player_position - PLAYER_DIMS/2
    // rg_stroke_rect(
    // 	Rect {
    //  		p.x,
    //    		p.y,
    //      	PLAYER_SIZE,
    //      	PLAYER_SIZE,
    //  	},
    //  	color_red_4b,
    // )
    // Draw lives at bottom
    for i in 0..<game.player_num_lives {
    	// rg_blit({3*CELL_SIZE+i*PLAYER_SIZE, (ROWS-2)*CELL_SIZE}, {0, 0, PLAYER_SIZE, PLAYER_SIZE})
    	blit_sprite(.Big, {3*CELL_SIZE+i*PLAYER_SIZE, (ROWS-2)*CELL_SIZE}, {0, 0})
    }
}

draw_ghosts :: proc() {
	rg_texture(game.ghost_spritesheet)
	flash_state := util.time_sin(freq=2.0) >= 0.5
    if !game.do_draw_grid {
        for ghost_index in Ghost_Type {
	        sprite_data: Tile_Sprite
            ghost_actor := &game.ghosts[ghost_index]
            draw_pos := cast(vec2)ghost_actor.position - {PLAYER_SIZE, PLAYER_SIZE}/2
            switch game.ghosts[ghost_index].state {
            case .Eaten:
                if ghost_actor.direction == .Left || ghost_actor.direction == .Right {
                    rg_blit(
                        draw_pos,
                        Rect{8*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
                        {ghost_actor.direction == .Left, false}
                    )
                } else if ghost_actor.direction == .Up {
                    rg_blit(draw_pos, Rect{9*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE})

                } else if ghost_actor.direction == .Down {
                    rg_blit(draw_pos, Rect{10*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE})
                }
            case .Frightened:
         		// TODO: only flash when frightened time is reaches near limit
         		if flash_state {
		       		rg_palette(1, GHOST_FRIGHTENED_COLOR)
					rg_palette(2, {238, 186, 161, 255})
           		} else {
		            rg_palette(1, color_white_4b)
					rg_palette(2, color_red_4b)
             	}
	        	sprite_data = Tile_Sprite{
                    rect={cast(i32)game.ghost_anim.frame_index*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE}
                }
                rg_blit(draw_pos, sprite_data.rect, sprite_data.flip)
            case .Scatter, .Chase:
                rg_palette(1, GHOST_COLORS[ghost_index])
	        	sprite_data = GHOST_SPRITES[ghost_actor.direction][game.ghost_anim.frame_index]
                rg_blit(draw_pos, sprite_data.rect, sprite_data.flip)
            }
        }
    } else {
        for ghost_index in Ghost_Type {
            ghost_color := GHOST_COLORS[ghost_index]
            ghost_actor := &game.ghosts[ghost_index]
            col := cast(i32)(cast(f32)ghost_actor.position.x / (f32)(CELL_SIZE))
            row := cast(i32)(cast(f32)ghost_actor.position.y / (f32)(CELL_SIZE))
            rg_fill_rect(
                Rect{
                    x=col*CELL_SIZE,
                    y=row*CELL_SIZE,
                    w=CELL_SIZE,
                    h=CELL_SIZE,
                },
                ghost_color if flash_state else color_grey_4b,
            )
            // draw ghost center point
            rg_fill_rect(Rect{
                cast(i32)ghost_actor.position.x,
                cast(i32)ghost_actor.position.y,
                1,
                1
            }, inv_color(ghost_color))
        }
    }
}

draw_path :: proc(origin_tile_index: vec2, path: []Direction) {
	for i in 0..<len(path)-1 {
		// TODO:
	}
}

draw_text :: proc(text: string, offset: vec2, scale: f32 = 1.0, loc := #caller_location) {
	rg_texture(game.text_spritesheet)
	rg_palette(1, color_black_4b)
    scaled_cell_size := (i32)(scale * cast(f32)CELL_SIZE)
	for c, i in text {
		rect := Rect{
			get_text_sprite_xoffset(c),
			0,
			CELL_SIZE,
			CELL_SIZE,
		}
		if c != ' ' {
			rg_blit(
				{(cast(i32)i * scaled_cell_size) + offset.x, offset.y},
				rect,
				dst_dims=vec2{scaled_cell_size, scaled_cell_size},
			)
		}
	}
}

get_text_sprite_xoffset :: proc(target_c: rune) -> i32 {
	idx := 0
	target_c := target_c
	for c, i in TEXT_SPRITESHEET_ORDER {
		if target_c >= 'a' && target_c <= 'z' {
			target_c = (target_c - 'a') + 'A'
		}
		if target_c == c {
			return cast(i32)i * CELL_SIZE,
		}
	}
	// Returns last character which is placeholder
	return cast(i32)len(TEXT_SPRITESHEET_ORDER) * CELL_SIZE
}

// Since most blits have a src_rect dimensions of PLAYER_SIZE or CELL_SIZE
blit_sprite :: #force_inline proc(
	sprite_size: enum{Big, Small},
	offset, src_rect_offset: vec2,
 	flip: [2]bool = {},
  	loc := #caller_location)
{
	dim_size := PLAYER_SIZE if sprite_size == .Big else CELL_SIZE
	rg_blit(offset, Rect{src_rect_offset.x, src_rect_offset.y, dim_size, dim_size}, flip, loc=loc)
}
