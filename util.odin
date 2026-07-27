package main

TEXT_SPRITESHEET_ORDER :: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!:.,?\"-/%=()[]"

check_warp_actor_oob :: proc(actor: ^Actor) {
    min_x := (f32)(-2*CELL_SIZE)
    max_x := (f32)((COLS+1)*CELL_SIZE)
    if actor.position.x < min_x {
        actor.position.x = max_x
    } else if actor.position.x > max_x {
        actor.position.x = min_x
    }
}

// Since most blits have a src_rect dimensions of PLAYER_SIZE or CELL_SIZE
blit_sprite :: #force_inline proc(
	sprite_size: enum{Big, Small},
	offset, src_rect_offset: vec2,
 	flip: [2]bool = {},
  	loc := #caller_location)
{
	dim_size := PLAYER_SIZE if sprite_size == .Big else CELL_SIZE
	rg_blit(
        offset,
        Rect{src_rect_offset.x, src_rect_offset.y, dim_size, dim_size},
        flip,
        loc=loc
    )
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

get_adjacent_tile :: proc "contextless" (
	tile_coord: Tile_Coord,
 	direction: Direction) -> (^Tile_Type, bool) #optional_ok
{
    adj_coord, in_bounds := get_adjacent_tile_coord(tile_coord, direction)
    if in_bounds {
	    return &game.tile_map[adj_coord.y*COLS + adj_coord.x], true
    }
    return nil, false
}

// Returns adjacent tile coord facing specified direction
// Also returns boolean specifying if it's within bounds
get_adjacent_tile_coord :: proc "contextless" (
	tile_coord: Tile_Coord,
 	direction: Direction) -> (Tile_Coord, bool) #optional_ok
{
    adj_coord: Tile_Coord
    switch direction {
    case .None:
    	adj_coord = tile_coord
    case .Left:
    	adj_coord = {tile_coord.x - 1, tile_coord.y}
    case .Right:
        adj_coord = {tile_coord.x + 1, tile_coord.y}
    case .Up:
        adj_coord = {tile_coord.x, tile_coord.y - 1}
    case .Down:
	    adj_coord = {tile_coord.x, tile_coord.y + 1}
    }
    in_bounds := adj_coord.x >= 0 && adj_coord.x < COLS && adj_coord.y >= 0 && adj_coord.y < ROWS
    return adj_coord, in_bounds
}

get_tile_coord_from_tile_index :: #force_inline proc "contextless" (#any_int idx: i32) -> Tile_Coord
{
    return {idx % COLS, idx / COLS}
}

get_tile_coord_from_position :: #force_inline proc "contextless" (pos: vec2) -> Tile_Coord {
	return (Tile_Coord)(pos / CELL_SIZE)
}

get_tile_index_from_tile_coord :: #force_inline proc "contextless" (gp: Tile_Coord) -> i32 {
	return COLS*gp.y + gp.x
}

get_position_from_tile_coord :: #force_inline proc "contextless" (gp: Tile_Coord) -> vec2 {
	return (vec2)(gp * CELL_SIZE)
}

get_position_from_tile_index :: #force_inline proc "contextless" (#any_int idx: i32) -> vec2 {
	return CELL_SIZE * vec2{idx % COLS, idx / COLS}
}
