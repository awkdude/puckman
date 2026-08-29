package util

Window_ID :: uintptr

Renderer_Backend :: enum i32 {
    Software,
    Opengl,
}

Window_Event :: struct {
    type: Window_Event_Type,
    source_window: Window_ID,
    using data: struct #raw_union {
        key: struct {
            keycode: u32,
            pressed, repeated: bool,
        } `raw_union_tag:"type=.Key"`,
        char_codepoint: rune  `raw_union_tag:"type=.Char_Input"`,
        mouse_button: struct {
            button: Mouse_Button,
            pressed: bool,
            position: vec2,
        }  `raw_union_tag:"type=.Mouse_Button"`,
        vec2: vec2,
        files: []string `raw_union_tag:"type=.Drop"`,
    },
}

Window_Event_Type :: enum {
    Key,
    Char_Input,
    // Window client area dimensions
    Window_Resize,
    Mouse_Button,
    Mouse_Move,
    Mouse_Wheel,
    Need_Repaint,
    Gain_Focus,
    Lose_Focus,
    Window_Close,
    Drop,
}

Mouse_Button :: enum {
    Left,
    Middle,
    Right,
    X1,
    X2,
}

Mouse_Cursor_Type :: enum {
    Normal,
    Wait,
    IBeam,
    Hand,
}

Platform_Command :: struct {
    type: enum {
        Rename_Window,
        Change_Mouse_Cursor,
        Resize_Window,
        Set_Window_Min_Size,
        Set_Window_Max_Size,
        Change_Window_Icon,
        Quit,
    },
    window: Window_ID,
    using data: struct #raw_union {
        size: Maybe(vec2),
        cursor_type: Mouse_Cursor_Type,
        title, path: string,
    },
}
