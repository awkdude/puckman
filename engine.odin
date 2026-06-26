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

PLATFORM_BACKEND :: #config(BACKEND, "native")

THUMBSTICK_THRESHOLD :: 0.5

FONT_PATH :: "resources/DejaVu Sans Mono_512x512x16x16.png"

CELL_SIZE: i32 : 8
ROWS: i32 : 32
COLS: i32 : 32
PLAYER_SIZE_CELLS :: 2
PLAYER_SIZE: i32 : PLAYER_SIZE_CELLS * CELL_SIZE
FRAMEBUFFER_WIDTH  :: CELL_SIZE * ROWS
FRAMEBUFFER_HEIGHT :: CELL_SIZE * COLS
FRAMEBUFFER_SIZE :: vec2{FRAMEBUFFER_WIDTH, FRAMEBUFFER_HEIGHT }

PACMAN_RIGHT_FRAMES := [?]i32 {0, 2, 4}
PACMAN_DOWN_FRAMES := [?]i32{1, 3, 4}

window_sizes := [?]vec2 {
	1 * {FRAMEBUFFER_WIDTH, FRAMEBUFFER_HEIGHT},
	2 * {FRAMEBUFFER_WIDTH, FRAMEBUFFER_HEIGHT},
	3 * {FRAMEBUFFER_WIDTH, FRAMEBUFFER_HEIGHT},
	4 * {FRAMEBUFFER_WIDTH, FRAMEBUFFER_HEIGHT},
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
	window_size: vec2,
    gamepad_state: util.Gamepad_State,
    is_gamepad_connected: bool,
    framebuffer: util.Pixmap,
}

Tile_Type :: enum u8 {
    None,
    Dot,
    Pellet,
    Wall_Left,
    Wall_Right,
    Wall_Top,
    Wall_Bottom,
    Wall_Top_Left,
    Wall_Top_Right,
    Wall_Bottom_Left,
    Wall_Bottom_Right,
    Border_Top,
    Border_Bottom,
    Border_Left,
    Border_Right,
    Border_Sharp_Top_Left,
    Border_Sharp_Top_Right,
    Border_Sharp_Bottom_Left,
    Border_Sharp_Bottom_Right,
    Border_Top_Left,
    Border_Top_Right,
    Border_Bottom_Left,
    Border_Bottom_Right,
    Ghost_Pass,
    Unused,
}

Direction :: enum {
    None,
    Up,
    Down,
    Left,
    Right,
}

