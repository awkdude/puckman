package main

import "odinlib:util"
import "core:os"
import "core:strings"
import "core:fmt"
import "core:log"

Editor_State :: struct {
	tile_placement_grid_coord: vec2,
	selected_tile: Tile_Type,
	edit_ring_buffer: [1024]Tile_Edit,
	edit_head, edit_tail: int,
}

Tile_Edit :: struct {
	tile_index: i32,
	old, current: Tile_Type,
}

MAZE_LOWER_BOUND :: 3*COLS
MAZE_UPPER_BOUND :: ((ROWS-2)*COLS)-1

editor_init :: proc() {

}

update_editor :: proc() {
	if .Left in game.input_state.mouse_buttons {
		place_tile()
	}
	bottom_margin_y := (ROWS-2)*CELL_SIZE
	rg_fill_rect(
		Rect{0, bottom_margin_y, INTERN_FRAMEBUFFER_DIMS.x, PLAYER_SIZE},
		color_grey_4b
	)
	tile_sprite := TILE_SPRITES[cast(Tile_Type)game.editor.selected_tile]
	rg_texture(game.tile_spritesheet)
	rg_blit(get_position_from_grid_coord({7, ROWS-2}), tile_sprite.rect, tile_sprite.flip, PLAYER_DIMS)
	draw_text("TILE: ", get_position_from_tile_index(COLS*(ROWS-1)))
	pos := get_position_from_grid_coord(game.editor.tile_placement_grid_coord)
	rg_fill_rect(Rect{pos.x, pos.y, CELL_SIZE, CELL_SIZE}, color_purple_4b)
}


@(private="file")
place_tile :: proc() {
	tile_placement_tile_index := get_tile_index_from_tile_coord(game.editor.tile_placement_grid_coord)
	if tile_placement_tile_index < MAZE_LOWER_BOUND || tile_placement_tile_index > MAZE_UPPER_BOUND do return
	old_tile := game.tile_map[tile_placement_tile_index]
	game.tile_map[tile_placement_tile_index] = cast(Tile_Type)game.editor.selected_tile
	if game.editor.selected_tile != old_tile {
		tile_edit := Tile_Edit {
			tile_index=tile_placement_tile_index,
			old=old_tile,
			current=cast(Tile_Type)game.editor.selected_tile,
		}
		game.editor.edit_ring_buffer[game.editor.edit_tail] = tile_edit
		game.editor.edit_tail = (game.editor.edit_tail + 1) % len(game.editor.edit_ring_buffer)
		if game.editor.edit_tail == game.editor.edit_head {
			game.editor.edit_head = (game.editor.edit_head + 1) % len(game.editor.edit_ring_buffer)
		}
		log.debugf("TAIL: %v, HEAD: %v", game.editor.edit_tail, game.editor.edit_head)
	}
}

@(private="file")
undo_tile_edit :: proc() {
	if game.editor.edit_head == game.editor.edit_tail do return
	game.editor.edit_tail = util.wrap(game.editor.edit_tail - 1, len(game.editor.edit_ring_buffer))
	tile_edit := game.editor.edit_ring_buffer[game.editor.edit_tail]
	game.tile_map[tile_edit.tile_index] = tile_edit.old
}

editor_handle_event :: proc(window_event: util.Window_Event) {
	#partial switch window_event.type {
	case .Mouse_Move:
		mouse_pos := (vec2)(cast(vec2f)INTERN_FRAMEBUFFER_DIMS * (cast(vec2f)window_event.vec2 / cast(vec2f)game.window_size))
		mouse_tile_index := get_tile_index_from_position(mouse_pos)
		mouse_tile_pos := get_position_from_tile_index(mouse_tile_index)
		game.editor.tile_placement_grid_coord = mouse_pos / {CELL_SIZE, CELL_SIZE}
	case .Mouse_Button:
	case .Key:
		if !window_event.key.pressed do return
		switch window_event.key.keycode {
		case util.KEY_UP:
			game.editor.tile_placement_grid_coord.y = util.wrap(game.editor.tile_placement_grid_coord.y - 1, ROWS)
		case util.KEY_DOWN:
			game.editor.tile_placement_grid_coord.y = util.wrap(game.editor.tile_placement_grid_coord.y + 1, ROWS)
		case util.KEY_LEFT:
			game.editor.tile_placement_grid_coord.x = util.wrap(game.editor.tile_placement_grid_coord.x - 1, COLS)
		case util.KEY_RIGHT:
			game.editor.tile_placement_grid_coord.x = util.wrap(game.editor.tile_placement_grid_coord.x + 1, COLS)
		}
		if window_event.key.repeated do return
		switch window_event.key.keycode {
		case util.KEY_S:
			save_tile_map()
		case util.KEY_Z:
			undo_tile_edit()
		case util.KEY_RETURN:
			place_tile()
		case util.KEY_INSERT:
			select_int := cast(int)game.editor.selected_tile
			select_int = util.wrap(select_int + 1, len(Tile_Type))
			game.editor.selected_tile = cast(Tile_Type)select_int
		case util.KEY_DELETE:
			select_int := cast(int)game.editor.selected_tile
			select_int = util.wrap(select_int - 1, len(Tile_Type))
			game.editor.selected_tile = cast(Tile_Type)select_int
		}
	case .Mouse_Wheel:
		select_int := cast(int)game.editor.selected_tile
		select_int = util.wrap(select_int + cast(int)window_event.vec2.y, len(Tile_Type))
		game.editor.selected_tile = cast(Tile_Type)select_int
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
    log.debug(data_i)
    log.debug(len(level_data))
    for ; data_i < len(level_data); data_i += 1 {
        if tile_i >= num_tiles do break
        if level_data[data_i] == '\n' || level_data[data_i] == '\r' do continue
        index := strings.index_rune(CHAR_TILE_MAP, cast(rune)level_data[data_i])
        log.assertf(index != -1 && index < len(Tile_Type), "Unknown tile char: %c", level_data[data_i])
        tile := cast(Tile_Type)index
        game.tile_map[tile_i] = tile
        tile_i += 1
    }
    assert(cast(i32)tile_i == ROWS*COLS)
    log.debug(tile_i)
}

save_tile_map :: proc() {
	file, err := os.open("maze.txt", {.Write, .Create, .Trunc})
	assert(err == nil)
	defer os.close(file)
	sb, sb_err := strings.builder_make(context.temp_allocator)
	assert(sb_err == nil)

	for tile_type, i in Tile_Type {
		fmt.sbprintfln(&sb, "# %v: %c", tile_type, CHAR_TILE_MAP[i])
	}
	for tile, i in game.tile_map {
		strings.write_rune(&sb, cast(rune)CHAR_TILE_MAP[cast(int)tile])
		if cast(i32)i % COLS == COLS-1 {
			strings.write_rune(&sb, '\n')
		}
	}
	os.write(file, transmute([]u8)strings.to_string(sb))
}
