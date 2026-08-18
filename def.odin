package main

// TODO: Define big array for all sprites in game

Game_Phase :: enum {
    Ready,
    Play,
    Death,
    Game_Over,
    Complete,
}

Freeze_Type :: enum {
    None,
    Cold_Start_Ready,
    Eat_Ghost,
    Clear_Maze1,
    // Flashes maze
    Clear_Maze2,
    Death1,
    // Plays death animation
    Death2,
    Game_Over,
    Ready,
} 

DEFAULT_DURATION_TICKS :: SIM_UPDATE_HZ

// if (end_tick - now_ticks) > this, don't draw stuff
READY_BLANK_TICK_DIFF_MIN :: SIM_UPDATE_HZ-10

Debug_Mode :: enum {
	None,
	Ghost_Target,
	Grid,
	Editor,
}

Actor :: struct {
	position: vec2f,
	direction: Direction,
	tile_coord, reset_tile_coord: Tile_Coord,
}

Player :: struct {
   	using actor: Actor,
   	score, num_lives: i32,
}

CHAR_TILE_MAP := "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
CHAR_MARKER_MAP := ".!@#$%^&*()"

Tile_Coord :: distinct [2]i32

// TODO: Maybe rename this Wall_Tile_Type
Tile_Type :: enum u8 {
    None,
    Dot,
    Pellet,
    Wall_Left,
    Wall_Right,
    Wall_Top,
    Wall_Bottom,
    Wall_Top_Left,
    Wall_Top_Right,
    Wall_Bottom_Left,
    Wall_Bottom_Right,
    Inner_Wall_Top_Left,
    Inner_Wall_Top_Right,
    Inner_Wall_Bottom_Left,
    Inner_Wall_Bottom_Right, Double_Wall_Top,
    Double_Wall_Bottom,
    Double_Wall_Left,
    Double_Wall_Right,
    Double_Wall_Sharp_Top_Left,
    Double_Wall_Sharp_Top_Right,
    Double_Wall_Sharp_Bottom_Left,
    Double_Wall_Sharp_Bottom_Right,
    Double_Wall_Top_Left,
    Double_Wall_Top_Right,
    Double_Wall_Bottom_Left,
    Double_Wall_Bottom_Right,
    Double_Inner_Wall_Top_Left,
    Double_Inner_Wall_Top_Right,
    Double_Inner_Wall_Bottom_Left,
    Double_Inner_Wall_Bottom_Right,
    Ghost_Pass,
    Unused,
}

Marker_Tile_Type :: enum u8 {
	None,
	Player_Start,
	Blinky_Start,
	Pinky_Start,
	Inky_Start,
	Clyde_Start,
	Ghost_Decision,
	Slow_Zone,
	No_Up_Zone,
}

Direction :: enum u8 {
    None,
    Up,
    Left,
    Down,
    Right,
}

OPPOSITE_DIRECTION := [Direction]Direction {
	.None = .None,
	.Up = .Down,
	.Down = .Up,
	.Left = .Right,
	.Right = .Left,
}

PACMAN_RIGHT_FRAMES := [?]i32 {0, 2, 4}
PACMAN_DOWN_FRAMES := [?]i32{1, 3, 4}
PACMAN_DEATH_FRAMES := [?]i32{0, 5, 6, 7, 8, 9, 10, 11, 12, 13}


Ghost_Type :: enum {
	Blinky,
	Pinky,
	Inky,
	Clyde,
}

GHOST_FRIGHTENED_COLOR :: Color4b{0, 0, 0xff, 0xff}

GHOST_COLORS := [Ghost_Type]Color4b {
	.Blinky = {241, 10, 0, 255},
	.Pinky = {249, 184, 222, 255},
	.Inky = {93, 255, 222, 255},
	.Clyde = {247, 184, 63, 255},
}

Ghost_Global_Mode :: enum {
	Scatter,
	Chase,
}

Ghost_Unique_Mode :: enum {
	None,
	Frightened,
	Eaten,
}

Ghost_Actor :: struct {
	using actor: Actor,
	mode: Ghost_Unique_Mode,
	next_tile_coord, target_tile_coord: Tile_Coord,
    // Set when ghost still in ghost house after being eaten
    reviving: bool,
}

GHOST_FRIGHTENED_TICK_DIFF :: 2*SIM_UPDATE_HZ

GHOST_SCATTER_TARGET_TILE_COORD := [Ghost_Type]Tile_Coord {
	.Blinky = {COLS-3, 0},
	.Pinky = {2, 0},
	.Inky = {COLS-1, ROWS-1},
	.Clyde = {0, ROWS-1},
}

PASSABLE_TILES :: bit_set[Tile_Type] {
	.Dot,
	.Pellet,
	.None,
	.Unused,
}

GHOST_PASSABLE_TILES :: bit_set[Tile_Type] {
    .Dot,
    .Pellet,
    .None,
    .Unused,
    .Ghost_Pass,
}

DIRECTION_VECTORS := [Direction]vec2f {
    .None= {},
    .Up = {0, -1},
    .Down = {0, 1},
    .Left = {-1, 0},
    .Right = {1, 0},
}

