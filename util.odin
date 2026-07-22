package main

TEXT_SPRITESHEET_ORDER :: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!:.,?\"-/%=()[]"

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

draw_text :: proc(text: string, offset: vec2, scale: f32 = 1.0, loc := #caller_location) {
	rg_texture(game.text_spritesheet)
	rg_palette(1, color_white_4b)
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

get_adjacent_tile_type :: proc "contextless" (
	#any_int tile_idx: i32,
 	direction: Direction) -> (Tile_Type, bool) #optional_ok
{
    adj_idx, ok := get_adjacent_tile_index(tile_idx, direction)
    if ok {
	    return game.tile_map[adj_idx], true
    }
    return nil, false
}

get_adjacent_tile_index :: proc "contextless" (
	#any_int tile_idx: i32,
 	direction: Direction) -> (i32, bool) #optional_ok
{
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
        ok = (adj_idx % COLS) < COLS
    case .Up:
        adj_idx = tile_idx-COLS
        ok = adj_idx >= COLS
    case .Down:
        adj_idx = tile_idx+COLS
        ok = adj_idx <= (COLS)*(ROWS-1)
    }
    return adj_idx, ok
}

get_tile_coord_from_tile_index :: #force_inline proc "contextless" (#any_int idx: i32) -> vec2 {
    return vec2{idx % COLS, idx / COLS}
}

get_tile_index_from_position :: #force_inline proc "contextless" (pos: vec2) -> i32 {
	col := pos.x / CELL_SIZE
	row := pos.y / CELL_SIZE
	return row * COLS + col
}

get_tile_coord_from_position :: #force_inline proc "contextless" (pos: vec2) -> vec2 {
	return {pos.x / CELL_SIZE, pos.y / CELL_SIZE}
}

get_tile_index_from_tile_coord :: #force_inline proc "contextless" (gp: vec2) -> i32 {
	return COLS*gp.y + gp.x
}

get_position_from_grid_coord :: #force_inline proc "contextless" (gp: vec2) -> vec2 {
	return gp * CELL_SIZE
}

get_position_from_tile_index :: #force_inline proc "contextless" (#any_int idx: i32) -> vec2 {
	return CELL_SIZE * vec2{idx % COLS, idx / COLS}
}
