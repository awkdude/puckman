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
        case '.':
        	game.tile_map[tile_i] = .Dot
        case '*':
        	game.tile_map[tile_i] = .Pellet
        case '|':
            game.tile_map[tile_i] = .Wall_Vert
        case '-':
            game.tile_map[tile_i] = .Wall_Horz
        case '7':
            game.tile_map[tile_i] = .Wall_Top_Left
        case '9':
            game.tile_map[tile_i] = .Wall_Top_Right
        case '1':
            game.tile_map[tile_i] = .Wall_Bottom_Left
        case '3':
            game.tile_map[tile_i] = .Wall_Bottom_Right
        case :
            continue
        }
        tile_i += 1
    }
    log.debug(tile_i)
}
