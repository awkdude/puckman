#+build windows
package draw

import win "core:sys/windows"
import "../d2d"
import "../util"

D2D_Context :: struct {
    factory: ^d2d.ID2D1Factory,
    render_target: ^d2d.ID2D1HwndRenderTarget,
    dwrite_factory: ^d2d.IDWriteFactory,
    text_layout: ^d2d.IDWriteTextLayout,
    solid_color_brush: ^d2d.ID2D1SolidColorBrush,
}

d2d_create_font :: proc(
    draw_context: ^Draw_Context,
    font_name: string,
    font_size_dip: f32,
    resource_type: Font_Resource_Type = .System) -> rawptr 
{
    font_name_buf: [256]u16
    font_name_ws := win.utf8_to_utf16(font_name_buf[:], font_name)
    d2d_context := cast(^D2D_Context)draw_context.data
    text_format: ^d2d.IDWriteTextFormat
    result := d2d_context.dwrite_factory->CreateTextFormat(
        raw_data(font_name_ws), 
        nil, 
        .NORMAL, 
        .NORMAL, 
        .NORMAL, 
        font_size_dip, 
        raw_data([]u16{0}), 
        &text_format
    )
    return cast(rawptr)text_format
}

d2d_get_char_rect :: proc(
    draw_context: ^Draw_Context,
    font: rawptr,
    text: string,
    char_index: int) -> (Rect, bool)
{
    d2d_context := cast(^D2D_Context)draw_context.data
    text_format := cast(^d2d.IDWriteTextFormat)font
    render_size: d2d.D2D_SIZE_U
    d2d_context.render_target->GetPixelSize(&render_size)
    text_ws := win.utf8_to_utf16(text, context.temp_allocator)
    text_layout: ^d2d.IDWriteTextLayout
    result: win.HRESULT
    result = d2d_context.dwrite_factory->CreateTextLayout(
        raw_data(text_ws), 
        cast(u32)len(text_ws),
        text_format,
        cast(f32)render_size.width,
        cast(f32)render_size.height,
        &text_layout
    )
    if result != win.S_OK do return {}, false 
    defer util.com_safe_release(&text_layout)
    hit_test_metrics: d2d.DWRITE_HIT_TEST_METRICS
    x, y: f32
    result = text_layout->HitTestTextPosition(
        cast(u32)char_index,
        win.FALSE,
        &x,
        &y,
        &hit_test_metrics,
    )
    if result != win.S_OK do return {}, false 
    return Rect {
        x=cast(i32)(hit_test_metrics.left),
        y=cast(i32)(hit_test_metrics.top),
        w=cast(i32)hit_test_metrics.width,
        h=cast(i32)hit_test_metrics.height,
    }, true
}

d2d_measure_string :: proc(draw_context: ^Draw_Context, font: rawptr, text: string) -> vec2 {
    d2d_context := cast(^D2D_Context)draw_context.data
    size: vec2
    // size, ok := size.?
    if true {  // !ok {
        render_size: d2d.D2D_SIZE_U
        d2d_context.render_target->GetPixelSize(&render_size)
        size = vec2{cast(i32)render_size.width, cast(i32)render_size.height}
    }
    text_layout: ^d2d.IDWriteTextLayout
    text_format := cast(^d2d.IDWriteTextFormat)font
    text_ws := win.utf8_to_utf16(text, context.temp_allocator)
    // defer delete(text_ws)
    d2d_context.dwrite_factory->CreateTextLayout(
        raw_data(text_ws), 
        cast(u32)len(text_ws),
        text_format,
        cast(f32)size.x,
        cast(f32)size.y,
        &text_layout
    )
    defer util.com_safe_release(&text_layout)
    text_metrics: d2d.DWRITE_TEXT_METRICS
    text_layout->GetMetrics(&text_metrics)
    return vec2 {
        cast(i32)text_metrics.widthIncludingTrailingWhitespace + 1, 
        cast(i32)text_metrics.height + 1,
    }
} 

