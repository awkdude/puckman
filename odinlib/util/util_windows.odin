package util

// import "../d2d"
import "base:intrinsics"
import "core:log"
import win "core:sys/windows"

com_safe_release :: proc "contextless" (obj: ^^$T) 
where intrinsics.type_is_subtype_of(T, win.IUnknown) {
    if obj^ != nil {
        (obj^)->Release()
    }
    obj^ = nil
}

translate_vk :: proc "contextless" (wparam: win.WPARAM) -> u32 {
    // switch wparam {
    // case win.VK_ESCAPE: return KEY_ESCAPE   
    // case win.VK_SPACE : return KEY_SPACE    
    // case win.VK_BACK  : return KEY_BACKSPACE
    // case win.VK_RETURN: return KEY_RETURN   
    // case win.VK_LEFT  : return KEY_LEFT     
    // case win.VK_RIGHT : return KEY_RIGHT    
    // case win.VK_UP    : return KEY_UP       
    // case win.VK_DOWN  : return KEY_DOWN     
    // }
    keycode: u32
    switch wparam {
    case win.VK_CONTROL: 
        // FIXME:
        // if (cast(uint)(win.GetKeyState (win.VK_LCONTROL)) & 0x8000) != 0 {
        //     keycode=KEY_LCONTROL
        // } else {
        //     keycode=KEY_RCONTROL
        // }
        keycode = KEY_LCONTROL
    case win.VK_SHIFT:
        // FIXME:
        // if (cast(uint)(win.GetKeyState (win.VK_LSHIFT)) & 0x8000) != 0 {
        //     keycode=KEY_LSHIFT
        // } else {
        //     keycode=KEY_RSHIFT
        // }
        keycode = KEY_LSHIFT
    case:
        keycode = cast(u32)wparam 

    }
    return keycode
}


// TODO: return font name and size
// font_dialog :: proc(d2d_context: ^D2D_Context) {
//     logical_font: win.LOGFONTW
//     choose_font := CHOOSEFONTW {
//         lStructSize=size_of(CHOOSEFONTW),
//         hwndOwner=d2d_context.render_target->GetHwnd(),
//         lpLogFont=&logical_font,
//         Flags=CF_FIXEDPITCHONLY | CF_TTONLY | CF_LIMITSIZE,
//         nSizeMin=10,
//         nSizeMax=60,
//     }
//     if ChooseFontW(&choose_font) {
//         // I think lfHeight just gives font size in DIP but I'm too 100% sure
//         font_name_buf: [64]u8
//         font_name := win.wstring_to_utf8(
//             font_name_buf[:], 
//             raw_data(logical_font.lfFaceName[:])
//         )
//         font_size_dip := cast(f32)-logical_font.lfHeight
//         log.debugf("Font: %s, Size: %v", font_name, font_size_dip)
//         com_safe_release(&d2d_context.text_format)
//         result := d2d_context.dwrite_factory->CreateTextFormat(
//             raw_data(logical_font.lfFaceName[:]), 
//             nil, 
//             .NORMAL, 
//             .NORMAL, 
//             .NORMAL, 
//             font_size_dip, 
//             raw_data([]u16{0}), 
//             &d2d_context.text_format
//         )
//         assert(result == win.S_OK)
//     }
// }

CF_FIXEDPITCHONLY: win.DWORD : 0x00004000
CF_TTONLY: win.DWORD : 0x00040000
CF_LIMITSIZE: win.DWORD : 0x00002000

CHOOSEFONTW :: struct {
    lStructSize: win.DWORD,
    hwndOwner: win.HWND,
    hDC: win.HDC,
    lpLogFont: ^win.LOGFONTW,
    iPointSize: win.INT,
    Flags: win.DWORD,
    rgbColors: win.COLORREF,
    lCustData: win.LPARAM,
    lpfnHook: rawptr,
    lpTemplateName: win.LPCSTR,
    hInstance: win.HINSTANCE,
    lpszStyle: win.LPSTR,
    nFontType: win.WORD,
    ___MISSING_ALIGNMENT__: win.WORD,
    nSizeMin: win.INT,
    nSizeMax: win.INT,
}

foreign import "system:Comdlg32.lib"

foreign Comdlg32 {
    ChooseFontW :: proc "system" (param: ^CHOOSEFONTW) -> win.BOOL --- 
}
