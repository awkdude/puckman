#+build windows
package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:time"
import "core:slice"
import "core:math"
import "core:math/bits"
import "core:mem"
import "core:c"
import "base:intrinsics"
import win "core:sys/windows"
import sa "core:container/small_array"
import "core:unicode"
import "core:unicode/utf8"
import "base:runtime"
import "core:strings"
import "core:c/libc"
import "odinlib:util"
import "vendor:windows/xaudio2"

when PLATFORM_BACKEND == "native" {

USE_OPENGL :: false
frame_tick: time.Tick
vec2 :: util.vec2
window_handle: win.HWND
ixaudio2: ^xaudio2.IXAudio2
running: bool
global_context: runtime.Context
bitmap_handle: win.HBITMAP
bitmap_info: win.BITMAPINFO
memory_device_context: win.HDC
framebuffer_pixmap: util.Pixmap
min_window_size, max_window_size: Maybe(vec2)
window_position: vec2

MOVE_WINDOW_TO_RIGHTMOST_MONITOR :: false

// FIXME: Mouse position seems to be off after setting dpi awareness

wide_string_literal :: intrinsics.constant_utf16_cstring

main :: proc() {
    // logging allocator {{{
    log_alloc: util.Logging_Allocator
    util.logging_allocator_init(&log_alloc, context.allocator)
    context.allocator = util.logging_allocator(&log_alloc)
    // temp_log_alloc: Logging_Allocator
    // logging_allocator_init(&temp_log_alloc, context.temp_allocator)
    // temp_log_alloc.is_temp = true
    // context.temp_allocator = logging_allocator(&temp_log_alloc)
    // }}}
    context.logger = log.create_console_logger()
    context.logger.options -= {.Date}
    global_context = context

    // win32 setup {{{
    app_name := cast(cstring16)wide_string_literal("WINAPP")
    program_instance := cast(win.HANDLE)win.GetModuleHandleA(nil);
    window_class: win.WNDCLASSW
    window_class.style = win.CS_HREDRAW | win.CS_VREDRAW
    window_class.lpfnWndProc = window_proc
    window_class.cbClsExtra = 0
    window_class.cbWndExtra = 0
    window_class.hInstance = program_instance
    window_class.hIcon = nil
    window_class.hCursor = nil
    window_class.hbrBackground = cast(win.HBRUSH)win.GetStockObject(win.WHITE_BRUSH)
    window_class.lpszMenuName = wide_string_literal("TryMenu")
    window_class.lpszClassName = app_name

    assert(win.RegisterClassW(&window_class) != 0)

    // Find right-most monitor
    monitor_enum_proc :: proc "stdcall" (
        monitor_handle: win.HMONITOR,
        _: win.HDC,
        _: ^win.RECT,
        _: int) -> win.BOOL
    {
        @(static) rightmost_position: vec2
        monitor_info: win.MONITORINFO = { cbSize=size_of(win.MONITORINFO) }
        win.GetMonitorInfoW(monitor_handle, &monitor_info)

        when MOVE_WINDOW_TO_RIGHTMOST_MONITOR {
            if monitor_info.rcWork.left > window_position.x {
                window_position = {monitor_info.rcWork.left, monitor_info.rcWork.top}
            }
        }
        return win.TRUE
    }
    win.EnumDisplayMonitors(
        nil,
        nil,
        monitor_enum_proc,
        0
    )

    window_handle = win.CreateWindowExW(
        win.WS_EX_ACCEPTFILES,
        app_name,
        win.utf8_to_wstring("win32 window", context.temp_allocator),
        win.WS_OVERLAPPEDWINDOW,
        window_position.x,
        window_position.y,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        nil,
        nil,
        program_instance,
        nil
    )
    assert(window_handle != nil)
    win.ShowWindow(window_handle, win.SW_SHOW)
    win.UpdateWindow(window_handle)
    // }}}

    // rawinput (not needed) {{{
    when false {
        mapping_db, file_err := os.read_entire_file("gamecontrollerdb.txt", context.allocator)
        assert(file_err == nil)


        rawinput_devices := [2]win.RAWINPUTDEVICE {
            {
                usUsagePage = 0x01,
                usUsage = 0x05,
                dwFlags = win.RIDEV_INPUTSINK,
                hwndTarget = window_handle,
            },
            {
                usUsagePage = 0x01,
                usUsage = 0x06,
                dwFlags = win.RIDEV_INPUTSINK,
                hwndTarget = window_handle,
            },
        }
        reg_res := win.RegisterRawInputDevices(
            raw_data(rawinput_devices[:]),
            len(rawinput_devices),
            size_of(win.RAWINPUTDEVICE)
        )
        assert(reg_res == win.TRUE)
        devlist_count: win.UINT
        win.GetRawInputDeviceList(
            nil,
            &devlist_count,
            size_of(win.RAWINPUTDEVICELIST)
        )
        devlist_array := make([]win.RAWINPUTDEVICELIST, devlist_count)
        win.GetRawInputDeviceList(
            raw_data(devlist_array[:]),
            &devlist_count,
            size_of(win.RAWINPUTDEVICELIST)
        )
        for ridev, i in devlist_array[:devlist_count] {
            mappings := cast(string)mapping_db
            device_name: [256]u16
            dev_info: win.RID_DEVICE_INFO
            size: u32 
            win.GetRawInputDeviceInfoW(ridev.hDevice, win.RIDI_DEVICENAME, nil, &size)
            win.GetRawInputDeviceInfoW(ridev.hDevice, win.RIDI_DEVICENAME, raw_data(device_name[:]), &size)
            size = size_of(win.RID_DEVICE_INFO)
            win.GetRawInputDeviceInfoW(ridev.hDevice, win.RIDI_DEVICEINFO, &dev_info, &size)
            if dev_info.dwType != win.RIM_TYPEHID {
                continue
            }
            // TODO: get GUID!
            bustype := 0x03
            guid: [32]u8
            fmt.bprintf(
                guid[:],
                "%02x%02x0000%02x%02x0000%02x%02x0000%02x%02x0000",
                bustype & 0xff,
                (bustype >> 8) & 0xff,
                dev_info.hid.dwVendorId & 0xff,
                (dev_info.hid.dwVendorId >> 8) & 0xff,
                dev_info.hid.dwProductId & 0xff,
                (dev_info.hid.dwProductId >> 8) & 0xff,
                dev_info.hid.dwVersionNumber & 0xff,
                (dev_info.hid.dwVersionNumber >> 8) & 0xff,
            )
            log.debugf("%v: %s", i, cast(cstring16)raw_data(device_name[:]))
            log.debugf("GUID: %s", cast(string)guid[:])


            hid_dev := win.CreateFileW(
                cast(cstring16)raw_data(device_name[:]),
                win.GENERIC_READ | win.GENERIC_WRITE,
                win.FILE_SHARE_READ | win.FILE_SHARE_WRITE,
                nil,
                win.OPEN_EXISTING,
                0,
                nil
            )
            defer win.CloseHandle(hid_dev)
            buffer: [128]u16
            win.HidD_GetProductString(hid_dev, raw_data(buffer[:]), size_of(buffer))
            log.debug(cast(cstring16)raw_data(buffer[:]))
            for line in strings.split_lines_iterator(&mappings) {
                if len(line) > 32 && line[:32] == cast(string)guid[:] {
                    log.warn("Found %s!", cast(cstring16)raw_data(buffer[:]))
                    break
                }
            }
        }
    }

    // }}}

    // opengl setup {{{
    when USE_OPENGL {
	    suggested_pixel_format_desc: win.PIXELFORMATDESCRIPTOR
	    pixel_format_desc := win.PIXELFORMATDESCRIPTOR {
	        nSize=size_of(win.PIXELFORMATDESCRIPTOR),
	        nVersion=1,
	        dwFlags=win.PFD_DRAW_TO_WINDOW | win.PFD_DOUBLEBUFFER | win.PFD_SUPPORT_OPENGL,
	        iPixelType=win.PFD_TYPE_RGBA,
	        iLayerType=win.PFD_MAIN_PLANE,
	        cColorBits=32,
	        cDepthBits=24,
	        cAlphaBits=8,
	        cStencilBits=8,
	    }
	    device_context := win.GetDC(window_handle)
	    pfd_index := win.ChoosePixelFormat(
	        device_context,
	        &pixel_format_desc,
	    )
	    win.DescribePixelFormat(
	        device_context,
	        pfd_index,
	        size_of(win.PIXELFORMATDESCRIPTOR),
	        &suggested_pixel_format_desc
	    )
	    win.SetPixelFormat(device_context, pfd_index, &suggested_pixel_format_desc)
	    gl_context := win.wglCreateContext(device_context)
	    win.wglMakeCurrent(device_context, gl_context)
	    when false && ODIN_DEBUG {
	        // FIXME: Causes weird memory bug. Look at Handmade Hero code
	        CreateContextAttribsARB: win.CreateContextAttribsARBType
	        win.gl_set_proc_address(&CreateContextAttribsARB, "wglCreateContextAttribsARB")
	        assert(CreateContextAttribsARB != nil, "no wglCreateContextAttribsARB")
	        attrib_list := []i32 {
	            win.WGL_CONTEXT_MAJOR_VERSION_ARB, GL_VERSION[0],
	            win.WGL_CONTEXT_MINOR_VERSION_ARB, GL_VERSION[1],
	            win.WGL_CONTEXT_FLAGS_ARB, (
	                win.WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB | win.WGL_CONTEXT_DEBUG_BIT_ARB
	            ),
	            win.WGL_CONTEXT_PROFILE_MASK_ARB, win.WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
	            0
	        }
	        // win.wglDeleteContext(gl_context)
	        gl_context = CreateContextAttribsARB(
	            device_context,
	            nil,
	            raw_data(attrib_list)
	        )
	        assert(gl_context != nil)
	        win.wglMakeCurrent(device_context, gl_context)
	    }
	    win.ReleaseDC(window_handle, device_context)
    }
    // }}}

    update_framebuffer_win32()
    eng_ok := eng_init(Engine_Init{
        // gl_set_proc_address=win.gl_set_proc_address,
        set_gamepad_rumble_proc=set_gamepad_rumble_xinput,
        platform_command_proc=handle_platform_command_win,
        get_window_dpi = proc() -> i32 {
            return cast(i32)win.GetDpiForWindow(window_handle)
        },
        pixel_format={bytes_per_pixel=4, layout=util.DEFAULT_PIXEL_LAYOUT},
    })

    if !eng_ok {
        return
    }

    running = true
    when USE_OPENGL {
        SwapIntervalEXT: win.SwapIntervalEXTType
        win.gl_set_proc_address(&SwapIntervalEXT, "wglSwapIntervalEXT")
        assert(SwapIntervalEXT != nil, "no wglSwapIntervalEXT")
        SwapIntervalEXT(1)
    }
    win.XInputEnable(true)
    com_result := win.CoInitializeEx(nil, .MULTITHREADED)
    if win.FAILED(com_result) {
        panic("COM failed")
    }
    assert(win.SUCCEEDED(xaudio2.Create(&ixaudio2, {.DEBUG_ENGINE}, xaudio2.USE_DEFAULT_PROCESSOR)))
    mastering_voice: ^xaudio2.IXAudio2MasteringVoice
    assert(win.SUCCEEDED(ixaudio2->CreateMasteringVoice(&mastering_voice)))
    source_voice: ^xaudio2.IXAudio2SourceVoice
    samples_per_sec: u32 = 44100
    bits_per_sample: u32 = 16
    num_channels: u32 = 2
    block_align := num_channels*(bits_per_sample/8)
    wave_format := win.WAVEFORMATEX {
        wFormatTag=win.WAVE_FORMAT_PCM,
        nChannels=cast(u16)num_channels,
        nSamplesPerSec=samples_per_sec,
        nBlockAlign=cast(u16)block_align,
        nAvgBytesPerSec=samples_per_sec * block_align,
        wBitsPerSample=cast(u16)bits_per_sample,
        cbSize=0,
    }
    assert(win.SUCCEEDED(ixaudio2->CreateSourceVoice(&source_voice, &wave_format)))
    audio_buffer_size := samples_per_sec*block_align*2
    audio_buffer := make([]u8, audio_buffer_size)
    buffer_index: u32 = 0
    phase: f32 = 0
    for buffer_index < audio_buffer_size {
        // n: f32 = 523.0 + util.normalize_to_range(cast(f32)buffer_index, 0, cast(f32)audio_buffer_size, 0, 100)
        n := 300.0 + math.sin(5.0 * math.TAU * (cast(f32)buffer_index / cast(f32)audio_buffer_size)) * 300
        phase += 2 * math.PI * (n / 44100.0)
        s := math.sin(phase)
        if s < 0.0 {
            s = -1
        } else {
            s = 1
        }
        sample := (i16)(s * cast(f32)bits.I16_MAX * 0.05)
        audio_buffer[buffer_index+0] = cast(u8)sample
        audio_buffer[buffer_index+1] = cast(u8)(sample >> 8)
        audio_buffer[buffer_index+2] = cast(u8)sample
        audio_buffer[buffer_index+3] = cast(u8)(sample >> 8)
        buffer_index += 4
    }
    xaudio_buffer := xaudio2.BUFFER {
        Flags={.END_OF_STREAM},
        AudioBytes=audio_buffer_size,
        pAudioData=raw_data(audio_buffer),
        PlayBegin=0,
        PlayLength=0,
        LoopBegin=0,
        LoopLength=0,
        LoopCount=xaudio2.LOOP_INFINITE,
    }
    assert(win.SUCCEEDED(source_voice->SubmitSourceBuffer(&xaudio_buffer)))
    assert(win.SUCCEEDED(source_voice->Start({})))
    loop: for {
        message: win.MSG

        for win.PeekMessageW(&message, nil, 0, 0, win.PM_REMOVE) {
            win.TranslateMessage(&message)
            win.DispatchMessageW(&message)
            if message.message == win.WM_QUIT {
                break loop
            }
        }
        client_rect: win.RECT
        win.GetClientRect(
            window_handle,
            &client_rect
        )
        gamepad_state, is_connected := get_gamepad_state_xinput()
        eng_update := Engine_Update{
                window_dims={
                client_rect.right-client_rect.left,
                client_rect.bottom-client_rect.top,
            },
            gamepad_state=gamepad_state,
            is_gamepad_connected=is_connected,
            framebuffer=framebuffer_pixmap,
        }
        if !eng_update_render(eng_update) do return
		device_context := win.GetDC(window_handle)
		win.BitBlt(
			device_context,
			0,
			0,
			framebuffer_pixmap.w,
			framebuffer_pixmap.h,
			memory_device_context,
			0,
			0,
			win.SRCCOPY,
		)
		win.ReleaseDC(window_handle, device_context)
		util.wait_frame_interval(&frame_tick, 16666 * time.Microsecond)
        // device_context := win.GetDC(window_handle)
        // win.SwapBuffers(device_context)
        // win.ReleaseDC(window_handle, device_context)
    }
}

update_framebuffer_win32 :: proc() {
	rect: win.RECT
	win.GetClientRect(window_handle, &rect)
	w, h := rect.right - rect.left, rect.bottom - rect.top
	framebuffer_pixmap = util.Pixmap {
		pixels=nil,
		w = w,
		h = h,
		pitch = w * 4,
		format={layout=util.DEFAULT_PIXEL_LAYOUT, bytes_per_pixel=4},
	}
	bitmap_info = win.BITMAPINFO {
		bmiHeader = {
			biSize = cast(u32)size_of(win.BITMAPINFOHEADER),
			biWidth = w,
			biHeight = -h, // Top-bottom
			biPlanes = 1,
			biBitCount = 32,
			biCompression = win.BI_RGB,
		},
	}
	device_context := win.GetDC(window_handle)
	if memory_device_context != nil {
		win.DeleteDC(memory_device_context)
	}
	memory_device_context = win.CreateCompatibleDC(device_context)
	bitmap_handle = win.CreateDIBSection(
        nil,
        &bitmap_info,
        0,
        &framebuffer_pixmap.pixels,
        nil,
        0
    )
	// assert(bitmap_handle != nil)
	if bitmap_handle == nil {
		@(static)fake_framebuffer: [64]ColorU32
		framebuffer_pixmap = util.Pixmap {
			pixels=raw_data(fake_framebuffer[:]),
			w = 8,
			h = 8,
			pitch = 32,
			format={bytes_per_pixel=4,
		    layout = util.DEFAULT_PIXEL_LAYOUT},
		}
	}
	assert(framebuffer_pixmap.pixels != nil)
	win.SelectObject(memory_device_context, cast(win.HGDIOBJ)bitmap_handle)
	win.ReleaseDC(window_handle, device_context)
	stride := ((((bitmap_info.bmiHeader.biWidth * cast(i32)bitmap_info.bmiHeader.biBitCount) + 31) & ~cast(i32)31) >> 3)
    framebuffer_pixmap.pitch = stride
}

win32_cursor: cstring
window_proc :: proc "stdcall" (
    window_handle:
    win.HWND,
    message: c.uint,
    wparam: win.WPARAM,
    lparam: win.LPARAM) -> win.LRESULT
{
// {{{
    context = global_context
    exit_code: win.LRESULT
    window_event: Maybe(util.Window_Event)
    switch message {
    case win.WM_INPUT:

    case win.WM_CREATE:
    case win.WM_PAINT:
        paintstruct: win.PAINTSTRUCT
        device_context := win.BeginPaint(window_handle, &paintstruct)
        win.EndPaint(window_handle, &paintstruct)
    case win.WM_DROPFILES:
        path_u16: [win.MAX_PATH]u16
        drop_handle := cast(win.HDROP)wparam
        files := make([dynamic]string, 0, 4, context.temp_allocator)
        count := win.DragQueryFileW(drop_handle, 0xffffffff, raw_data(path_u16[:]), len(path_u16))
        for i in 0..<count {
            win.DragQueryFileW(drop_handle, i, raw_data(path_u16[:]), len(path_u16))
            log.debugf("%v: %s", i, raw_data(path_u16[:]))
            path, alloc_err := win.wstring_to_utf8(
                cstring16(raw_data(path_u16[:])),
                len(path_u16),
                context.temp_allocator
            )
            assert(alloc_err == nil)
            append(&files, path)
        }
        win.DragFinish(drop_handle)
        window_event = util.Window_Event {
            type=.Drop,
            files=files[:],
        }
    case win.WM_CHAR:
        window_event = util.Window_Event {
            type=.Char_Input,
            char_codepoint=cast(rune)wparam,
        }
    case win.WM_KEYUP, win.WM_KEYDOWN:
        window_event = util.Window_Event {
            type=.Key,
            key={
                keycode=util.translate_vk(wparam),
                pressed=message == win.WM_KEYDOWN,
                repeated=(lparam & (1 << 30)) != 0,
            },
        }
    // mouse button events {{{
    case win.WM_LBUTTONDOWN:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Left,
                pressed=true,
                position={
                    win.GET_X_LPARAM(lparam),
                    win.GET_Y_LPARAM(lparam)
                },
            }
        }
    case win.WM_LBUTTONUP:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Left,
                pressed=false,
                position={
                    win.GET_X_LPARAM(lparam),
                    win.GET_Y_LPARAM(lparam)
                },
            }
        }
    case win.WM_MBUTTONDOWN:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Middle,
                pressed=true,
                position={
                    win.GET_X_LPARAM(lparam),
                    win.GET_Y_LPARAM(lparam)
                },
            }
        }
    case win.WM_MBUTTONUP:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Middle,
                pressed=false,
                position={
                    win.GET_X_LPARAM(lparam),
                    win.GET_Y_LPARAM(lparam)
                },
            }
        }
    case win.WM_RBUTTONDOWN:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Right,
                pressed=true,
                position={
                    win.GET_X_LPARAM(lparam),
                    win.GET_Y_LPARAM(lparam)
                },
            }
        }
    case win.WM_RBUTTONUP:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.Right,
                pressed=false,
                position={
                    win.GET_X_LPARAM(lparam),
                    win.GET_Y_LPARAM(lparam)
                },
            }
        }
    case win.WM_XBUTTONDOWN:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.X1 if win.HIWORD(wparam) == 1 else .X2,
                pressed=true,
                position={
                    win.GET_X_LPARAM(lparam),
                    win.GET_Y_LPARAM(lparam)
                },
            }
        }
    case win.WM_XBUTTONUP:
        window_event = util.Window_Event {
            type=.Mouse_Button,
            mouse_button={
                button=.X1 if win.HIWORD(wparam) == 1 else .X2,
                pressed=false,
                position={
                    win.GET_X_LPARAM(lparam),
                    win.GET_Y_LPARAM(lparam)
                },
            }
        }
        // }}}

    case win.WM_MOUSEMOVE:
        window_event = util.Window_Event {
            type=.Mouse_Move,
            vec2={
                win.GET_X_LPARAM(lparam),
                win.GET_Y_LPARAM(lparam)
            },
        }
    case win.WM_MOUSEWHEEL:
        window_event = util.Window_Event {
            type=.Mouse_Wheel,
            vec2={
                0,
                cast(i32)(win.GET_WHEEL_DELTA_WPARAM(wparam) / win.WHEEL_DELTA),
            }
        }
    case win.WM_MOUSEHWHEEL:
        window_event = util.Window_Event {
            type=.Mouse_Wheel,
            vec2={
                cast(i32)(win.GET_WHEEL_DELTA_WPARAM(wparam) / win.WHEEL_DELTA),
                0,
            }
        }
    case win.WM_SIZE:
        width := win.GET_X_LPARAM(lparam)
        height := win.GET_Y_LPARAM(lparam)
        window_event = util.Window_Event {
            type=.Window_Resize,
            vec2={width, height},
        }
        update_framebuffer_win32()
    case win.WM_GETMINMAXINFO:
    	// TODO: use win.AdjustWindowRect() to adjust target size
        min_max_info := transmute(^win.MINMAXINFO)lparam
        if min_size, ok := min_window_size.?; ok {
            min_max_info.ptMinTrackSize = win.POINT{min_size.x, min_size.y}
        }
        if max_size, ok := max_window_size.?; ok {
            min_max_info.ptMaxTrackSize = win.POINT{max_size.x, max_size.y}
        }
    case win.WM_SETCURSOR:
        if win32_cursor != nil && win.LOWORD(lparam) == win.HTCLIENT {
            win.SetCursor(win.LoadCursorA(nil, win32_cursor))
        } else {
            win.DefWindowProcW(window_handle, message, wparam, lparam)
        }
    case win.WM_SETFOCUS:
        window_event = util.Window_Event {
            type=.Gain_Focus
        }
    case win.WM_KILLFOCUS:
        window_event = util.Window_Event {
            type=.Lose_Focus
        }
    case win.WM_CLOSE:
        window_event = util.Window_Event {
            type=.Window_Close,
        }
    case win.WM_DESTROY:
        win.PostQuitMessage(0)
    case:
        exit_code = win.DefWindowProcW(window_handle, message, wparam, lparam)
    }
    if running {
        if event, ok := window_event.?; ok {
            event.source_window = cast(util.Window_ID)window_handle
            eng_handle_event(event)
        }
    }

    return exit_code