direction_vectors := [Direction]vec2f {
    .None= {},
    .Up = {0, -1},
    .Down = {0, 1},
    .Left = {-1, 0},
    .Right = {1, 0},
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
    internal_framebuffer: []ColorU32, // [512*512]u8,
    // Row-major
    tile_map: [ROWS*COLS]Tile_Type,
    input_state: util.Input_State,
    player_spritesheet:  util.Pixmap,
    tile_spritesheet: Pixmap,
    text_spritesheet: Pixmap,
    tile_sprites: [Tile_Type]Tile_Sprite,
    render_group: Render_Group,
    last_frame_tick: time.Tick,
    lag: time.Duration,
    rects_collide: bool,
    anim: Sprite_Animatior,
    window_size_index: int,
    palette: Palette,

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

eng_init :: proc(init_info: Engine_Init) -> bool {
    game = new(Engine_Context)
    game.running = true
    game.init_info = init_info
    game.window_size_index = len(window_sizes) - 1
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

    game.render_group.palette = game.palette

    game.internal_framebuffer = make([]ColorU32, FRAMEBUFFER_WIDTH * FRAMEBUFFER_HEIGHT)

    load_ok: bool
    game.player_spritesheet, load_ok = load_bmp_indexed("textures/pacman.bmp")
    assert(load_ok)
    game.text_spritesheet, load_ok = load_bmp_indexed("textures/text.bmp")
    assert(load_ok)
    game.tile_spritesheet, load_ok = load_bmp_indexed("textures/tiles.bmp", &game.palette)
    assert(load_ok)

    try_setup_level()

    game.tile_sprites = {
    	.None={},
    	.Unused={},
    	.Dot={
       		rect=Rect{8*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
     	},
     	.Pellet={
      		rect=Rect{9*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
      	},
    	.Wall_Left={
       		rect=Rect{0*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={true, false},
     	},
     	.Wall_Right={
      		rect=Rect{0*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
      	},
      	.Wall_Top={
      		rect=Rect{1*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
           	flip={false, true},
       	},
       	.Wall_Bottom={
      		rect=Rect{1*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
       	},
       	.Wall_Bottom_Right={
       		rect=Rect{2*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        },
       	.Wall_Bottom_Left={
       		rect=Rect{2*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={true, false},
        },
       	.Wall_Top_Left={
       		rect=Rect{2*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={true, true},
        },
       	.Wall_Top_Right={
       		rect=Rect{2*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={false, true},
        },
        .Border_Bottom={
        	rect=Rect{4*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={false, false},
        },
        .Border_Top={
        	rect=Rect{4*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={false, true},
        },
        .Border_Left={
        	rect=Rect{5*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={true, false},
        },
        .Border_Right={
        	rect=Rect{5*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={false, false},
        },
       	.Border_Bottom_Right={
       		rect=Rect{6*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        },
       	.Border_Bottom_Left={
       		rect=Rect{6*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={true, false},
        },
       	.Border_Top_Left={
       		rect=Rect{6*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={true, true},
        },
       	.Border_Top_Right={
       		rect=Rect{6*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={false, true},
        },
       	.Border_Sharp_Bottom_Right={
       		rect=Rect{7*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        },
       	.Border_Sharp_Bottom_Left={
       		rect=Rect{7*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={true, false},
        },
       	.Border_Sharp_Top_Left={
       		rect=Rect{7*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={true, true},
        },
       	.Border_Sharp_Top_Right={
       		rect=Rect{7*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={false, true},
        },
        .Ghost_Pass={
        	rect=Rect{3*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
         	flip={false, false},
        },
    }

    game.anim = Sprite_Animatior {
   		end_frame=2,
    	frame_interval=50*time.Millisecond,
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
    framebuffer_size := cast(vec2f)vec2{
        game.update_info.framebuffer.w,
        game.update_info.framebuffer.h
    }

	now := time.tick_now()
    diff := time.tick_diff(game.last_frame_tick, now)
	game.lag += diff
    game.last_frame_tick = now

    try_setup_level()
    // TODO: Don't update if diff is too big (likely due to debugging)
    for game.lag > SIM_UPDATE_INTERVAL {
        SPEED :: 1.5
        game.player_position += SPEED * direction_vectors[game.player_direction]
        if game.player_target_direction != nil {
            game.player_direction = game.player_target_direction// TODO: check collision
        }
        max_x := (f32)(CELL_SIZE * COLS - PLAYER_SIZE)
        max_y := (f32)(CELL_SIZE * ROWS - PLAYER_SIZE)
        if game.player_position.x < 0 {
            game.player_position.x = 0
        } else if game.player_position.x > max_x {
            game.player_position.x = max_x
        }
        if game.player_position.y < 0 {
            game.player_position.y = 0
        } else if game.player_position.y > max_y {
            game.player_position.y = max_y
        }
        tile := get_tile_from_position(cast(vec2)game.player_position)
        if tile^ == .Dot {
        	// TODO: Eat dot
         	tile^ = .None
        }
        anim_update(&game.anim, game.last_frame_tick)
        game.lag -= SIM_UPDATE_INTERVAL
    }
    log.debug(game.player_position)
    set_direction_from_input()
    fb_pixmap := Pixmap {
        pixels=raw_data(game.internal_framebuffer),
        w=FRAMEBUFFER_WIDTH,
        h=FRAMEBUFFER_HEIGHT,
        pitch=FRAMEBUFFER_WIDTH*4,
        bytes_per_pixel=4,
        pixel_format=game.init_info.pixel_format,
    }
    game.render_group.palette = game.palette
    rg_clear(Color4b{255, 127, 127, 255})

    player_frame: i32
    is_vert := game.player_direction in bit_set[Direction]{.Up, .Down}
    if is_vert {
        player_frame = PACMAN_DOWN_FRAMES[game.anim.frame_index]
    } else {
        player_frame = PACMAN_RIGHT_FRAMES[game.anim.frame_index]
    }
    v := (u8)(util.time_sin() * 255.0)
    rg_palette(1, {v, v, v, 255})

    rg_texture(game.tile_spritesheet)
    for tile, i in game.tile_map {
    	if tile != .None && tile != .Unused {
	    	tile_sprite := game.tile_sprites[tile]
	        rg_blit(
	         	CELL_SIZE * get_tile_coord_from_tile_index(i),
	          	tile_sprite.rect,
	           	tile_sprite.flip,
	        )
     	}
    }
    log.debug(len(game.render_group.buffer))
    buf: [64]u8
    text := fmt.bprintf(buf[:], "GRID: %v", "ON" if game.do_draw_grid else "OFF")
    draw_text(text, {CELL_SIZE, CELL_SIZE})
    // draw player
    if game.do_draw_grid {
  		col := cast(i32)(cast(f32)game.player_position.x / (f32)(CELL_SIZE))
  		row := cast(i32)(cast(f32)game.player_position.y / (f32)(CELL_SIZE))
    	rg_fill_rect(
     		Rect{
	       		x=col*CELL_SIZE,
	         	y=row*CELL_SIZE,
	          	w=CELL_SIZE,
	          	h=CELL_SIZE,
       		},
         	{0xff, 0, 0, 0xff},
     	)
    } else {
	    rg_texture(game.player_spritesheet)
	    rg_blit(
	     	cast(vec2)game.player_position - {PLAYER_SIZE, PLAYER_SIZE}/2,
	      	Rect{
	        	player_frame * PLAYER_SIZE,
	         	0,
	          	PLAYER_SIZE,
	           	PLAYER_SIZE
	       	},
	        {game.player_direction == .Left, game.player_direction == .Up},
	   	)
    }
    rg_fill_rect(Rect{
    	cast(i32)game.player_position.x,
    	cast(i32)game.player_position.y,
     	1,
      	1
    }, color_cyan_4b)
    rg_to_output(fb_pixmap)
    rg_texture(fb_pixmap)
    rg_blit_scaled(
     	{0, 0},
    	dst_rect=Rect{
     		0,
       		0,
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
           	cast(f32)CELL_SIZE * (framebuffer_size / cast(vec2f)FRAMEBUFFER_SIZE),
            color_green
  		)
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
                game.running = false
            case util.KEY_SPACE:
            	game.do_draw_grid = !game.do_draw_grid
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
set_direction_from_input :: proc() {
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
}

// TODO: maybe assert or return maybe type if tile out of bounds
get_adjacent_tile_type :: proc(#any_int tile_idx: i32, direction: Direction) -> Tile_Type {
    adj_idx: i32
    switch direction {
    case .None:
        adj_idx = tile_idx
    case .Left:
        adj_idx = tile_idx-1
    case .Right:
        adj_idx = tile_idx+1
    case .Up:
        adj_idx = tile_idx-COLS
    case .Down:
        adj_idx = tile_idx+COLS
    }
    return game.tile_map[adj_idx]
}

get_tile_coord_from_tile_index :: #force_inline proc "contextless" (#any_int idx: i32) -> vec2 {
    return vec2{idx % COLS, idx / COLS}
}

get_tile_from_position :: #force_inline proc "contextless" (pos: vec2) -> ^Tile_Type {
	col := pos.x / CELL_SIZE
	row := pos.y / CELL_SIZE
	return &game.tile_map[row * COLS + col]
}

get_position_from_grid_coord :: #force_inline proc "contextless" (gp: vec2) -> vec2 {
	return gp * CELL_SIZE
}

get_position_from_tile_index :: #force_inline proc "contextless" (#any_int idx: i32) -> vec2 {
	return CELL_SIZE * vec2{idx % COLS, idx / COLS}
}

TEXT_SPRITESHEET_ORDER :: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!:.,?\"-/"

draw_text :: proc(text: string, offset: vec2) {
	rg_texture(game.text_spritesheet)
	for c, i in text {
		rect := Rect{
			get_text_sprite_xoffset(c),
			0,
			CELL_SIZE,
			CELL_SIZE,
		}
		if c != ' ' {
			rg_blit(
				{(cast(i32)i * CELL_SIZE) + offset.x, offset.y},
				rect,
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
