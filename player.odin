package main

import "odinlib:util"
import "core:log"
import "core:time"

update_player :: proc() {
	// TODO:
	SPEED :: 0.6
	game.player.tile_coord = get_tile_coord_from_position(cast(vec2)game.player.position)
	player_tile, tile_ok := get_adjacent_tile(game.player.tile_coord, .None)
    // Set if player eats dot or pellet. Just causes pacman to slow-down as he's chomping
    did_chomp := false
    if tile_ok {
        if player_tile^ == .Dot {
            player_tile^ = .None
            game.player.score += 10
            game.dots_remaining -= 1
            did_chomp = true
            if game.dots_remaining <= 0 {
                set_freeze_type(.Clear_Maze1, 3*SIM_UPDATE_HZ)
            }
        } else if player_tile^ == .Pellet {
            frighten_all()
            player_tile^ = .None
            game.player.score += 50
            did_chomp = true
            set_rumble(100*time.Millisecond, 0.6)
        }
    }
    player_target_direction := game.user_input_direction
    if player_target_direction == nil {
        player_target_direction = game.player.direction
    }
    check_warp_actor_oob(&game.player)
    tile_pos := get_position_from_tile_coord(game.player.tile_coord)
    current_tile_center := tile_pos + (CELL_DIMS/2)
    next_tile, next_ok := get_adjacent_tile(game.player.tile_coord, game.player.direction)
    next_target_tile, target_ok := get_adjacent_tile(game.player.tile_coord, player_target_direction)
    // assert(!(game.player_target_direction == .Down && !target_ok))
    if player_target_direction != nil && target_ok {
        if next_target_tile^ in PASSABLE_TILES {
            game.player.direction = player_target_direction
            #partial switch game.player.direction {
            case .Up, .Down:
                // Position player x value to tile's center x if up or down
                game.player.position.x = cast(f32)current_tile_center.x
            case .Left, .Right:
                // Position player y value to tile's center y if left or right
                game.player.position.y = cast(f32)current_tile_center.y
            }
        }
    }
    // Don't advance if ate dot
    if !did_chomp {
        game.player.position += SPEED * DIRECTION_VECTORS[game.player.direction]
    }
    // Clamp position if tile if front is non passable
    if next_ok && next_tile^ not_in PASSABLE_TILES {
        #partial switch game.player.direction {
        case .Left:
            game.player.position.x = max(cast(f32)current_tile_center.x, game.player.position.x)
        case .Right:
            game.player.position.x = min(cast(f32)current_tile_center.x, game.player.position.x)
        case .Up:
            game.player.position.y = max(cast(f32)current_tile_center.y, game.player.position.y)
        case .Down:
            game.player.position.y = min(cast(f32)current_tile_center.y, game.player.position.y)
        }
    } else {
    	anim_update(&game.anim, game.last_frame_cpu_tick)
    }
    player_is_horz := game.player.direction in bit_set[Direction]{.Left, .Right}
    player_is_vert := game.player.direction in bit_set[Direction]{.Up, .Down}
    if player_is_horz {
        game.player.position.y = (f32)(tile_pos.y + CELL_SIZE/2)
    } else if player_is_vert {
        game.player.position.x = (f32)(tile_pos.x + CELL_SIZE/2)
    }
    min_x := cast(f32)0
    min_y := cast(f32)CELL_SIZE*2
    max_x := (f32)(CELL_SIZE * (COLS + 1))
    max_y := (f32)(CELL_SIZE * (ROWS - 2))
    // if game.player.position.x < 0 {
    //     game.player.position.x = max_x
    // } else if game.player.position.x > max_x  {
    //     game.player.position.x = 0
    // }
    // if game.player.position.y < 0 {
    //     game.player.position.y = max_y
    // } else if game.player.position.y > max_y {
    //     game.player.position.y = 0
    // }
}

