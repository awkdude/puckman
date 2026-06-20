package main

import "core:log"

level_data := #load("level.txt")

WALL_VERT :: '|'
WALL_HORI :: '-'
WALL_CORNER :: '+'

// TODO: drop corner logic

setup_level :: proc() {
    tile_i := 0
    num_tiles := (int)(ROWS*COLS)
    for data_i in 0..<len(level_data) {
        if tile_i >= num_tiles do break
        switch level_data[data_i] {
        case '0', ' ':
        	game.tile_map[tile_i] = .None
        case '|':
            game.tile_map[tile_i] = .Wall_Vert
        case '-':
            game.tile_map[tile_i] = .Wall_Horz
        case '+':
            game.tile_map[tile_i] = .Unused
        case :
            continue
        }
        tile_i += 1
    }
    log.debug(tile_i)
    // Fill corner walls
    for &tile, tile_i in game.tile_map {
        // TODO: assert this isn't at edge of map
        if tile != .Unused do continue
        left := get_adjacent_tile_type(tile_i, .Left)
        right := get_adjacent_tile_type(tile_i, .Right)
        up := get_adjacent_tile_type(tile_i, .Up)
        down := get_adjacent_tile_type(tile_i, .Down)
        row := cast(i32)tile_i / COLS
        col := cast(i32)tile_i % COLS
        assert(row > 0, "Corner not allowed on top edge")
        assert(row < ROWS-1, "Corner not allowed on bottom edge")
        assert(col > 0, "Corner not allowed on left edge")
        assert(col < COLS-1, "Corner not allowed on right edge")
        if up == .Wall_Vert {
            if left == .Wall_Horz {
                tile = .Wall_Bottom_Right
            } else if right == .Wall_Horz {
                tile = .Wall_Bottom_Left
            }
        } else if down == .Wall_Vert {
            if left == .Wall_Horz {
                tile = .Wall_Top_Right
            } else if right == .Wall_Horz {
                tile = .Wall_Top_Left
            }
        }
    }
}
