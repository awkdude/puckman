package main

import "core:math"
import "core:math/bits"
import "core:slice"
import "core:log"
import "core:fmt"
import "odinlib:util"

Ghost_Logic_Proc :: #type proc "contextless"(ghost_actor: ^Ghost_Actor)

slight_offset := [Ghost_Type]vec2 {
	.Blinky = {0, -1},
	.Pinky = {1, 0},
	.Inky = {0, 1},
	.Clyde = {-1, 0},
}

// Make all ghosts frightened
frighten_all :: proc(state: Ghost_Unique_Mode) {
	for &ghost in game.ghosts {
		if ghost.mode == .None {
			ghost.mode = .Frightened
		}
	}
	game.frightened_sim_tick = 30*6
	game.eat_count = 0
}

update_ghosts :: proc() {
    GHOST_SPEED :: 0.5
	for ghost_index in Ghost_Type {
        ghost_actor := &game.ghosts[ghost_index]
        ghost_actor.ticks_until_next_tile_change -= 1
        current_tile_index := get_tile_index_from_position(cast(vec2)ghost_actor.position)
        next_tile := get_adjacent_tile_type(ghost_actor.tile_index, ghost_actor.direction)
        ghost_speed: f32 = GHOST_SPEED if ghost_actor.mode != .Eaten else GHOST_SPEED*3.0
        if current_tile_index == ghost_actor.next_tile_index {
           	tile_center_pos := get_position_from_tile_index(ghost_actor.next_tile_index) + {CELL_SIZE/2, CELL_SIZE/2}
           	diff := ghost_actor.position - cast(vec2f)tile_center_pos
            cond: bool
            cond = math.abs(diff.x) < ghost_speed && math.abs(diff.y) < ghost_speed
            if ghost_speed > 2.6 {
            	// ghost_actor.position = cast(vec2f)tile_center_pos
	            // cond = true
            }
            if ghost_index == .Blinky {
            	next_tile_coord := get_tile_coord_from_tile_index(ghost_actor.next_tile_index)
            	log.debugf("NEXT: %v, DIFF: %v", next_tile_coord, diff)
            }
           	if cond && ghost_actor.ticks_until_next_tile_change <= 0 {
          		ghost_actor.next_tile_index, _ = ghost_decide_next_move(ghost_actor, ghost_index)
            	ghost_actor.ticks_until_next_tile_change = 3
           	}
        } else if next_tile not_in PASSABLE_TILES {
            ghost_actor.next_tile_index, _ = ghost_decide_next_move(ghost_actor, ghost_index)
           	// ghost_actor.ticks_until_next_tile_change = 3
        }
        ghost_actor.tile_index = current_tile_index
        next_tile = get_adjacent_tile_type(ghost_actor.tile_index, ghost_actor.direction)

        tile_pos := get_position_from_tile_index(ghost_actor.tile_index)
        current_tile_center := tile_pos + {CELL_SIZE/2, CELL_SIZE/2}
        ghost_actor.position += ghost_speed * DIRECTION_VECTORS[ghost_actor.direction]
        if next_tile not_in PASSABLE_TILES {
            #partial switch ghost_actor.direction {
            case .Left:
                ghost_actor.position.x = max(cast(f32)current_tile_center.x, ghost_actor.position.x)
            case .Right:
                ghost_actor.position.x = min(cast(f32)current_tile_center.x, ghost_actor.position.x)
            case .Up:
                ghost_actor.position.y = max(cast(f32)current_tile_center.y, ghost_actor.position.y)
            case .Down:
                ghost_actor.position.y = min(cast(f32)current_tile_center.y, ghost_actor.position.y)
            }
        }
	}
}

// Returns next tile that ghost will target
ghost_decide_next_move :: proc(ghost: ^Ghost_Actor, ghost_index: Ghost_Type) -> (i32, bool) {
	min_dist: i32 = bits.I32_MAX
	min_dir := Direction.None
	min_adj_tile_index := ghost.tile_index
	target_tile_coord := get_tile_coord_from_tile_index(ghost.target_tile_index)
	dirs_to_check := [?]Direction {.Up, .Left, .Down, .Right}
	for direction in dirs_to_check {
		if direction == OPPOSITE_DIRECTION[ghost.direction] do continue
		adj_tile_index, ok := get_adjacent_tile_index(ghost.tile_index, direction)
		// assert(ok)
		if !ok do continue
		if game.tile_map[adj_tile_index] not_in PASSABLE_TILES do continue
		adj_tile_coord := get_tile_coord_from_tile_index(adj_tile_index)
		dist_vec := target_tile_coord - adj_tile_coord
		dist := (dist_vec.x * dist_vec.x) + (dist_vec.y * dist_vec.y)
		// Apparently, it uses the manhattan distance formula
		// dist := math.abs(dist_vec.x) + math.abs(dist_vec.y)
		if dist < min_dist {
			min_dir = direction
			min_dist = dist
			min_adj_tile_index = adj_tile_index
		}
	}
	if min_dir != .None {
		ghost.direction = min_dir
		tile_pos := get_position_from_tile_index(ghost.tile_index)
		current_tile_center := tile_pos + {CELL_SIZE/2, CELL_SIZE/2}
		#partial switch ghost.direction {
        case .Up, .Down:
            // Position player x value to tile's center x if up or down
            ghost.position.x = cast(f32)current_tile_center.x
        case .Left, .Right:
            // Position player y value to tile's center y if left or right
            ghost.position.y = cast(f32)current_tile_center.y
        }

	} else {
		return 0, false
	}
	log.assertf(min_adj_tile_index != ghost.tile_index, "%v == %v", min_adj_tile_index, ghost.tile_index)
	return min_adj_tile_index, true
}