d2d_push_command :: proc(draw_context: ^Draw_Context, command: Command) {
    d2d_context := cast(^D2D_Context)draw_context.data
    // Sort?
    // log.debugf("# draw_context = %v", len(draw_context.buffer))
    // _fill(pixmap, draw_context.clear_color)
    #partial switch params in command {
    case Clear:
        color := params.color
        d2d_context.render_target->Clear(transmute(^d2d.D2D1_COLOR_F)&color)
    case Stroke_Line:
        stroke_style: ^d2d.ID2D1StrokeStyle
        color := params.color
        d2d_context.solid_color_brush->SetColor(transmute(^d2d.D2D1_COLOR_F)&color)
        d2d_context.render_target->DrawLine(
            d2d.D2D_POINT_2F{cast(f32)params.pts[0].x, cast(f32)params.pts[0].y},
            d2d.D2D_POINT_2F{cast(f32)params.pts[1].x, cast(f32)params.pts[1].y},
            d2d_context.solid_color_brush,
            cast(f32)params.line_width,
            stroke_style,
        )
    case Stroke_Rect:
        rect_f := rect_to_d2d_rect(params.rect)
        color := params.color
        stroke_style: ^d2d.ID2D1StrokeStyle
        if params.style == .Dash {
            d2d_context.factory->CreateStrokeStyle(
                &{
                    startCap=.FLAT,
                    endCap=.FLAT,
                    dashCap=.FLAT,
                    miterLimit=1.0, // ??
                    dashStyle=.DASH,
                    dashOffset=0,
                },
                nil,
                0,
                &stroke_style
            )
        }
        defer util.com_safe_release(&stroke_style)
        d2d_context.solid_color_brush->SetColor(transmute(^d2d.D2D1_COLOR_F)&color)
        d2d_context.render_target->DrawRectangle(
            &rect_f, 
            d2d_context.solid_color_brush,
            cast(f32)-params.line_width,
            stroke_style,
        )
    case Fill_Rect:
        // _fill_rect(pixmap, params.rect, params.color)
        rect_f := rect_to_d2d_rect(params.rect)
        color := params.color
        d2d_context.solid_color_brush->SetColor(transmute(^d2d.D2D1_COLOR_F)&color)
        d2d_context.render_target->FillRectangle(
            &rect_f, 
            d2d_context.solid_color_brush
        )
    case Fill_Rounded_Rect:
        rounded_rect := d2d.D2D1_ROUNDED_RECT {
            rect=rect_to_d2d_rect(params.rect),
            radiusX=cast(f32)params.corner_radius,
            radiusY=cast(f32)params.corner_radius,
        }
        color := params.color
        d2d_context.solid_color_brush->SetColor(transmute(^d2d.D2D1_COLOR_F)&color)
        d2d_context.render_target->FillRoundedRectangle(
            &rounded_rect, 
            d2d_context.solid_color_brush
        )
    case Blit:
        // _blit(pixmap, params.pixmap, params.off, nil, nil)
    case Blit_Mono_To_Truecolor:
        // _blit_pixmap_mono_to_truecolor(pixmap, params.pixmap, params.off, params.color, 
        //     params.src_rect)
    case Draw_Text:
        layout_rect: d2d.D2D_SIZE_F
        d2d_context.render_target->GetSize(&layout_rect)
        color := params.color
        d2d_context.solid_color_brush->SetColor(transmute(^d2d.D2D1_COLOR_F)&color)
        text_format := cast(^d2d.IDWriteTextFormat)params.font
        d2d_alignment: d2d.DWRITE_TEXT_ALIGNMENT
        switch params.alignment {
        case .Leading:
            d2d_alignment = .LEADING
        case .Center:
            d2d_alignment = .CENTER
        case .Trailing:
            d2d_alignment = .TRAILING
        }
        text_format->SetTextAlignment(d2d_alignment)
        text_ws := win.utf8_to_utf16(params.text, context.temp_allocator)
        d2d_context.render_target->DrawText(
            raw_data(text_ws),
            cast(u32)len(text_ws),
            text_format,
            &d2d.D2D_RECT_F{
                cast(f32)params.rect.x,
                cast(f32)params.rect.y,
                cast(f32)(params.rect.x+params.rect.w),
                cast(f32)(params.rect.y+params.rect.h),
            },
            d2d_context.solid_color_brush,
            {},
            .NATURAL
        )
    }
}

d2d_push_clip_rect :: proc(draw_context: ^Draw_Context, rect: Rect) {
    d2d_context := cast(^D2D_Context)draw_context.data
    d2d_rect := rect_to_d2d_rect(rect)
    d2d_context.render_target->PushAxisAlignedClip(&d2d_rect, .ALIASED)
}

d2d_pop_clip_rect :: proc(draw_context: ^Draw_Context) {
    d2d_context := cast(^D2D_Context)draw_context.data
    d2d_context.render_target->PopAxisAlignedClip()
}

d2d_begin_frame :: proc(draw_context: ^Draw_Context) {
    d2d_context := cast(^D2D_Context)draw_context.data
    d2d_context.render_target->BeginDraw()
}

