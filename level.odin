package main

import "core:log"
import "core:os"
import "core:time"
import "core:unicode"
import "core:strings"

reset_level :: proc() {
	pos: vec2
	for marker, i in game.marker_map {
		#partial switch marker {
		case .Player_Start:
			pos = get_position_from_tile_index(i)
			game.player_position = cast(vec2f)vec2{pos.x, pos.y + CELL_SIZE/2}
		case .Blinky_Start:
			pos = get_position_from_tile_index(i)
			game.ghosts[.Blinky].position= cast(vec2f)vec2{pos.x, pos.y + CELL_SIZE/2}
		case .Pinky_Start:
			pos = get_position_from_tile_index(i)
			game.ghosts[.Pinky].position= cast(vec2f)vec2{pos.x, pos.y + CELL_SIZE/2}
		case .Inky_Start:
			pos = get_position_from_tile_index(i)
			game.ghosts[.Inky].position= cast(vec2f)vec2{pos.x, pos.y + CELL_SIZE/2}
		case .Clyde_Start:
			pos = get_position_from_tile_index(i)
			game.ghosts[.Clyde].position= cast(vec2f)vec2{pos.x, pos.y + CELL_SIZE/2}
		}
	}
	for ghost_index in Ghost_Type {
		game.ghosts[ghost_index].state = .Scatter
		game.ghosts[ghost_index].target_tile_index = GHOST_SCATTER_TARGET_TILE_INDEX[ghost_index]
	}
}
