package main

Debug_Mode :: enum {
	None,
	Ghost_Target,
	Grid,
	Editor,
}

Actor :: struct {
	position: vec2f,
	direction: Direction,
	tile_coord: Tile_Coord,
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
    Inner_Wall_Bottom_Right,
    Double_Wall_Top,
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
}

GHOST_SCATTER_TARGET_TILE_COORD := [Ghost_Type]Tile_Coord {
	.Blinky = {COLS-3, 0},
	.Pinky = {2, 0},
	.Inky = {COLS-1, ROWS-1},
	.Clyde = {0, ROWS-1},
}

PASSABLE_TILES :: bit_set[Tile_Type] {
	.Dot,
	.Pellet,
	// .Ghost_Pass, // TODO: remove this
	.None,
	// .Unused,
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


GHOST_SPRITES := [Direction][2]Tile_Sprite {
	.None={},
	.Left = {
		Tile_Sprite {
			rect={2*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
			flip={true, false},
		},
		Tile_Sprite {
			rect={3*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
			flip={true, false},
		},
	},
	.Right = {
		Tile_Sprite {
			rect={2*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
			flip={false, false},
		},
		Tile_Sprite {
			rect={3*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
			flip={false, false},
		},
	},
	.Up = {
		Tile_Sprite {
			rect={4*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
			flip={false, false},
		},
		Tile_Sprite {
			rect={5*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
			flip={false, false},
		},
	},
	.Down = {
		Tile_Sprite {
			rect={6*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
			flip={false, false},
		},
		Tile_Sprite {
			rect={7*PLAYER_SIZE, 0, PLAYER_SIZE, PLAYER_SIZE},
			flip={false, false},
		},
	},
}


TILE_SPRITES :=  [Tile_Type]Tile_Sprite {
    .None={},
    .Unused={
    	rect=Rect{11*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Dot={
        rect=Rect{9*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Pellet={
        rect=Rect{10*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Wall_Left={
        rect=Rect{0*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, false},
    },
    .Wall_Right={
        rect=Rect{0*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Wall_Top={
        rect=Rect{1*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, true},
    },
    .Wall_Bottom={
        rect=Rect{1*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Wall_Bottom_Right={
        rect=Rect{2*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Wall_Bottom_Left={
        rect=Rect{2*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, false},
    },
    .Wall_Top_Left={
        rect=Rect{2*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, true},
    },
    .Wall_Top_Right={
        rect=Rect{2*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, true},
    },
    .Inner_Wall_Bottom_Right={
        rect=Rect{13*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Inner_Wall_Bottom_Left={
        rect=Rect{13*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, false},
    },
    .Inner_Wall_Top_Left={
        rect=Rect{13*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, true},
    },
    .Inner_Wall_Top_Right={
        rect=Rect{13*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, true},
    },
    .Double_Wall_Bottom={
        rect=Rect{4*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, false},
    },
    .Double_Wall_Top={
        rect=Rect{4*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, true},
    },
    .Double_Wall_Left={
        rect=Rect{5*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, false},
    },
    .Double_Wall_Right={
        rect=Rect{5*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, false},
    },
    .Double_Wall_Bottom_Right={
        rect=Rect{6*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Double_Wall_Bottom_Left={
        rect=Rect{6*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, false},
    },
    .Double_Wall_Top_Left={
        rect=Rect{6*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, true},
    },
    .Double_Wall_Top_Right={
        rect=Rect{6*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, true},
    },
    .Double_Wall_Sharp_Bottom_Right={
        rect=Rect{7*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
    .Double_Wall_Sharp_Bottom_Left={
        rect=Rect{7*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, false},
    },
    .Double_Wall_Sharp_Top_Left={
        rect=Rect{7*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={true, true},
    },
    .Double_Wall_Sharp_Top_Right={
        rect=Rect{7*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, true},
    },
    .Double_Inner_Wall_Top_Left={
    	rect=Rect{8*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
     	flip={true, true},
    },
    .Double_Inner_Wall_Top_Right={
    	rect=Rect{8*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
     	flip={false, true},
    },
    .Double_Inner_Wall_Bottom_Left={
    	rect=Rect{8*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
     	flip={true, false},
    },
    .Double_Inner_Wall_Bottom_Right={
    	rect=Rect{8*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
     	flip={false, false},
    },
    .Ghost_Pass={
        rect=Rect{3*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
        flip={false, false},
    },
}