calculate_ghost_targets :: proc() {
	tile_index_ahead_of_player :: proc "contextless" (player_tile_index, distance: i32) -> i32 {
		target_tile_index: i32
		ok: bool
		switch game.player.direction {
		case .None:
		case .Left:
	        target_tile_index = game.player.tile_index-distance
			col := target_tile_index % COLS
			player_col := player_tile_index % COLS
	        ok = col < player_tile_index && col < player_col
	    case .Right:
	        target_tile_index = game.player.tile_index+distance
			col := target_tile_index % COLS
			player_col := game.player.tile_index % COLS
	        ok = col < COLS && col > player_col
	    case .Up:
	        target_tile_index = game.player.tile_index-COLS*distance
	        ok = target_tile_index >= COLS
	    case .Down:
	        target_tile_index = game.player.tile_index+COLS*distance
	        ok = target_tile_index <= COLS*(ROWS-1)
	    }
		return target_tile_index if ok else game.player.tile_index
	}

    for ghost_index in Ghost_Type {
        ghost_actor := &game.ghosts[ghost_index]
        if ghost_actor.mode == .Frightened {
            // TODO:
        } else if ghost_actor.mode == .Eaten {
            ghost_actor.target_tile_index = game.ghost_pass_tile_index
        } else if game.ghost_global_mode == .Scatter {
			ghost_actor.target_tile_index = GHOST_SCATTER_TARGET_TILE_INDEX[ghost_index]
        } else if game.ghost_global_mode == .Chase {
            target_logic := [Ghost_Type]Ghost_Logic_Proc {
                .Blinky = proc "contextless"(ghost_actor: ^Ghost_Actor) {
                    ghost_actor.target_tile_index = game.player.tile_index
                },
                .Pinky = proc "contextless"(ghost_actor: ^Ghost_Actor) {
                    ghost_actor.target_tile_index = tile_index_ahead_of_player(game.player.tile_index, 4)
                },
                .Inky = proc "contextless"(ghost_actor: ^Ghost_Actor) {
                    ahead_tile_index := tile_index_ahead_of_player(game.player.tile_index, 2)
                    ahead_tile_coord := get_tile_coord_from_tile_index(ahead_tile_index)
                    blinky_tile_coord := get_tile_coord_from_position(cast(vec2)game.ghosts[.Blinky].position)
                    dist_vec := (ahead_tile_coord - blinky_tile_coord) * 2
                    final_tile_coord := blinky_tile_coord + dist_vec
                    final_tile_coord.x = math.clamp(final_tile_coord.x, 0, COLS-1)
                    final_tile_coord.y = math.clamp(final_tile_coord.y, 0, ROWS-1)
                    ghost_actor.target_tile_index = get_tile_index_from_tile_coord(final_tile_coord)
                },
                .Clyde = proc "contextless"(ghost_actor: ^Ghost_Actor) {
                    player_tile_coord := get_tile_coord_from_tile_index(game.player.tile_index)
                    ghost_tile_coord := get_tile_coord_from_position(
                        cast(vec2)game.ghosts[.Clyde].position
                    )
                    tile_dx := (player_tile_coord.x - ghost_tile_coord.x)
                    tile_dy := (player_tile_coord.y - ghost_tile_coord.y)
                    if ((tile_dx * tile_dx) + (tile_dy * tile_dy)) <= (8*8) {
                        ghost_actor.target_tile_index = GHOST_SCATTER_TARGET_TILE_INDEX[.Clyde]
                    } else {
                        ghost_actor.target_tile_index = game.player.tile_index
                    }
                }
            }
            target_logic[ghost_index](ghost_actor)
        }
    }
}