GHOST_FRIGHTENED_SPEED :: 0.3
GHOST_EATEN_SPEED :: 1.7

Sprite_Size :: enum {
    Big,
    Small,
}

Sprite :: struct {
    src_offset: vec2,
    flip: [2]bool,
}


GHOST_SPRITES := [Direction][2]Sprite {
	.None={},
	.Left = {
		Sprite {
			src_offset={2*PLAYER_SIZE, 16},
			flip={true, false},
		},
		Sprite {
			src_offset={3*PLAYER_SIZE, 16},
			flip={true, false},
		},
	},
	.Right = {
		Sprite {
			src_offset={2*PLAYER_SIZE, 16},
			flip={false, false},
		},
		Sprite {
			src_offset={3*PLAYER_SIZE, 16},
			flip={false, false},
		},
	},
	.Up = {
		Sprite {
			src_offset={4*PLAYER_SIZE, 16},
			flip={false, false},
		},
		Sprite {
			src_offset={5*PLAYER_SIZE, 16},
			flip={false, false},
		},
	},
	.Down = {
		Sprite {
			src_offset={6*PLAYER_SIZE, 16},
			flip={false, false},
		},
		Sprite {
			src_offset={7*PLAYER_SIZE, 16},
			flip={false, false},
		},
	},
}

TILE_SPRITES :=  [Tile_Type]Sprite {
    .None={},
    .Unused={
    	src_offset={11*CELL_SIZE, 32},
    },
    .Dot={
        src_offset={9*CELL_SIZE, 32},
    },
    .Pellet={
        src_offset={10*CELL_SIZE, 32},
    },
    .Wall_Left={
        src_offset={0*CELL_SIZE, 32},
        flip={true, false},
    },
    .Wall_Right={
        src_offset={0*CELL_SIZE, 32},
    },
    .Wall_Top={
        src_offset={1*CELL_SIZE, 32},
        flip={false, true},
    },
    .Wall_Bottom={
        src_offset={1*CELL_SIZE, 32},
    },
    .Wall_Bottom_Right={
        src_offset={2*CELL_SIZE, 32},
    },
    .Wall_Bottom_Left={
        src_offset={2*CELL_SIZE, 32},
        flip={true, false},
    },
    .Wall_Top_Left={
        src_offset={2*CELL_SIZE, 32},
        flip={true, true},
    },
    .Wall_Top_Right={
        src_offset={2*CELL_SIZE, 32},
        flip={false, true},
    },
    .Inner_Wall_Bottom_Right={
        src_offset={13*CELL_SIZE, 32},
    },
    .Inner_Wall_Bottom_Left={
        src_offset={13*CELL_SIZE, 32},
        flip={true, false},
    },
    .Inner_Wall_Top_Left={
        src_offset={13*CELL_SIZE, 32},
        flip={true, true},
    },
    .Inner_Wall_Top_Right={
        src_offset={13*CELL_SIZE, 32},
        flip={false, true},
    },
    .Double_Wall_Bottom={
        src_offset={4*CELL_SIZE, 32},
        flip={false, false},
    },
    .Double_Wall_Top={
        src_offset={4*CELL_SIZE, 32},
        flip={false, true},
    },
    .Double_Wall_Left={
        src_offset={5*CELL_SIZE, 32},
        flip={true, false},
    },
    .Double_Wall_Right={
        src_offset={5*CELL_SIZE, 32},
        flip={false, false},
    },
    .Double_Wall_Bottom_Right={
        src_offset={6*CELL_SIZE, 32},
    },
    .Double_Wall_Bottom_Left={
        src_offset={6*CELL_SIZE, 32},
        flip={true, false},
    },
    .Double_Wall_Top_Left={
        src_offset={6*CELL_SIZE, 32},
        flip={true, true},
    },
    .Double_Wall_Top_Right={
        src_offset={6*CELL_SIZE, 32},
        flip={false, true},
    },
    .Double_Wall_Sharp_Bottom_Right={
        src_offset={7*CELL_SIZE, 32},
    },
    .Double_Wall_Sharp_Bottom_Left={
        src_offset={7*CELL_SIZE, 32},
        flip={true, false},
    },
    .Double_Wall_Sharp_Top_Left={
        src_offset={7*CELL_SIZE, 32},
        flip={true, true},
    },
    .Double_Wall_Sharp_Top_Right={
        src_offset={7*CELL_SIZE, 32},
        flip={false, true},
    },
    .Double_Inner_Wall_Top_Left={
    	src_offset={8*CELL_SIZE, 32},
     	flip={true, true},
    },
    .Double_Inner_Wall_Top_Right={
    	src_offset={8*CELL_SIZE, 32},
     	flip={false, true},
    },
    .Double_Inner_Wall_Bottom_Left={
    	src_offset={8*CELL_SIZE, 32},
     	flip={true, false},
    },
    .Double_Inner_Wall_Bottom_Right={
    	src_offset={8*CELL_SIZE, 32},
     	flip={false, false},
    },
    .Ghost_Pass={
        src_offset={3*CELL_SIZE, 32},
        flip={false, false},
    },
}
