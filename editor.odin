package main

import "odinlib:util"
import "core:os"
import "core:strings"
import "core:fmt"
import "core:log"

Editor_State :: struct {
	tile_placement_tile_coord: Tile_Coord,
	selected_tile: Tile_Type,
	selected_marker_tile: Marker_Tile_Type,
	edit_ring_buffer: [1024]Tile_Edit,
	edit_head, edit_tail: int,
	mode: enum {Tile, Marker,},
	// Prevents me from accidentally editing map
	unlocked: bool,
}

Tile_Edit :: struct {
	tile_coord: Tile_Coord,
	old, current: Tile_Type,
}

MAZE_LOWER_BOUND_Y :: 3
MAZE_UPPER_BOUND_Y :: ROWS-2

editor_init :: proc() {

}

update_editor :: proc() {
	bottom_margin_y := (ROWS-2)*CELL_SIZE
	pos := get_position_from_tile_coord(game.editor.tile_placement_tile_coord)
	rg_fill_rect(
		Rect{0, bottom_margin_y, INTERN_FRAMEBUFFER_DIMS.x, PLAYER_SIZE},
		color_grey_4b
	)
	if game.editor.mode == .Tile {
		select_int := cast(int)game.editor.selected_tile
		select_int = util.wrap(select_int + cast(int)game.input_state.mouse_wheel_delta.y, len(Tile_Type))
		game.editor.selected_tile = cast(Tile_Type)select_int
		if .Left in game.input_state.mouse_buttons {
			place_tile()
		}
		tile_sprite := TILE_SPRITES[cast(Tile_Type)game.editor.selected_tile]
		rg_texture(game.spritesheet)
		rg_blit(
            get_position_from_tile_coord({7, ROWS-2}),
            Rect{
                tile_sprite.src_offset.x,
                tile_sprite.src_offset.y,
                CELL_SIZE,
                CELL_SIZE
            },
            tile_sprite.flip,
            PLAYER_DIMS
        )
		draw_text("TILE: ", get_position_from_tile_coord({0, ROWS-1}))
		rg_fill_rect(Rect{pos.x, pos.y, CELL_SIZE, CELL_SIZE}, color_purple_4b)
	} else if game.editor.mode == .Marker {
		select_int := cast(int)game.editor.selected_marker_tile
		select_int = util.wrap(select_int + cast(int)game.input_state.mouse_wheel_delta.y, len(Marker_Tile_Type))
		game.editor.selected_marker_tile = cast(Marker_Tile_Type)select_int
		if .Left in game.input_state.mouse_buttons {
			place_marker_tile()
		}
		switch game.editor.selected_marker_tile {
		case .None:
		case .Player_Start:
			rg_texture(game.player_spritesheet)
			rg_blit(get_position_from_tile_coord({7, ROWS-2}), Rect{0, 0, PLAYER_SIZE, PLAYER_SIZE})
		case .Blinky_Start:
			rg_texture(game.ghost_spritesheet)
			rg_palette(1, GHOST_COLORS[.Blinky])
			rg_blit(get_position_from_tile_coord({7, ROWS-2}), Rect{2*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE})
		case .Pinky_Start:
			rg_texture(game.ghost_spritesheet)
			rg_palette(1, GHOST_COLORS[.Pinky])
			rg_blit(get_position_from_tile_coord({7, ROWS-2}), Rect{2*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE})
		case .Inky_Start:
			rg_texture(game.ghost_spritesheet)
			rg_palette(1, GHOST_COLORS[.Inky])
			rg_blit(get_position_from_tile_coord({7, ROWS-2}), Rect{2*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE})
		case .Clyde_Start:
			rg_texture(game.ghost_spritesheet)
			rg_palette(1, GHOST_COLORS[.Clyde])
			rg_blit(get_position_from_tile_coord({7, ROWS-2}), Rect{2*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE})
		case .Ghost_Decision:
			p := get_position_from_tile_coord({7, ROWS-2})
			rg_fill_rect(Rect{p.x, p.y, PLAYER_SIZE, PLAYER_SIZE}, color_green_4b)
		case .Slow_Zone:
			p := get_position_from_tile_coord({7, ROWS-2})
			rg_fill_rect(Rect{p.x, p.y, PLAYER_SIZE, PLAYER_SIZE}, color_tortilla_4b)
		case .No_Up_Zone:
			p := get_position_from_tile_coord({7, ROWS-2})
			rg_fill_rect(Rect{p.x, p.y, PLAYER_SIZE, PLAYER_SIZE}, color_lemon_4b)
		}
		draw_text("MARKER: ", get_position_from_tile_index(COLS*(ROWS-1)))
		rg_fill_rect(Rect{pos.x, pos.y, CELL_SIZE, CELL_SIZE}, color_brown_4b)
		// Render marker rects
		for marker, i in game.marker_map {
			color: Color4b
			switch marker {
			case .None:
				continue
			case .Player_Start:
				color = color_yellow_4b
			case .Blinky_Start:
				color = GHOST_COLORS[.Blinky]
			case .Pinky_Start:
				color = GHOST_COLORS[.Pinky]
			case .Inky_Start:
				color = GHOST_COLORS[.Inky]
			case .Clyde_Start:
				color = GHOST_COLORS[.Clyde]
			case .Ghost_Decision:
				color = color_green_4b
			case .Slow_Zone:
				color = color_tortilla_4b
			case .No_Up_Zone:
				color = color_lemon_4b
			}
			if util.blink_state(game.frame_counter, 60) == 0 {
				tile_pos := get_position_from_tile_index(i)
				rg_fill_rect(Rect{tile_pos.x, tile_pos.y, CELL_SIZE, CELL_SIZE}, color)
			}
		}
	}
}

