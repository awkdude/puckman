package platform

import "core:mem"
import "core:strings"
import "core:slice"

vec2  :: [2]i32
Rect  :: struct {
    x, y, w, h: i32,
}

Pixmap :: struct {
     pixels: [^]u8,
     w, h, pitch: i32,
     // NOTE: maybe add pixelformat
}

Window_Graphics :: enum i32 {
    Software,
    OpenGL,
}

Mouse_Button :: enum i32 {
    Left = 1,
    Middle = 2,
    Right = 4,
}

Window_Key_Event :: struct {
    keycode: u32,
    modifiers: i32,
    pressed, repeated: bool,
}

Window_Mouse_Button_Event :: struct {
    x, y: i32,
    button: Mouse_Button,
    pressed: bool,
}

Window_Mouse_Wheel_Event :: struct {
    x, y, dx, dy: i32,
} 

Window_Event_Type :: enum i32 {
    Key = 1,
    Mouse_Button,
    Mouse_Wheel,
    Mouse_Motion,
    Resize,
    Mouse_Enter,
    Mouse_Leave,
    Gain_Focus,
    Lose_Focus,
    Display_Change,
    Character,
    Close,
}


Window_Event :: struct {
    using _: struct #raw_union {
        key: Window_Key_Event,
        mouse_button: Window_Mouse_Button_Event,
        mouse_wheel: Window_Mouse_Wheel_Event,
        vec2: vec2,
        char_codepoint: u32,
    },
    type: Window_Event_Type,
}

Cursor_Type :: enum {
    Normal,
    Wait,
    IBeam,
    Hand,
}

SOUND_RES_SIGNED :: (1 << 7)

Sound_Resolution :: enum i32 {
    U8  = 8,
    S8  = SOUND_RES_SIGNED | 8,
    U16 = 16,
    S16 = SOUND_RES_SIGNED | 16,
}

Sound_Spec :: struct {
    num_channels, sample_rate: i32,
    bit_format: Sound_Resolution,
}

when ODIN_OS != .Windows {
    foreign import plat "../../platform/libplat.so"


    @(default_calling_convention="c")
    foreign plat {
        @(link_name="pipe_command")
        _pipe_command : proc(command_input, command_output_buf: cstring, 
            command_output_len: uint) -> i32

        // @(link_name="init_window")
        init_window : proc(title: cstring, width, height, window_graphics: i32) -> bool

        @(link_name="shutdown_window")
        shutdown_window: proc() 

        resize_window : proc( width, height: i32)  
        get_window_size : proc() -> vec2

        @(link_name="poll_window_events")
        _poll_window_events : proc(window_events: [^]Window_Event,
             max_num_events: u32) -> u32
        

        @(link_name="set_window_title")
        _set_window_title : proc(title: cstring)

        get_framebuffer: proc(pixels: ^rawptr, w, h: ^i32)
        show_framebuffer: proc()
        get_display_size : proc() -> vec2 
        get_display_dpi : proc() -> u32
        set_mouse_cursor_icon : proc( cursor: Cursor_Type)
        make_context_current : proc()
        get_proc_address : proc(name: cstring) -> rawptr
        swap_buffers : proc() 

        @(link_name="set_clipboard_text")
        _set_clipboard_text : proc(text: cstring)

        @(link_name="get_clipboard_text")
        _get_clipboard_text : proc(textbuf: [^]u8, bufsize: u32) -> u32

        // :sound
        init_sound : proc() -> bool
        open_sound_device_for_playback : proc(device_name: cstring) -> bool
        close_sound_device : proc()
        set_sound_spec_for_device : proc(spec: ^Sound_Spec) -> bool

        @(link_name="write_sound_to_device")
        _write_sound_to_device : proc(stream_buffer: [^]u8, bufsize: uint) -> uint
        get_sound_device_buffer_size : proc() -> uint
        shutdown_sound : proc()
    }

    write_sound_to_device :: proc(buf: []u8) -> uint {
        return _write_sound_to_device(raw_data(buf), len(buf))
    }

    // init_window :: proc(title: string, width, height: i32, graphics: Window_Graphics) -> bool {
    //     title_c, err := strings.clone_to_cstring(title)
    //     if err != .None do title_c = cstring("?")
    //     init_ok := _init_window(title_c, width, height, cast(i32)graphics)
    //     if err == .None do delete(title_c)
    //     return init_ok
    // }

    set_window_title :: proc(title: string) {
        title_c, err := strings.clone_to_cstring(title)
        if err != .None do title_c = cstring("?")
        _set_window_title(title_c)
        if err == .None do delete(title_c)
    }


    // FIXME: Perhaps return (i32, ok: bool)
    pipe_command :: proc (command_input: string, command_output_buf: []u8) -> i32 {
        command_input_c, err := strings.clone_to_cstring(command_input)
        if err != .None do return 1
        defer delete(command_input_c)
        return _pipe_command(command_input_c, 
            cstring(slice.as_ptr(command_output_buf)), len(command_output_buf))
    }

    poll_window_events :: proc (window_events: []Window_Event) -> u32 {
        return _poll_window_events(raw_data(window_events), u32(len(window_events)))
    }

    set_clipboard_text :: proc(textbuf: []u8) -> string {
        // TODO:
        return ""
    }

    get_clipboard_text :: proc(textbuf: []u8) -> string {
        length := _get_clipboard_text(slice.as_ptr(textbuf), cast(u32)len(textbuf))
        return transmute(string)textbuf[:length]
    }
} 
