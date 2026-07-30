package main

import "core:log"
import "core:os"
import "core:time"
import "core:unicode"
import "core:strings"

reset_level :: proc() {
	pos: vec2
	game.tile_map = game.full_tile_map
    game.max_num_dots = 0
	for marker, i in game.marker_map {
		#partial switch marker {
		case .Player_Start:
			pos = get_position_from_tile_index(i)
			game.player.position = cast(vec2f)vec2{pos.x, pos.y + CELL_SIZE/2}
		// NOTE: I set ghost position later
		case .Blinky_Start:
			game.ghosts[.Blinky].tile_coord = get_tile_coord_from_tile_index(i)
		case .Pinky_Start:
			game.ghosts[.Pinky].tile_coord = get_tile_coord_from_tile_index(i)
		case .Inky_Start:
			game.ghosts[.Inky].tile_coord = get_tile_coord_from_tile_index(i)
		case .Clyde_Start:
			game.ghosts[.Clyde].tile_coord = get_tile_coord_from_tile_index(i)
		}
		if game.ghost_pass_tile_coord == 0 && game.tile_map[i] == .Ghost_Pass {
			game.ghost_pass_tile_coord = get_tile_coord_from_tile_index(i)
            game.ghost_revive_tile_coord = game.ghost_pass_tile_coord + {0, 2}
		}
        if game.tile_map[i] == .Dot {
            game.max_num_dots += 1
        }
	}
    game.dots_remaining = game.max_num_dots
	game.ghost_global_mode = .Chase
	for ghost_index in Ghost_Type {
        ghost_actor := &game.ghosts[ghost_index]
        tile_pos := get_position_from_tile_coord(ghost_actor.tile_coord)
		current_tile_center := tile_pos + (CELL_SIZE/2)
        ghost_actor.position = cast(vec2f)current_tile_center
		#partial switch ghost_actor.direction {
            case .Up, .Down:
                // Position player x value to tile's center x if up or down
                ghost_actor.position.x = cast(f32)current_tile_center.x
            case .Left, .Right:
                // Position player y value to tile's center y if left or right
                ghost_actor.position.y = cast(f32)current_tile_center.y
        }
		ghost_actor.mode = .None
		ghost_actor.target_tile_coord = GHOST_SCATTER_TARGET_TILE_COORD[ghost_index]
		ghost_actor.next_tile_coord, _ = ghost_decide_next_move(ghost_actor, ghost_index)
		next_tile_coord := ghost_actor.next_tile_coord
		log.debugf("NEXT: %v is %v going %v", ghost_index, next_tile_coord, ghost_actor.direction)
	}
}
