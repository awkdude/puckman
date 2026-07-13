package main

Debug_Mode :: enum {
	None,
	Grid,
	Editor,
}

CHAR_TILE_MAP := "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
CHAR_MARKER_MAP := "!@#$%^&*()"

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
    Slow_Zone, // TODO: remove this
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
}

Direction :: enum {
    None,
    Up,
    Down,
    Left,
    Right,
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

Ghost_State :: enum {
	Scatter,
	Chase,
	Frightened,
	Eaten,
}

Ghost_Actor :: struct {
	position: vec2f,
	direction: Direction,
	state: Ghost_State,
	target_tile_index: i32,
}


PASSABLE_TILES :: bit_set[Tile_Type] {
	.Dot,
	.Pellet,
	.None,
	.Unused,
	.Slow_Zone,
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
    .Slow_Zone={
    	rect=Rect{12*CELL_SIZE, 0, CELL_SIZE, CELL_SIZE},
    },
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