d2d_end_frame :: proc(draw_context: ^Draw_Context) {
    d2d_context := cast(^D2D_Context)draw_context.data
    d2d_context.render_target->EndDraw(nil, nil)
}

d2d_get_render_target_dpi :: proc(draw_context: ^Draw_Context) -> i32 {
    d2d_context := cast(^D2D_Context)draw_context.data
    return cast(i32)win.GetDpiForWindow(d2d_context.render_target->GetHwnd())
}

d2d_resize :: proc(draw_context: ^Draw_Context, size: vec2) {
    d2d_context := cast(^D2D_Context)draw_context.data
    d2d_context.render_target->Resize(&d2d.D2D_SIZE_U {
        cast(u32)size.x,
        cast(u32)size.y,
    })
}

d2d_get_render_target_size :: proc(draw_context: ^Draw_Context) -> vec2 {
    d2d_context := cast(^D2D_Context)draw_context.data
    render_size_u: d2d.D2D_SIZE_U
    d2d_context.render_target->GetPixelSize(&render_size_u)
    return vec2 {
        cast(i32)render_size_u.width,
        cast(i32)render_size_u.height,
    }
}

new_draw_context_direct2d :: proc(
    window_handle: win.HWND,
    allocator := context.allocator) -> Draw_Context 
{
    d2d_context := new(D2D_Context, allocator)
    result: win.HRESULT
    assert(win.SUCCEEDED(win.CoInitialize(nil)))
    result = d2d.D2D1CreateFactory(
        .SINGLE_THREADED,
        d2d.ID2D1Factory_UUID,
        &{.NONE},
        transmute(^rawptr)&d2d_context.factory
    )
    client_rect: win.RECT
    win.GetClientRect(window_handle, &client_rect)
    size := d2d.D2D_SIZE_U {
        u32(client_rect.right - client_rect.left), 
        u32(client_rect.bottom - client_rect.top)
    }
    render_target_props := d2d.D2D1_RENDER_TARGET_PROPERTIES {
        type=.DEFAULT,
        pixelFormat={format=.B8G8R8A8_UNORM, alphaMode=.UNKNOWN},
        usage=.NONE,
        minLevel=.DEFAULT,
    }
    hwnd_render_target_props := d2d.D2D1_HWND_RENDER_TARGET_PROPERTIES {
        hwnd=window_handle,
        pixelSize=size,
        presentOptions={.RETAIN_CONTENTS},
    }
    result = d2d_context.factory->CreateHwndRenderTarget(
        &render_target_props, 
        &hwnd_render_target_props, 
        &d2d_context.render_target
    )
    assert(result == win.S_OK)
    result = d2d.DWriteCreateFactory(
        .SHARED,
        d2d.IDWriteFactory_UUID, 
        transmute(^rawptr)&d2d_context.dwrite_factory
    )
    assert(result == win.S_OK)
    result = d2d_context.render_target->CreateSolidColorBrush(
        d2d_color(&{0.0,0.0,0.0,1.0}),
        &d2d.D2D1_BRUSH_PROPERTIES {
            opacity=1,
        },
        &d2d_context.solid_color_brush
    )
    assert(result == win.S_OK)
    return Draw_Context {
        vtable=new_clone(D2D_VTable, allocator),
        data=d2d_context,
    }
}

D2D_VTable := Draw_Context_VTable {
    push_clip_rect=d2d_push_clip_rect,
    pop_clip_rect=d2d_pop_clip_rect,
    begin_frame=d2d_begin_frame,
    end_frame=d2d_end_frame,
    get_render_target_dpi=d2d_get_render_target_dpi,
    get_render_target_size=d2d_get_render_target_size,
    measure_string=d2d_measure_string,
    push_command=d2d_push_command,
    resize=d2d_resize,
    create_font=d2d_create_font,
    get_char_rect=d2d_get_char_rect,
} 

d2d_color :: proc(color: ^Color_f) -> ^d2d.D2D1_COLOR_F {
    return transmute(^d2d.D2D1_COLOR_F)color
}

rect_to_d2d_rect :: proc(rect: Rect) -> d2d.D2D_RECT_F {
    return {
        cast(f32)rect.x,
        cast(f32)rect.y,
        cast(f32)(rect.x + rect.w),
        cast(f32)(rect.y + rect.h),
    }
}

get_render_target_dpi :: proc(render_target: ^d2d.ID2D1RenderTarget) -> i32 {
    dpi_x, dpi_y: f32
    render_target->GetDpi(&dpi_x, &dpi_y)
    return cast(i32)dpi_x
}