// }}}
}

handle_platform_command_win :: proc(command: util.Platform_Command) {
    #partial switch command.type {
    case .Quit:
        win.DestroyWindow(window_handle)
    case .Rename_Window:
        buf: [128]u16
        title_ws := win.utf8_to_wstring(buf[:], command.title)
        win.SetWindowTextW(window_handle, title_ws)
    case .Change_Mouse_Cursor:
        switch command.cursor_type {
        case .Normal:
            win32_cursor = win.IDC_ARROW
        case .Wait:
            win32_cursor = win.IDC_WAIT
        case .IBeam:
            win32_cursor = win.IDC_IBEAM
        case .Hand:
            win32_cursor = win.IDC_HAND
        }
        win.SetCursor(win.LoadCursorA(nil, win32_cursor))
        log.debugf("Cursor set to %v", command.cursor_type)
    case .Resize_Window:
        if size, ok := command.size.?; ok {
        	rect := win.RECT {
         		0,
           		0,
             	size.x,
             	size.y,
         	}
          	log.debug("Requested size:", size)
        	win.AdjustWindowRect(&rect, win.WS_OVERLAPPEDWINDOW, win.FALSE)
         	log.debug(rect)
	        win.SetWindowPos(
	            window_handle,
	            nil,
	            0,
	            0,
	            rect.right - rect.left,
	            rect.bottom - rect.top,
	            win.SWP_NOMOVE | win.SWP_NOOWNERZORDER
	        )
        }
    case .Set_Window_Min_Size:
        min_window_size = command.size
    case .Set_Window_Max_Size:
        max_window_size = command.size
    case .Change_Window_Icon:
        path_ws := win.utf8_to_wstring(command.path, context.temp_allocator)
        win.SetClassLongPtrW(
            window_handle,
            win.GCLP_HICON,
            transmute(int)win.LoadImageW(
                nil,
                path_ws,
                win.IMAGE_ICON,
                0,
                0,
                win.LR_DEFAULTSIZE | win.LR_LOADFROMFILE
            )
        )
    }
}

