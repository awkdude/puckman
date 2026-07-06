package main

import "core:log"
import "core:os"
import "core:time"

last_level_modify_time: time.Time

try_setup_level :: proc(override: bool = false) {
	level_file, open_err := os.open("level.txt")
	assert(open_err == nil)
	defer os.close(level_file)
	modify_time, modify_err := os.modification_time(level_file)
	assert(modify_err == nil)
	if !override && time.diff(last_level_modify_time, modify_time) <= 0 do return
	level_data, read_err := os.read_entire_file_from_path("level.txt", context.temp_allocator)
	assert(read_err == nil)
	last_level_modify_time = time.now()
    tile_i := 0
    num_tiles := (int)(ROWS*COLS)
    did_place_pacman := false
    did_place_ghosts: [Ghost_Type]bool
    data_i := 0
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
        tile: Tile_Type
        switch level_data[data_i] {
        case '0', ' ':
        	tile = .None
        case '.':
        	tile = .Dot
        case '*':
        	tile = .Pellet
        case 'l':
            tile = .Wall_Left
        case 'r':
            tile = .Wall_Right
        case 't':
            tile = .Wall_Top
        case 'b':
            tile = .Wall_Bottom
        case '7':
            tile = .Wall_Top_Left
        case '9':
            tile = .Wall_Top_Right
        case '1':
            tile = .Wall_Bottom_Left
        case '3':
            tile = .Wall_Bottom_Right
        case 'Q':
        	tile = .Border_Top_Left
        case 'P':
        	tile = .Border_Top_Right
        case 'Z':
        	tile = .Border_Bottom_Left
        case 'M':
        	tile = .Border_Bottom_Right
        case 'q':
        	tile = .Border_Sharp_Top_Left
        case 'p':
        	tile = .Border_Sharp_Top_Right
        case 'z':
        	tile = .Border_Sharp_Bottom_Left
        case 'm':
        	tile = .Border_Sharp_Bottom_Right
        case '+':
        	tile = .Ghost_Pass
        case 'T':
        	tile = .Border_Top
        case 'B':
        	tile = .Border_Bottom
        case 'L':
        	tile = .Border_Left
        case 'R':
        	tile = .Border_Right
        case '!':
        	assert(!did_place_pacman, "Pacman starting marker appears more than once!")
         	game.player_position = cast(vec2f)get_position_from_tile_index(tile_i) + cast(vec2f)CELL_SIZE/2
        	did_place_pacman = true
        case '@':
        	assert(!did_place_ghosts[.Blinky], "Blinky starting makrer appears more than once!")
        	game.ghosts[.Blinky].position = cast(vec2f)get_position_from_tile_index(tile_i) + cast(vec2f)CELL_SIZE/2
	       	did_place_ghosts[.Blinky] = true
        case '#':
        	assert(!did_place_ghosts[.Pinky], "Pinky starting makrer appears more than once!")
        	game.ghosts[.Pinky].position = cast(vec2f)get_position_from_tile_index(tile_i) + cast(vec2f)CELL_SIZE/2
	       	did_place_ghosts[.Pinky] = true
        case '$':
        	assert(!did_place_ghosts[.Inky], "Inky starting makrer appears more than once!")
        	game.ghosts[.Inky].position = cast(vec2f)get_position_from_tile_index(tile_i) + cast(vec2f)CELL_SIZE/2
	       	did_place_ghosts[.Inky] = true
        case '%':
        	assert(!did_place_ghosts[.Clyde], "Clyde starting makrer appears more than once!")
        	game.ghosts[.Clyde].position = cast(vec2f)get_position_from_tile_index(tile_i) + cast(vec2f)CELL_SIZE/2
	       	did_place_ghosts[.Clyde] = true
        case:
            continue
        }
        game.tile_map[tile_i] = tile
        tile_i += 1
    }
    assert(cast(i32)tile_i == ROWS*COLS)
    assert(did_place_pacman, "Pac-man was not set in the level data")
    assert(did_place_ghosts[.Blinky], "Blinky was not set in the level data")
    assert(did_place_ghosts[.Pinky], "Pinky was not set in the level data")
    assert(did_place_ghosts[.Inky], "Inky was not set in the level data")
    assert(did_place_ghosts[.Clyde], "Clyde was not set in the level data")
    log.debug(tile_i)
}