draw_player :: proc() {
    rg_texture(game.spritesheet)
	player_frame: i32
    flip: [2]bool
    if game.freeze_type != .Death2 {
        if game.player.direction == .Up || game.player.direction == .Down {
            player_frame = PACMAN_DOWN_FRAMES[game.anim.frame_index]
        } else {
            player_frame = PACMAN_RIGHT_FRAMES[game.anim.frame_index]
        }
        flip = {game.player.direction == .Left, game.player.direction == .Up}
    } else {
        player_frame = PACMAN_DEATH_FRAMES[game.death_anim.frame_index]
        anim_update(&game.death_anim, game.last_frame_cpu_tick)
    }
	if game.debug_mode == .Grid {
        player_color := Color4b{0xff, 0xff, 0, 0xff}
    	rg_fill_rect(
     		Rect{
	     		x=game.player.tile_coord.x*CELL_SIZE,
		       	y=game.player.tile_coord.y*CELL_SIZE,
	        	w=CELL_SIZE,
	        	h=CELL_SIZE,
       		},
         	player_color,
     	)
        // draw player's center point
        rg_fill_rect(Rect{
            cast(i32)game.player.position.x,
            cast(i32)game.player.position.y,
            1,
            1
        }, inv_color(player_color))
    } else {
        valid_freeze_types := bit_set[Freeze_Type]{.None, .Death1, .Death2, .Clear_Maze1}
        if game.freeze_type in valid_freeze_types {
            blit_sprite(
                .Big,
                cast(vec2)game.player.position - PLAYER_DIMS/2,
                vec2{ player_frame * PLAYER_SIZE, 0, },
                flip,
            )
        }
    }
    // p := cast(vec2)game.player.position - PLAYER_DIMS/2
    // rg_stroke_rect(
    // 	Rect {
    //  		p.x,
    //    		p.y,
    //      	PLAYER_SIZE,
    //      	PLAYER_SIZE,
    //  	},
    //  	color_red_4b,
    // )
    // Draw lives at bottom
    if game.debug_mode == .None {
	    for i in 0..<game.player.num_lives {
	    	// rg_blit({3*CELL_SIZE+i*PLAYER_SIZE, (ROWS-2)*CELL_SIZE}, {0, 0, PLAYER_SIZE, PLAYER_SIZE})
	    	blit_sprite(.Big, {3*CELL_SIZE+i*PLAYER_SIZE, (ROWS-2)*CELL_SIZE}, {0, 0})
	    }
    }
}

// Sets player's target direction from input.
// Gamepad input has priority over keyboard
update_user_input_direction :: proc "contextless" () {
	game.user_input_direction = nil
	switch {
	case .LEFT in game.input_state.gamepad.hat:
		game.user_input_direction = .Left
	case .RIGHT in game.input_state.gamepad.hat:
		game.user_input_direction = .Right
	case .UP in game.input_state.gamepad.hat:
		game.user_input_direction = .Up
	case .DOWN in game.input_state.gamepad.hat:
		game.user_input_direction = .Down
	}
	// Read thumbstick input if dpad is not pressed
	if game.user_input_direction == nil {
		switch {
        case .LEFT_X_LEFT in game.input_state.gamepad.buttons: 
			game.user_input_direction = .Left
        case .LEFT_X_RIGHT in game.input_state.gamepad.buttons: 
			game.user_input_direction = .Right
        case .LEFT_Y_UP in game.input_state.gamepad.buttons: 
			game.user_input_direction = .Up
        case .LEFT_Y_DOWN in game.input_state.gamepad.buttons: 
			game.user_input_direction = .Down
		}
	}
	// Read keyboard input if no input from gamepad
	if game.user_input_direction == nil {
		switch {
		case util.bit_test(game.input_state.keyboard[:], util.KEY_LEFT):
			game.user_input_direction = .Left
		case util.bit_test(game.input_state.keyboard[:], util.KEY_RIGHT):
			game.user_input_direction = .Right
		case util.bit_test(game.input_state.keyboard[:], util.KEY_UP):
			game.user_input_direction = .Up
		case util.bit_test(game.input_state.keyboard[:], util.KEY_DOWN):
			game.user_input_direction = .Down
		}
	}
}
