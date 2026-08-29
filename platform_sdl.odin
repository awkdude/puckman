package main

import "odinlib:file_load"
import "core:log"
import "core:strings"
import "odinlib:util"
import "core:math"
import "core:math/bits"
import sdl "vendor:sdl3"
import sdl_img "vendor:sdl3/image"
import "core:thread"
import "core:os"
import "core:time"
import "base:runtime"
import "core:fmt"

when PLATFORM_BACKEND == "sdl" {
	USE_OPENGL :: false
	global_context: runtime.Context
	frame_tick: time.Tick
    audio_buffer: []u8

	sdl_window: ^sdl.Window
	sdl_gamepad: ^sdl.Gamepad
	vec2 :: util.vec2

	running := true
	keycode_map: map[int]u32

	sdl_set_proc_address :: proc(p: rawptr, name: cstring) {
	    p := cast(^rawptr)p
	    p^ = cast(rawptr)sdl.GL_GetProcAddress(name)
	}

	main :: proc() {
        context.logger = log.create_console_logger()
	    context.logger.options -= {.Date}
        global_context = context
        audio_buffer = make([]u8, 44100*4*2*2)
	    if !sdl.Init({.VIDEO, .AUDIO, .EVENTS, .GAMEPAD}) {
	        log.panic("Could not init SDL")
	    }
	    sdl_window = sdl.CreateWindow(
	        strings.clone_to_cstring("sdl window"),
	        100,
	        100,
	        {.RESIZABLE},
	    )
	    if sdl_window == nil {
	        log.panic("Could not create SDL window")
	    }
		sdl.SetWindowPosition(sdl_window, 50, 50)
	    when USE_OPENGL {
		    sdl.GL_SetAttribute(sdl.GL_CONTEXT_PROFILE_MASK, cast(i32)sdl.GL_CONTEXT_PROFILE_CORE)
		    sdl.GL_SetAttribute(sdl.GL_CONTEXT_MAJOR_VERSION, GL_VERSION[0])
		    sdl.GL_SetAttribute(sdl.GL_CONTEXT_MINOR_VERSION, GL_VERSION[1])
		    gl_context := sdl.GL_CreateContext(sdl_window)
		    sdl.GL_MakeCurrent(sdl_window, gl_context)
			sdl.GL_SetSwapInterval(1)
	    }
        sdl_pixel_format := sdl.GetWindowPixelFormat(sdl_window)
        sdl_pixel_format_details := sdl.GetPixelFormatDetails(sdl_pixel_format)
        pixel_format := util.Pixel_Format {
            layout={
            	r=sdl_pixel_format_details.Rshift,
	            g=sdl_pixel_format_details.Gshift,
	            b=sdl_pixel_format_details.Bshift,
	            a=sdl_pixel_format_details.Ashift,
            },
            bytes_per_pixel=4,
        }
        // Find alpha shift value if non-existent
        if sdl_pixel_format_details.Abits == 0 {
            possible_shifts := [4]u8 {0, 8, 16, 24}
            for shift in possible_shifts {
                if shift != sdl_pixel_format_details.Rshift &&
                shift != sdl_pixel_format_details.Gshift &&
                shift != sdl_pixel_format_details.Bshift
                {
                    pixel_format.a = shift
                    break
                }
            }
        }
        // Load gamepad mappings
        if sdl.AddGamepadMappingsFromFile("gamecontrollerdb.txt") == -1 {
            log.error("Failture when loading gamepad mappings from 'gamecontrollerdb.txt'")
        }
        when true {
            desired_audio_spec := sdl.AudioSpec {
                freq=44100,
                format=.S16LE,
                channels=2,
            }
            phase: f32 = 0
            audio_spec: sdl.AudioSpec
            audio_stream := sdl.OpenAudioDeviceStream(
                sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK,
                &desired_audio_spec,
                proc "c" (
                    userdata: rawptr,
                    stream: ^sdl.AudioStream,
                    additional_amount, total_amount: i32) 
                {
                    amount := total_amount
                    context = global_context
                    for buffer_index := 0; buffer_index < cast(int)amount; buffer_index += 4 {
                        phase := cast(^f32)userdata
                        phase^ += math.TAU * (700.0 / 44100.0)
                        sample := (i16)(math.sin(phase^) * cast(f32)bits.I16_MAX * 0.05)
                        audio_buffer[buffer_index+0] = cast(u8)sample
                        audio_buffer[buffer_index+1] = cast(u8)(sample >> 8)
                        audio_buffer[buffer_index+2] = cast(u8)sample
                        audio_buffer[buffer_index+3] = cast(u8)(sample >> 8)
                    }
                    sdl.PutAudioStreamData(
                        stream,
                        raw_data(audio_buffer),
                        amount
                    )
                    // log.debugf("PUSED %v bytes", total_amount)
                },
                &phase
            )
            sdl.GetAudioStreamFormat(audio_stream, nil, &audio_spec)
            log.debug(audio_spec)
            // wav_audio_buf, is_wav_loaded := file_load.load_wav(
            //     "resources/StartupPowerMac.wav",
            //     target_spec=util.Audio_Spec{
            //         num_channels=audio_spec.channels,
            //         sample_rate=audio_spec.freq,
            //         bit_format=audio_format_from_sdl(audio_spec.format), // TODO: Make bit format conv proc
            //     }
            // )
            for buffer_index := 0; buffer_index < len(audio_buffer); {
                // phase += 2 * math.PI * (523.0 / cast(f32)audio_spec.freq)
                // sample := math.sin(phase) * 0.5
                // (cast(^f32le)(&audio_buffer[buffer_index+0]))^ = cast(f32le)sample
                // (cast(^f32le)(&audio_buffer[buffer_index+4]))^ = cast(f32le)sample
                phase += 2 * math.PI * (523.0 / 44100.0)
                sample := (i16)(math.sin(phase) * cast(f32)bits.I16_MAX * 0.05)
                audio_buffer[buffer_index+0] = cast(u8)sample
                audio_buffer[buffer_index+1] = cast(u8)(sample >> 8)
                audio_buffer[buffer_index+2] = cast(u8)sample
                audio_buffer[buffer_index+3] = cast(u8)(sample >> 8)
                buffer_index += 4
            } 
            sdl.ResumeAudioStreamDevice(audio_stream)
            sdl.PutAudioStreamData(
                audio_stream,
                raw_data(audio_buffer),
                cast(i32)len(audio_buffer)
            )
            if false do os.exit(0)
        }
	    eng_ok := eng_init(Engine_Init{
	        // gl_set_proc_address=sdl_set_proc_address,
	        set_gamepad_rumble_proc=set_gamepad_rumble_sdl,
	        platform_command_proc=handle_platform_command_sdl,
	        get_window_dpi = proc() -> i32 {
	            // TODO:
	            return 0
	        },
            pixel_format=pixel_format,
	    })
	    if !eng_ok {
	        return
	    }
	    _ = sdl.StartTextInput(sdl_window)

	    keycode_map = make(map[int]u32, 128)
	    for pair in sdl_key_to_keycode_mappings {
	        keycode_map[pair.k] = pair.v
	    }
        log.debugf(
            "R: %v, G: %v, B: %v, A: %v",
            pixel_format.r,
            pixel_format.g,
            pixel_format.b,
            pixel_format.a,
        )
	    for running {
	        handle_events()
	        w, h: i32
	        sdl.GetWindowSize(sdl_window, &w, &h)
	        gamepad_state, gamepad_ok := get_gamepad_state_sdl()
	        window_surface := sdl.GetWindowSurface(sdl_window)
	        framebuffer := util.Pixmap{
	        	pixels=window_surface.pixels,
	            w=w,
	            h=h,
	            pitch=window_surface.pitch,
                format=pixel_format,
	        }
	        U := Engine_Update{
	            window_dims={w, h},
	            gamepad_state=gamepad_state,
	            is_gamepad_connected=gamepad_ok,
	            framebuffer=framebuffer,
	        }
	        if !eng_update_render(U) do return
	        sdl.UpdateWindowSurface(sdl_window)
			util.wait_frame_interval(&frame_tick, 16666 * time.Microsecond)
	        // sdl.GL_SwapWindow(sdl_window)
	    }
	}

	set_gamepad_rumble_sdl :: proc(weak, strong: f32) {
	    if sdl_gamepad != nil {
	        weak_ := cast(u16)(math.clamp(weak, 0.0, 1.0) * cast(f32)bits.U16_MAX)
	        strong_ := cast(u16)(math.clamp(strong, 0.0, 1.0) * cast(f32)bits.U16_MAX)
	        sdl.RumbleGamepad(sdl_gamepad, weak_, strong_, 5 * 1000)
	    }
	}

	handle_events :: proc() {
	    sdl_event: sdl.Event
	    window_event: Maybe(util.Window_Event)
	    drop_files: [dynamic]string
	    for sdl.PollEvent(&sdl_event) {
	        // TODO: Set source_window for all events
	        #partial switch sdl_event.type {
	        case .KEY_DOWN, .KEY_UP: {
	            window_event = util.Window_Event {
	                type=.Key,
	                key={
	                    pressed=(sdl_event.type==.KEY_DOWN),
	                    // FIXME: translate these!
	                    keycode=translate_sdl_key_to_keycode(cast(u32)sdl_event.key.key),
	                }
	            }
                if sdl_event.type == .KEY_DOWN && sdl_event.key.key == sdl.K_F11 {
                    @(static) window_is_fullscreen := false
                    window_is_fullscreen = !window_is_fullscreen 
                    sdl.SetWindowFullscreen(sdl_window, window_is_fullscreen)
                }
	        }
	        case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
	            // TODO: may have to check for sdl_event.button.clicks
	            mouse_button: util.Mouse_Button
	            switch cast(sdl.MouseButtonFlag)sdl_event.button.button {
	            case .LEFT:
	                mouse_button = .Left
	            case .MIDDLE:
	                mouse_button = .Middle
	            case .RIGHT:
	                mouse_button = .Right
	            case .X1:
	                mouse_button = .X1
	            case .X2:
	                mouse_button = .X2
	            }
	            window_event = util.Window_Event {
	                type=.Mouse_Button,
	                mouse_button={
	                    button=mouse_button,
	                    pressed=sdl_event.button.down,
	                    position={cast(i32)sdl_event.button.x, cast(i32)sdl_event.button.y},
	                }
	            }
	        case .WINDOW_RESIZED:
	            window_event = util.Window_Event {
	                type=.Window_Resize,
	                vec2={
	                    cast(i32)sdl_event.window.data1,
	                    cast(i32)sdl_event.window.data2,
	                },
	            }
				window_surface := sdl.GetWindowSurface(sdl_window)
	        case .MOUSE_WHEEL: {
	            window_event = util.Window_Event {
	                type=.Mouse_Wheel,
	                vec2={
	                    cast(i32)sdl_event.wheel.x,
	                    cast(i32)sdl_event.wheel.y,
	                }
	            }
	        }
	        case .MOUSE_MOTION: {
	            window_event = util.Window_Event {
	                type=.Mouse_Move,
	                vec2={
	                    cast(i32)sdl_event.motion.x,
	                    cast(i32)sdl_event.motion.y,
	                }
	            }
	        }
	        case .TEXT_INPUT:
	            log.debug("Text input: %s", sdl_event.text)
	        case .WINDOW_FOCUS_GAINED:
	            window_event = util.Window_Event{type=.Gain_Focus}
	        case .WINDOW_FOCUS_LOST:
	            window_event = util.Window_Event{type=.Lose_Focus}
	        case .WINDOW_CLOSE_REQUESTED:
	            window_event = util.Window_Event {type=.Window_Close}
	        case .DROP_BEGIN:
	            clear(&drop_files)
	        case .DROP_FILE:
	            append(
	                &drop_files,
	                strings.clone(string(sdl_event.drop.data), context.temp_allocator)
	            )
	        case .DROP_COMPLETE:
	            window_event = util.Window_Event {
	                type=.Drop,
	                files=drop_files[:],
	            }
			case .JOYSTICK_ADDED:
				log.debug("Joystick added")
			case .JOYSTICK_REMOVED:
				log.debug("Joystick removed")
	        }
	        if event, ok := window_event.?; ok {
	            eng_handle_event( event)
	        }
	    }
	}

	handle_platform_command_sdl :: proc(command: util.Platform_Command) {
	    #partial switch command.type {
	    case .Resize_Window:
	        if size, ok := command.size.?; ok {
	            sdl.SetWindowSize(sdl_window, size.x, size.y)
	        }
	    case .Change_Window_Icon:
	        path_cstr := strings.unsafe_string_to_cstring(command.path)
	        icon_surface := sdl_img.Load(path_cstr)
	        if icon_surface != nil {
	            sdl.SetWindowIcon(sdl_window, icon_surface)
	            sdl.DestroySurface(icon_surface)
	        }
	    case .Set_Window_Min_Size:
	        min_size := command.size.? or_else {0, 0}
	        sdl.SetWindowMinimumSize(sdl_window, min_size.x, min_size.y)
	    case .Rename_Window:
	        sdl.SetWindowTitle(sdl_window, strings.unsafe_string_to_cstring(command.title))
	    }
	}

	get_gamepad_state_sdl :: proc() -> (util.Gamepad_State, bool) {
	    if sdl_gamepad == nil {
	        if sdl.HasGamepad() {
	            count: i32
	            joystick_ids := sdl.GetGamepads(&count)
	            if count == 0 {
	                return {}, false
	            }
	            // Just get first gamepad for now
	            gamepad := sdl.OpenGamepad(joystick_ids[0])
	            if gamepad != nil {
	                log.debugf("%s is connected", sdl.GetGamepadName(gamepad))
	                sdl_gamepad = gamepad
	            }
	        }
		    if sdl_gamepad == nil {
		        return {}, false
		    }
	    } else {
			if !sdl.GamepadConnected(sdl_gamepad) {
                log.debugf("%s disconnected", sdl.GetGamepadName(sdl_gamepad))
				sdl_gamepad = nil
				return {}, false
			}
		}
	    gamepad_state := util.Gamepad_State {
	        axes={
	            .LEFT_X=util.normalize_to_range(
	                cast(f32)sdl.GetGamepadAxis(sdl_gamepad, .LEFTX),
	                cast(f32)sdl.JOYSTICK_AXIS_MIN,
	                cast(f32)sdl.JOYSTICK_AXIS_MAX,
	                -1.0,
	                1.0
	            ),
	            .LEFT_Y=util.normalize_to_range(
	                cast(f32)sdl.GetGamepadAxis(sdl_gamepad, .LEFTY),
	                cast(f32)sdl.JOYSTICK_AXIS_MIN,
	                cast(f32)sdl.JOYSTICK_AXIS_MAX,
	                -1.0,
	                1.0
	            ),
	            .RIGHT_X=util.normalize_to_range(
	                cast(f32)sdl.GetGamepadAxis(sdl_gamepad, .RIGHTX),
	                cast(f32)sdl.JOYSTICK_AXIS_MIN,
	                cast(f32)sdl.JOYSTICK_AXIS_MAX,
	                -1.0,
	                1.0
	            ),
	            .RIGHT_Y=util.normalize_to_range(
	                cast(f32)sdl.GetGamepadAxis(sdl_gamepad, .RIGHTY),
	                cast(f32)sdl.JOYSTICK_AXIS_MIN,
	                cast(f32)sdl.JOYSTICK_AXIS_MAX,
	                -1.0,
	                1.0
	            ),
	            .TRIGGER_LEFT=util.normalize_to_range(
	                cast(f32)sdl.GetGamepadAxis(sdl_gamepad, .LEFT_TRIGGER),
	                cast(f32)sdl.JOYSTICK_AXIS_MIN,
	                cast(f32)sdl.JOYSTICK_AXIS_MAX,
	                -1.0,
	                1.0
	            ),
	            .TRIGGER_RIGHT=util.normalize_to_range(
	                cast(f32)sdl.GetGamepadAxis(sdl_gamepad, .RIGHT_TRIGGER),
	                cast(f32)sdl.JOYSTICK_AXIS_MIN,
	                cast(f32)sdl.JOYSTICK_AXIS_MAX,
	                -1.0,
	                1.0
	            ),
	        }
	    }
	    // buttons {{{
	    if sdl.GetGamepadButton(sdl_gamepad, .SOUTH) {
	        gamepad_state.buttons += {.SOUTH}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .EAST) {
	        gamepad_state.buttons += {.EAST}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .NORTH) {
	        gamepad_state.buttons += {.NORTH}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .WEST) {
	        gamepad_state.buttons += {.WEST}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .START) {
	        gamepad_state.buttons += {.START}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .BACK) {
	        gamepad_state.buttons += {.SELECT}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .LEFT_STICK) {
	        gamepad_state.buttons += {.THUMB_LEFT}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .RIGHT_STICK) {
	        gamepad_state.buttons += {.THUMB_RIGHT}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .LEFT_SHOULDER) {
	        gamepad_state.buttons += {.BUMPER_LEFT}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .RIGHT_SHOULDER) {
	        gamepad_state.buttons += {.BUMPER_RIGHT}
	    }
	    // hats {{{
	    if sdl.GetGamepadButton(sdl_gamepad, .DPAD_UP) {
	        gamepad_state.hat += {.UP}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .DPAD_RIGHT) {
	        gamepad_state.hat += {.RIGHT}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .DPAD_LEFT) {
	        gamepad_state.hat += {.LEFT}
	    }
	    if sdl.GetGamepadButton(sdl_gamepad, .DPAD_DOWN) {
	        gamepad_state.hat += {.DOWN}
	    }
	    return gamepad_state, true
	}

	// NOTE: A-Z, 0-9, F1-F12 not needed
	sdl_key_to_keycode_mappings := []struct { k: int, v: u32 } {
	    {sdl.K_ESCAPE, util.KEY_ESCAPE},
	    {sdl.K_SPACE, util.KEY_SPACE},
	    {sdl.K_UP, util.KEY_UP},
	    {sdl.K_DOWN, util.KEY_DOWN},
	    {sdl.K_RIGHT, util.KEY_RIGHT},
	    {sdl.K_LEFT, util.KEY_LEFT},
	    {sdl.K_LCTRL, util.KEY_LCONTROL},
	    {sdl.K_LSHIFT, util.KEY_LSHIFT},
	    {sdl.K_PAGEUP, util.KEY_PAGEUP},
	    {sdl.K_PAGEDOWN, util.KEY_PAGEDOWN},
		{sdl.K_F1, util.KEY_F1},
		{sdl.K_F2, util.KEY_F2},
		{sdl.K_F3, util.KEY_F3},
		{sdl.K_F4, util.KEY_F4},
	}

	translate_sdl_key_to_keycode :: proc(sdl_key: u32) -> u32 {
	    switch sdl_key {
	    case sdl.K_A..=sdl.K_Z:
	        return util.KEY_A + (sdl_key - cast(u32)sdl.K_A)
	    case sdl.K_0..=sdl.K_9:
	        return util.KEY_0 + (sdl_key - cast(u32)sdl.K_0)
	    case sdl.K_F1..=sdl.K_F12:
	        return util.KEY_F1 + (sdl_key - cast(u32)sdl.K_F1)
	    }
	    return keycode_map[cast(int)sdl_key] or_else 0
	    // switch sdl_key {
	    // case sdl.K_ESCAPE:
	    //     return util.KEY_ESCAPE
	    // case sdl.K_SPACE:
	    //     return util.KEY_SPACE
	    // case sdl.K_UP:
	    //     return util.KEY_UP
	    // case sdl.K_DOWN:
	    //     return util.KEY_DOWN
	    // case sdl.K_RIGHT:
	    //     return util.KEY_RIGHT
	    // case sdl.K_LEFT:
	    //     return util.KEY_LEFT
	    // case sdl.K_LCTRL:
	    //     return util.KEY_LCONTROL
	    // case sdl.K_LSHIFT:
	    //     return util.KEY_LSHIFT
	    // case sdl.K_PAGEUP:
	    //     return util.KEY_PAGEUP
	    // case sdl.K_PAGEDOWN:
	    //     return util.KEY_PAGEDOWN
	    // }
	}
    audio_format_from_sdl :: proc "contextless" (sdl_audio_format: sdl.AudioFormat) -> util.Audio_Format
    {
        #partial switch sdl_audio_format {
        case .U8:
            return .U8
        case .S16LE:
            return .S16
        case .F32LE:
            return .F32_LE
        }
        return .U8
    }
}
