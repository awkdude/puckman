package util

Gamepad_Button :: enum i32 {
    SOUTH,
    EAST,
    WEST,
    NORTH,
    START,
    SELECT,
    GUIDE,
    BUMPER_LEFT,
    BUMPER_RIGHT,
    THUMB_LEFT,
    THUMB_RIGHT,
    // The rest are virtual buttons for axes
    // Can be set in bit set if they reach specified threshold
    LEFT_X_LEFT,
    LEFT_X_RIGHT,
    LEFT_Y_UP,
    LEFT_Y_DOWN,
    RIGHT_X_LEFT,
    RIGHT_X_RIGHT,
    RIGHT_Y_UP,
    RIGHT_Y_DOWN,
    TRIGGER_LEFT,
    TRIGGER_RIGHT,
}

Gamepad_Hat :: enum i32 {
    UP,
    RIGHT,
    DOWN,
    LEFT,
}

// NOTE: +Y means down, -Y means up
Gamepad_Axis :: enum i32 {
    LEFT_X,
    LEFT_Y,
    RIGHT_X,
    RIGHT_Y,
    TRIGGER_LEFT,
    TRIGGER_RIGHT,
}

Gamepad_State_Buttons :: bit_set[Gamepad_Button; u32]
Gamepad_State_Hats :: bit_set[Gamepad_Hat; u32]

Gamepad_State :: struct {
    buttons: Gamepad_State_Buttons,
    hat: Gamepad_State_Hats,
    axes: [Gamepad_Axis]f32,
}
