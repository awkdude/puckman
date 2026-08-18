package main

import "core:math"
import "core:math/bits"
import "core:slice"
import "core:log"
import "core:fmt"
import "odinlib:util"

slight_offset := [Ghost_Type]vec2 {
	.Blinky = {0, -1},
	.Pinky = {1, 0},
	.Inky = {0, 1},
	.Clyde = {-1, 0},
}

// Make all ghosts frightened
frighten_all :: proc() {
	for &ghost in game.ghosts {
		if ghost.mode == .None {
			ghost.mode = .Frightened
            ghost.direction = OPPOSITE_DIRECTION[ghost.direction]
		}
	}
	game.frightened_sim_ticks_remaining = 6*SIM_UPDATE_HZ
	game.ghost_eat_count = 0
}

// Make all ghosts unfrightened
unfrighten_all :: proc() {
	for &ghost in game.ghosts {
		if ghost.mode == .Frightened {
			ghost.mode = .None
		}
	}
}

update_ghosts :: proc() {
    GHOST_SPEED :: 0.57
    anim_update(&game.ghost_anim, game.last_frame_cpu_tick)
    do_mode_switch := false && game.sim_ticks >= game.ghost_mode_switch_end_sim_tick
    if do_mode_switch {
        if game.ghost_global_mode == .Chase {
            game.ghost_global_mode = .Scatter
        } else {
            game.ghost_global_mode = .Chase
        }
        game.ghost_mode_switch_end_sim_tick = game.sim_ticks + 5*SIM_UPDATE_HZ
    }
	for ghost_index in Ghost_Type {
        ghost_actor := &game.ghosts[ghost_index]
        if game.freeze_type == .Eat_Ghost && (game.eaten_ghost == ghost_index || ghost_actor.mode != .Eaten) 
        {
            continue
        }
        ghost_tile_index := get_tile_index_from_tile_coord(ghost_actor.tile_coord)
        if do_mode_switch && ghost_actor.mode == .None && game.marker_map[ghost_tile_index] != .Slow_Zone 
        {
            ghost_actor.direction = OPPOSITE_DIRECTION[ghost_actor.direction]
        }
        log.debugf("%v: %v", ghost_index, ghost_actor.position)
        check_warp_actor_oob(ghost_actor)
        passable_tiles := get_ghost_passable_tiles(ghost_actor)
        current_tile_coord := get_tile_coord_from_position(cast(vec2)ghost_actor.position)
        if ghost_actor.mode == .Eaten {
            if current_tile_coord == game.ghost_revive_tile_coord {
                ghost_actor.mode = .None
                ghost_actor.direction = .Up
                ghost_actor.reviving = true
                ghost_actor.target_tile_coord = game.ghost_pass_tile_coord + {0, -1}
            }
        } else if ghost_actor.reviving {
            if current_tile_coord == ghost_actor.target_tile_coord {
                ghost_actor.reviving = false
            }
        }
        next_tile, next_ok := get_adjacent_tile(ghost_actor.tile_coord, ghost_actor.direction)
        ghost_speed: f32 = GHOST_SPEED 
        if ghost_actor.mode == .Eaten {
            ghost_speed = GHOST_EATEN_SPEED
        } else if ghost_actor.mode == .Frightened || game.marker_map[ghost_tile_index] == .Slow_Zone || ghost_actor.reviving  {
            ghost_speed = GHOST_FRIGHTENED_SPEED
        }
        if current_tile_coord == ghost_actor.next_tile_coord {
           	tile_center_pos := get_position_from_tile_coord(ghost_actor.next_tile_coord) + CELL_DIMS/2
           	diff := ghost_actor.position - cast(vec2f)tile_center_pos
            cond: bool
            cond = math.abs(diff.x) < ghost_speed && math.abs(diff.y) < ghost_speed
            if ghost_speed > 2.6 {
            	// ghost_actor.position = cast(vec2f)tile_center_pos
	            // cond = true
            }
            if cond {
                ghost_actor.next_tile_coord, _ = ghost_decide_next_move(ghost_actor, ghost_index)
            }
        } else if next_ok && next_tile^ not_in passable_tiles {
            ghost_actor.next_tile_coord, _ = ghost_decide_next_move(ghost_actor, ghost_index)
        }
        ghost_actor.tile_coord = current_tile_coord
        next_tile, next_ok = get_adjacent_tile(ghost_actor.tile_coord, ghost_actor.direction)

        tile_pos := get_position_from_tile_coord(ghost_actor.tile_coord)
        current_tile_center := tile_pos + CELL_DIMS/2
        ghost_actor.position += ghost_speed * DIRECTION_VECTORS[ghost_actor.direction]
        if next_ok && next_tile^ not_in passable_tiles {
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
ghost_decide_next_move :: proc(ghost: ^Ghost_Actor, ghost_index: Ghost_Type) -> (Tile_Coord, bool) {
	min_dist: i32 = bits.I32_MAX
	min_dir := Direction.None
	min_adj_tile_coord := ghost.tile_coord
	// // target_tile_coord := get_tile_coord_from_tile_coord(ghost.target_tile_coord)
	dirs_to_check := [?]Direction {.Up, .Left, .Down, .Right}
	for direction in dirs_to_check {
		if direction == OPPOSITE_DIRECTION[ghost.direction] do continue
		adj_tile_coord, ok := get_adjacent_tile_coord(ghost.tile_coord, direction)
		if !ok do continue
        adj_tile_index := get_tile_index_from_tile_coord(adj_tile_coord)
        current_tile_index := get_tile_index_from_tile_coord(ghost.tile_coord)
        // Skip going up if we're not frightened nor eaten, and we're in a no-up zone
        if ghost.mode == .None && game.marker_map[current_tile_index] == .No_Up_Zone && direction == .Up {
            continue
        }
        passable_tiles := get_ghost_passable_tiles(ghost) 
		if game.tile_map[adj_tile_index] not_in passable_tiles do continue
		dist_vec := ghost.target_tile_coord - adj_tile_coord
		dist := (dist_vec.x * dist_vec.x) + (dist_vec.y * dist_vec.y)
		if dist < min_dist {
			min_dir = direction
			min_dist = dist
			min_adj_tile_coord = adj_tile_coord
		}
	}
	if min_dir != .None {
		ghost.direction = min_dir
		tile_pos := get_position_from_tile_coord(ghost.tile_coord)
		current_tile_center := tile_pos + CELL_DIMS/2
		#partial switch ghost.direction {
        case .Up, .Down:
            // Position player x value to tile's center x if up or down
            ghost.position.x = cast(f32)current_tile_center.x
        case .Left, .Right:
            // Position player y value to tile's center y if left or right
            ghost.position.y = cast(f32)current_tile_center.y
        }

	} else {
		return {}, false
	}
	log.assertf(min_adj_tile_coord != ghost.tile_coord, "%v == %v", min_adj_tile_coord, ghost.tile_coord)
	return min_adj_tile_coord, true
}

calculate_ghost_targets :: proc() {
	tile_coord_ahead_of_player :: proc "contextless" (
        player_tile_coord: Tile_Coord,
        distance: i32) -> Tile_Coord 
    {
		target_tile_coord: Tile_Coord
		ok: bool
		switch game.player.direction {
		case .None:
		case .Left:
            target_tile_coord = player_tile_coord + {-distance, 0}
			if target_tile_coord.x < 0 {
				target_tile_coord.x = 0
			}
	    case .Right:
            target_tile_coord = player_tile_coord + {distance, 0}
            if target_tile_coord.x > COLS-1 {
				target_tile_coord.x = COLS-1
			}
	    case .Up:
			target_tile_coord = player_tile_coord + {0, -distance}
			if target_tile_coord.y < 0 {
				target_tile_coord.y = 0
			}
	    case .Down:
			target_tile_coord = player_tile_coord + {0, distance}
			if target_tile_coord.y > ROWS-1 {
				target_tile_coord.y = ROWS-1
			}
	    }
		return target_tile_coord
	}

    for ghost_index in Ghost_Type {
        ghost_actor := &game.ghosts[ghost_index]
        // Don't update target tile if reviving
        if ghost_actor.reviving do break
        if ghost_actor.mode == .Eaten {
            ghost_actor.target_tile_coord = game.ghost_revive_tile_coord
        } else if game.ghost_global_mode == .Scatter || ghost_actor.mode == .Frightened {
			ghost_actor.target_tile_coord = GHOST_SCATTER_TARGET_TILE_COORD[ghost_index]
        } else if game.ghost_global_mode == .Chase {
            switch ghost_index {
            case .Blinky:
                ghost_actor.target_tile_coord = game.player.tile_coord
            case .Pinky:
                ghost_actor.target_tile_coord = tile_coord_ahead_of_player(game.player.tile_coord, 4)
            case .Inky:
                ahead_tile_coord := tile_coord_ahead_of_player(game.player.tile_coord, 2)
                blinky_tile_coord := game.ghosts[.Blinky].tile_coord
                dist_vec := (ahead_tile_coord - blinky_tile_coord) * 2
                final_tile_coord := blinky_tile_coord + dist_vec
                final_tile_coord.x = math.clamp(final_tile_coord.x, 0, COLS-1)
                final_tile_coord.y = math.clamp(final_tile_coord.y, 0, ROWS-1)
                ghost_actor.target_tile_coord = final_tile_coord
            case .Clyde:
                tile_dp := game.player.tile_coord - ghost_actor.tile_coord
                if ((tile_dp.x * tile_dp.x) + (tile_dp.y * tile_dp.y)) <= (8*8) {
                    ghost_actor.target_tile_coord = GHOST_SCATTER_TARGET_TILE_COORD[.Clyde]
                } else {
                    ghost_actor.target_tile_coord = game.player.tile_coord
                }
            }
        }
    }
}

draw_ghosts :: proc() {
    flash_state := util.blink_state(game.sim_ticks, SIM_UPDATE_HZ/2) == 1 
    if game.debug_mode != .Grid {
        valid_freeze_types := bit_set[Freeze_Type]{
            .None,
            .Eat_Ghost,
            .Clear_Maze1,
            .Death1,
            // TODO: .Ready
        }
        if game.freeze_type not_in valid_freeze_types do return
        for ghost_index in Ghost_Type {
	        sprite_data: Sprite
            ghost_actor := &game.ghosts[ghost_index]
            draw_pos := cast(vec2)ghost_actor.position - PLAYER_DIMS/2
            switch game.ghosts[ghost_index].mode {
            case .Eaten:
                src_offset: vec2
                if game.freeze_type == .Eat_Ghost && game.eaten_ghost == ghost_index {
                    switch game.ghost_eat_count {
                    case 1:
                        src_offset = {176, 16}
                    case 2:
                        src_offset = {192, 16}
                    case 3:
                        src_offset = {208, 16}
                    case 4:
                        src_offset = {224, 16}
                    }
                    rg_palette(1, GHOST_COLORS[ghost_index])
                    blit_sprite(.Big, draw_pos, src_offset)
                } else {
                    flip: [2]bool
                    #partial switch ghost_actor.direction {
                    case .Left, .Right:
                        src_offset = {8*PLAYER_SIZE, 16}
                        flip = {ghost_actor.direction == .Left, false}
                    case .Up: 
                        src_offset = {9*PLAYER_SIZE, 16}
                    case .Down :
                        src_offset = {10*PLAYER_SIZE, 16}
                    }
                    blit_sprite(.Big, draw_pos, src_offset, flip)
                }
            case .Frightened:
         		// Only flash when frightened time is reaches near limit
                if game.frightened_sim_ticks_remaining <= GHOST_FRIGHTENED_TICK_DIFF && flash_state 
                {
		            rg_palette(1, color_white_4b)
					rg_palette(2, color_red_4b)
                } else {
		       		rg_palette(1, GHOST_FRIGHTENED_COLOR)
					rg_palette(2, {238, 186, 161, 255})
           		}
	        	sprite_data = Sprite{
                    src_offset={cast(i32)game.ghost_anim.frame_index*PLAYER_SIZE, 16}
                }
                blit_sprite(.Big, draw_pos, sprite_data.src_offset, sprite_data.flip)
            case .None:
                rg_palette(1, GHOST_COLORS[ghost_index])
	        	sprite_data = GHOST_SPRITES[ghost_actor.direction][game.ghost_anim.frame_index]
                blit_sprite(.Big, draw_pos, sprite_data.src_offset, sprite_data.flip)
            }
        }
    } else {
        for ghost_index in Ghost_Type {
            ghost_color := GHOST_COLORS[ghost_index]
            ghost_actor := &game.ghosts[ghost_index]
            color := ghost_color
            if ghost_actor.mode == .Frightened {
                color = ghost_color if flash_state else color_grey_4b
            }
            rg_fill_rect(
                Rect{
                    x=ghost_actor.tile_coord.x*CELL_SIZE,
                    y=ghost_actor.tile_coord.y*CELL_SIZE,
                    w=CELL_SIZE,
                    h=CELL_SIZE,
                },
                color
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
		fake_ghosts := game.ghosts
	    for ghost_index in Ghost_Type {
            fake_ghost := &fake_ghosts[ghost_index]
			previous_tile_coords: [dynamic; 64]Tile_Coord
		   	rg_palette(1, GHOST_COLORS[ghost_index])
		    target_tile_pos := get_position_from_tile_coord(
                game.ghosts[ghost_index].target_tile_coord
            )
            blit_sprite(
                .Small, 
                target_tile_pos + slight_offset[ghost_index],
                {14*CELL_SIZE, 32}
            )
			for fake_ghost.tile_coord != fake_ghost.target_tile_coord {
				// if game.marker_map[fake_ghosts[ghost_index].tile_coord] == .Slow_Zone {
				// 	log.debug("BROKE")
				// 	break
				// }
				next_tile_coord, unstuck := ghost_decide_next_move(
                    fake_ghost,
                    ghost_index
                )
				if !unstuck {
                    break
				}
				fake_ghost.tile_coord = next_tile_coord
				pos := get_position_from_tile_coord(next_tile_coord)
				// rg_blit(pos + slight_offset[ghost_index] * 2, Rect{15*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE})
				if fake_ghost.direction == .Left || fake_ghost.direction == .Right {
				    blit_sprite(
                        .Small,
						pos + slight_offset[ghost_index],
					 	{16*CELL_SIZE, 32},
						{fake_ghost.direction == .Left, false},
					)
				} else {
				    blit_sprite(
                        .Small,
						pos + slight_offset[ghost_index],
					 	{17*CELL_SIZE, 32},
						{false, fake_ghost.direction == .Up},
					)
				}
				if slice.contains(previous_tile_coords[:], next_tile_coord) do break
				if append(&previous_tile_coords, next_tile_coord) == 0 do break
			}
	    }
    }
}

get_ghost_passable_tiles :: proc "contextless" (ghost_actor: ^Ghost_Actor) -> bit_set[Tile_Type]{
    if ghost_actor.mode == .Eaten || ghost_actor.reviving {
        return GHOST_PASSABLE_TILES
    }
    return PASSABLE_TILES
}
