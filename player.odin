package main

import "odinlib:util"

update_player :: proc() {
	// TODO:
	SPEED :: 1.5
	game.player.tile_index = get_tile_index_from_position(cast(vec2)game.player.position)
    tile_pos := get_position_from_tile_index(game.player.tile_index)
    current_tile_center := tile_pos + (CELL_SIZE/2)
    next_tile, ok := get_adjacent_tile_type(game.player.tile_index, game.player.direction)
    next_target_tile, target_ok := get_adjacent_tile_type(game.player.tile_index, game.player_target_direction)
    assert(!(game.player_target_direction == .Down && !target_ok))
    if game.player_target_direction != nil {
        if next_target_tile in PASSABLE_TILES {
            game.player.direction = game.player_target_direction
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
    game.player.position += SPEED * DIRECTION_VECTORS[game.player.direction]
    if next_tile not_in PASSABLE_TILES {
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
    	anim_update(&game.anim, game.last_frame_tick)
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
    // Eat dot
    if game.tile_map[game.player.tile_index] == .Dot {
        game.tile_map[game.player.tile_index] = .None
        game.player.score += 10
    } else if game.tile_map[game.player.tile_index] == .Pellet {
        frighten_all(.Frightened)
        game.tile_map[game.player.tile_index] = .None
        game.player.score += 50
    }
}

draw_player :: proc() {
	player_frame: i32
    if game.player.direction == .Up || game.player.direction == .Down {
        player_frame = PACMAN_DOWN_FRAMES[game.anim.frame_index]
    } else {
        player_frame = PACMAN_RIGHT_FRAMES[game.anim.frame_index]
    }
	if game.debug_mode == .Grid {
        player_color := Color4b{0xff, 0xff, 0, 0xff}
  		col := (i32)(cast(f32)game.player.position.x / cast(f32)CELL_SIZE)
  		row := (i32)(cast(f32)game.player.position.y / cast(f32)CELL_SIZE)
    	rg_fill_rect(
     		Rect{
	     		x=col*CELL_SIZE,
		       	y=row*CELL_SIZE,
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
	    rg_texture(game.player_spritesheet)
	    rg_blit(
            cast(vec2)game.player.position - PLAYER_DIMS/2,
	    	Rect{
		      	player_frame * PLAYER_SIZE,
		       	0,
	        	PLAYER_SIZE,
	         	PLAYER_SIZE
	     	},
			{game.player.direction == .Left, game.player.direction == .Up},
	 	)
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
set_direction_from_input :: proc "contextless" () {
	game.player_target_direction = nil
	switch {
	case .LEFT in game.input_state.gamepad.hat:
		game.player_target_direction = .Left
	case .RIGHT in game.input_state.gamepad.hat:
		game.player_target_direction = .Right
	case .UP in game.input_state.gamepad.hat:
		game.player_target_direction = .Up
	case .DOWN in game.input_state.gamepad.hat:
		game.player_target_direction = .Down
	}
	// Read thumbstick input if dpad is not pressed
	if game.player_target_direction == nil {
		// TODO:
		switch {
		case game.input_state.gamepad.axes[.LEFT_X] < -THUMBSTICK_THRESHOLD:
			game.player_target_direction = .Left
		case game.input_state.gamepad.axes[.LEFT_X] > THUMBSTICK_THRESHOLD:
			game.player_target_direction = .Right
		case game.input_state.gamepad.axes[.LEFT_Y] < -THUMBSTICK_THRESHOLD:
			game.player_target_direction = .Up
		case game.input_state.gamepad.axes[.LEFT_Y] > THUMBSTICK_THRESHOLD:
			game.player_target_direction = .Down
		}
	}
	// Read keyboard input if not input from gamepad
	if game.player_target_direction == nil {
		switch {
		case util.bit_test(game.input_state.keyboard[:], util.KEY_LEFT):
			game.player_target_direction = .Left
		case util.bit_test(game.input_state.keyboard[:], util.KEY_RIGHT):
			game.player_target_direction = .Right
		case util.bit_test(game.input_state.keyboard[:], util.KEY_UP):
			game.player_target_direction = .Up
		case util.bit_test(game.input_state.keyboard[:], util.KEY_DOWN):
			game.player_target_direction = .Down
		}
	}
	if game.player_target_direction == nil {
		game.player_target_direction = game.player.direction
	}
}