@(private="file")
place_marker_tile :: proc() {
	if !game.editor.unlocked do return
	DUPABLE_MARKERS := bit_set[Marker_Tile_Type]{.None, .Ghost_Decision, .Slow_Zone, .No_Up_Zone}
	if game.editor.tile_placement_tile_coord.y < MAZE_LOWER_BOUND_Y || game.editor.tile_placement_tile_coord.y > MAZE_UPPER_BOUND_Y do return
	// Clear any occurance of this marker type before setting to tile pos if non-duplicatable
	if game.editor.selected_marker_tile not_in DUPABLE_MARKERS {
		for &tile in game.marker_map {
			if tile == game.editor.selected_marker_tile {
				tile = .None
			}
		}
	}
	tile_placement_tile_index := get_tile_index_from_tile_coord(game.editor.tile_placement_tile_coord)
	game.marker_map[tile_placement_tile_index] = game.editor.selected_marker_tile
}

@(private="file")
place_tile :: proc() {
	if !game.editor.unlocked do return
	if game.editor.tile_placement_tile_coord.y < MAZE_LOWER_BOUND_Y || game.editor.tile_placement_tile_coord.y > MAZE_UPPER_BOUND_Y do return
	tile_placement_tile_index := get_tile_index_from_tile_coord(game.editor.tile_placement_tile_coord)
	old_tile := game.full_tile_map[tile_placement_tile_index]
	game.full_tile_map[tile_placement_tile_index] = cast(Tile_Type)game.editor.selected_tile
	if game.editor.selected_tile != old_tile {
		tile_edit := Tile_Edit {
			tile_coord=game.editor.tile_placement_tile_coord,
			old=old_tile,
			current=cast(Tile_Type)game.editor.selected_tile,
		}
		game.editor.edit_ring_buffer[game.editor.edit_tail] = tile_edit
		game.editor.edit_tail = (game.editor.edit_tail + 1) % len(game.editor.edit_ring_buffer)
		if game.editor.edit_tail == game.editor.edit_head {
			game.editor.edit_head = (game.editor.edit_head + 1) % len(game.editor.edit_ring_buffer)
		}
	}
}

@(private="file")
undo_tile_edit :: proc() {
	if !game.editor.unlocked do return
	if game.editor.edit_head == game.editor.edit_tail do return
	game.editor.edit_tail = util.wrap(game.editor.edit_tail - 1, len(game.editor.edit_ring_buffer))
	tile_edit := game.editor.edit_ring_buffer[game.editor.edit_tail]
	tile_index := get_tile_index_from_tile_coord(tile_edit.tile_coord)
	game.full_tile_map[tile_index] = tile_edit.old
}