set_gamepad_rumble_xinput :: proc(weak, strong: f32) {
    weak_ := (u16)(math.clamp(weak, 0.0, 1.0) * cast(f32)bits.U16_MAX)
    strong_ := (u16)(math.clamp(strong, 0.0, 1.0) * cast(f32)bits.U16_MAX)
    win.XInputSetState(.One, &{
        wLeftMotorSpeed=weak_,
        wRightMotorSpeed=strong_,
    })
}

get_gamepad_state_xinput :: proc() -> (util.Gamepad_State, bool) {
    @(static) old_packet_number: win.DWORD
    xinput_state: win.XINPUT_STATE
    if win.XInputGetState(.One, &xinput_state) != .SUCCESS {
        return {}, false
    }
    gamepad_state := util.Gamepad_State{
        axes = {
            .LEFT_X = cast(f32)xinput_state.Gamepad.sThumbLX / cast(f32)bits.I16_MAX,
            .LEFT_Y = -cast(f32)xinput_state.Gamepad.sThumbLY / cast(f32)bits.I16_MAX,
            .RIGHT_X = cast(f32)xinput_state.Gamepad.sThumbRX / cast(f32)bits.I16_MAX,
            .RIGHT_Y = -cast(f32)xinput_state.Gamepad.sThumbRY / cast(f32)bits.I16_MAX,
            .TRIGGER_LEFT = cast(f32)xinput_state.Gamepad.bLeftTrigger / 255.0,
            .TRIGGER_RIGHT = cast(f32)xinput_state.Gamepad.bRightTrigger / 255.0,
        }
    }
    if .A in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.SOUTH}
    }
    if .B in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.EAST}
    }
    if .X in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.WEST}
    }
    if .Y in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.NORTH}
    }
    if .START in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.START}
    }
    if .BACK in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.SELECT}
    }
    if .LEFT_SHOULDER in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.BUMPER_LEFT}
    }
    if .RIGHT_SHOULDER in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.BUMPER_RIGHT}
    }
    if .LEFT_THUMB in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.THUMB_LEFT}
    }
    if .RIGHT_THUMB in xinput_state.Gamepad.wButtons {
        gamepad_state.buttons += {.THUMB_RIGHT}
    }
    if .DPAD_UP in xinput_state.Gamepad.wButtons {
        gamepad_state.hat += {.UP}
    }
    if .DPAD_DOWN in xinput_state.Gamepad.wButtons {
        gamepad_state.hat += {.DOWN}
    }
    if .DPAD_LEFT in xinput_state.Gamepad.wButtons {
        gamepad_state.hat += {.LEFT}
    }
    if .DPAD_RIGHT in xinput_state.Gamepad.wButtons {
        gamepad_state.hat += {.RIGHT}
    }
    old_packet_number = xinput_state.dwPacketNumber
    return gamepad_state, true
}
}
