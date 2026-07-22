package main

import "core:log"
import "core:os"
import "core:time"
import "core:unicode"
import "core:strings"

reset_level :: proc() {
	pos: vec2
	game.tile_map = game.full_tile_map
	for marker, i in game.marker_map {
		#partial switch marker {
		case .Player_Start:
			pos = get_position_from_tile_index(i)
			game.player.position = cast(vec2f)vec2{pos.x, pos.y + CELL_SIZE/2}
		case .Blinky_Start:
			game.ghosts[.Blinky].tile_index = cast(i32)i
		case .Pinky_Start:
			game.ghosts[.Pinky].tile_index = cast(i32)i
		case .Inky_Start:
			game.ghosts[.Inky].tile_index = cast(i32)i
		case .Clyde_Start:
			game.ghosts[.Clyde].tile_index = cast(i32)i
		}
		if game.ghost_pass_tile_index == 0 && game.tile_map[i] == .Ghost_Pass {
			game.ghost_pass_tile_index = cast(i32)i
		}
	}
	game.ghost_global_mode = .Chase
	for ghost_index in Ghost_Type {
        ghost_actor := &game.ghosts[ghost_index]
        tile_pos := get_position_from_tile_index(ghost_actor.tile_index)
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
		ghost_actor.target_tile_index = GHOST_SCATTER_TARGET_TILE_INDEX[ghost_index]
		ghost_actor.next_tile_index, _ = ghost_decide_next_move(ghost_actor, ghost_index)
		next_tile_coord := get_tile_coord_from_tile_index(ghost_actor.next_tile_index)
		log.debugf("NEXT: %v is %v going %v", ghost_index, next_tile_coord, ghost_actor.direction)
	}
}