editor_handle_event :: proc(window_event: util.Window_Event) {
	#partial switch window_event.type {
	case .Mouse_Move:
		mouse_pos := (vec2)(cast(vec2f)INTERN_FRAMEBUFFER_DIMS * (cast(vec2f)window_event.vec2 / cast(vec2f)game.window_size))
		// mouse_tile_index := get_tile_index_from_position(mouse_pos)
		// mouse_tile_pos := get_position_from_tile_index(mouse_tile_index)
		game.editor.tile_placement_tile_coord = get_tile_coord_from_position(mouse_pos)
	case .Mouse_Button:
	case .Key:
		if !window_event.key.pressed || window_event.key.repeated do return
		switch window_event.key.keycode {
		case util.KEY_F2:
			game.editor.mode = .Tile if game.editor.mode == .Marker else .Marker
		case util.KEY_S:
			save_tile_map()
		case util.KEY_Z:
			undo_tile_edit()
		case util.KEY_RETURN:
			place_tile()
		case util.KEY_0:
			game.editor.unlocked = !game.editor.unlocked
		case util.KEY_INSERT:
			if game.editor.mode == .Tile {
				select_int := cast(int)game.editor.selected_tile
				select_int = util.wrap(select_int + 1, len(Tile_Type))
				game.editor.selected_tile = cast(Tile_Type)select_int
			} else if game.editor.mode == .Marker {

			}
		case util.KEY_DELETE:
			if game.editor.mode == .Tile {
				select_int := cast(int)game.editor.selected_tile
				select_int = util.wrap(select_int - 1, len(Tile_Type))
				game.editor.selected_tile = cast(Tile_Type)select_int
			} else if game.editor.mode == .Marker {

			}
		}
	}
}

load_tile_map :: proc() {
	level_data, read_err := os.read_entire_file_from_path("maze.txt", context.temp_allocator)
	assert(read_err == nil)
    tile_i := 0
    num_tiles := (int)(ROWS*COLS)
    did_place_pacman := false
    did_place_ghosts: [Ghost_Type]bool
    data_i := 0
    // Skip comments
    if level_data[data_i] == '#' {
    	data_i += 1
    	for {
     		if level_data[data_i] == '\n' {
       			data_i += 1
          		if level_data[data_i] != '#' {
            		break
            	}
       		} else if level_data[data_i] == '\r' {
     			data_i += 2
	      		if level_data[data_i] != '#' {
	        		break
	        	}
      		}
        	data_i += 1
     	}
    }
    for ; tile_i < num_tiles; data_i += 1 {
        if level_data[data_i] == '\n' || level_data[data_i] == '\r' do continue
        index := strings.index_rune(CHAR_TILE_MAP, cast(rune)level_data[data_i])
        log.assertf(
        	index != -1 && index < len(Tile_Type),
         	"Unknown tile char: %c",
          	level_data[data_i]
        )
        tile := cast(Tile_Type)index
        game.full_tile_map[tile_i] = tile
        tile_i += 1
    }
    data_i += 1
    tile_i = 0
    for ; tile_i < num_tiles; data_i += 1 {
        if level_data[data_i] == '\n' || level_data[data_i] == '\r' do continue
        index := strings.index_rune(CHAR_MARKER_MAP, cast(rune)level_data[data_i])
        log.assertf(
        	index != -1 && index < len(Marker_Tile_Type),
         	"Unknown tile char: %c",
          	level_data[data_i]
        )
        marker_tile := cast(Marker_Tile_Type)index
        game.marker_map[tile_i] = marker_tile
        tile_i += 1
    }
}

save_tile_map :: proc() {
	if !game.editor.unlocked do return
	file, err := os.open("maze.txt", {.Write, .Create, .Trunc})
	assert(err == nil)
	defer os.close(file)
	sb, sb_err := strings.builder_make(context.temp_allocator)
	assert(sb_err == nil)

	// Write legend comment section
	strings.write_string(&sb, "# *LEGEND FOR TILE MAP*\n")
	for tile_type, i in Tile_Type {
		fmt.sbprintfln(&sb, "# %v: %c", tile_type, CHAR_TILE_MAP[i])
	}
	strings.write_string(&sb, "# *LEGEND FOR MARKER MAP*\n")
	for marker_type, i in Marker_Tile_Type {
		fmt.sbprintfln(&sb, "# %v: %c", marker_type, CHAR_MARKER_MAP[i])
	}
	// Write tile data into maze.txt
	for tile, i in game.full_tile_map {
		strings.write_rune(&sb, cast(rune)CHAR_TILE_MAP[cast(int)tile])
		if cast(i32)i % COLS == COLS-1 {
			strings.write_rune(&sb, '\n')
		}
	}
	strings.write_string(&sb, "\n")
	// Write marker tile data into maze.txt
	for marker, i in game.marker_map {
		strings.write_rune(&sb, cast(rune)CHAR_MARKER_MAP[cast(int)marker])
		if cast(i32)i % COLS == COLS-1 {
			strings.write_rune(&sb, '\n')
		}
	}

	os.write(file, transmute([]u8)strings.to_string(sb))
}