draw_ghosts :: proc() {
	rg_texture(game.ghost_spritesheet)
	flash_state := util.time_sin(freq=2.0) >= 0.5
    if game.debug_mode != .Grid {
        for ghost_index in Ghost_Type {
	        sprite_data: Tile_Sprite
            ghost_actor := &game.ghosts[ghost_index]
            draw_pos := cast(vec2)ghost_actor.position - {PLAYER_SIZE, PLAYER_SIZE}/2
            switch game.ghosts[ghost_index].mode {
            case .Eaten:
            	if eaten_ghost, ok := game.eaten_ghost.?; ok {
             		if eaten_ghost == ghost_index do continue
	            }
                if ghost_actor.direction == .Left || ghost_actor.direction == .Right {
                    rg_blit(
                        draw_pos,
                        Rect{8*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
                        {ghost_actor.direction == .Left, false}
                    )
                } else if ghost_actor.direction == .Up {
                    rg_blit(draw_pos, Rect{9*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE})

                } else if ghost_actor.direction == .Down {
                    rg_blit(draw_pos, Rect{10*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE})
                }
            case .Frightened:
         		// TODO: only flash when frightened time is reaches near limit
         		if flash_state {
		       		rg_palette(1, GHOST_FRIGHTENED_COLOR)
					rg_palette(2, {238, 186, 161, 255})
           		} else {
		            rg_palette(1, color_white_4b)
					rg_palette(2, color_red_4b)
             	}
	        	sprite_data = Tile_Sprite{
                    rect={cast(i32)game.ghost_anim.frame_index*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE}
                }
                rg_blit(draw_pos, sprite_data.rect, sprite_data.flip)
            case .None:
                rg_palette(1, GHOST_COLORS[ghost_index])
	        	sprite_data = GHOST_SPRITES[ghost_actor.direction][game.ghost_anim.frame_index]
                rg_blit(draw_pos, sprite_data.rect, sprite_data.flip)
            }
        }
    } else {
        for ghost_index in Ghost_Type {
            ghost_color := GHOST_COLORS[ghost_index]
            ghost_actor := &game.ghosts[ghost_index]
            col := cast(i32)(cast(f32)ghost_actor.position.x / (f32)(CELL_SIZE))
            row := cast(i32)(cast(f32)ghost_actor.position.y / (f32)(CELL_SIZE))
            rg_fill_rect(
                Rect{
                    x=col*CELL_SIZE,
                    y=row*CELL_SIZE,
                    w=CELL_SIZE,
                    h=CELL_SIZE,
                },
                ghost_color if flash_state else color_grey_4b,
            )
            // draw ghost center point
            rg_fill_rect(Rect{
                cast(i32)ghost_actor.position.x,
                cast(i32)ghost_actor.position.y,
                1,
                1
            }, inv_color(ghost_color))
        }
    }
    // Draw ghost's targets
    if game.debug_mode == .Ghost_Target {
	    rg_texture(game.tile_spritesheet)
		fake_ghosts := game.ghosts
	    for ghost_index in Ghost_Type {
			previous_tile_indices: [dynamic; 64]i32
		   	rg_palette(1, GHOST_COLORS[ghost_index])
		    target_tile_pos := get_position_from_tile_index(game.ghosts[ghost_index].target_tile_index)
		    rg_blit(
				target_tile_pos + slight_offset[ghost_index],
			 	Rect{14*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE}
			)
			// FIXME: Draw path
			count := 0
			for ; ; count += 1 {
				if fake_ghosts[ghost_index].tile_index == fake_ghosts[ghost_index].target_tile_index {
					break
				}
				if game.marker_map[fake_ghosts[ghost_index].tile_index] == .Slow_Zone {
					log.debug("BROKE")
					break
				}
				next_tile_index, unstuck := ghost_decide_next_move(&fake_ghosts[ghost_index], ghost_index)
				if !unstuck {
					for tile_index, i in previous_tile_indices  {
						log.debug("INKY STUCK! PATH:")
						tile_coord := get_tile_coord_from_tile_index(tile_index)
						log.debugf("%v: %v", i, tile_coord)
						panic("DONE")
					}
				}
				fake_ghosts[ghost_index].tile_index = next_tile_index
				pos := get_position_from_tile_index(next_tile_index)
				rg_blit(pos + slight_offset[ghost_index] * 2, Rect{15*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE})
				if append(&previous_tile_indices, next_tile_index) == 0 {
					break
				}
				if slice.contains(previous_tile_indices[:], next_tile_index) {
					// log.infof("ALREADY WALKED HERE; len = %v", len(previous_tile_indices[:]))
					// break
				}
			}
			// log.debugf("%v: %v", ghost_index, count)
	    }
    }
}
