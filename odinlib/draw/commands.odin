package draw

import "../util"
// import "../draw"
import "core:math"
import "core:log"

vec2f :: util.vec2f
BBoxf :: util.BBoxf
// Rect :: util.Rect
// vec2 :: util.vec2
// Color_f :: util.Color_f

Clear :: struct { color: Color_f }

Fill_Rect :: struct {
    rect: Rect,
    color: Color_f,
}

Fill_Rounded_Rect :: struct {
    rect: Rect,
    color: Color_f,
    corner_radius: i32,
}

Stroke_Rect :: struct {
    rect: Rect,
    color: Color_f,
    line_width: i32,
    style: Stroke_Style,
}

Fill_Circle :: struct {
    origin: vec2,
    radius: i32,
    color: Color_f,
}

Stroke_Line :: struct {
    pts: [2]vec2,
    line_width: i32,
    color: Color_f,
    style: Stroke_Style,
}

Fill_Tri :: struct {
    v0, v1, v2: vec2,
    color: Color_f,
}

Blit :: struct {
    pixmap: ^util.Pixmap,
    off: vec2,
}

Blit_Mono_To_Truecolor :: struct {
    pixmap: ^util.Pixmap,
    off: vec2,
    color: Color_f,
    src_rect: Maybe(Rect),
}

Draw_Text :: struct {
    text: string,
    font: rawptr,
    rect: Rect,
    color: Color_f,
    alignment: enum {
        Leading,
        Center,
        Trailing,
    }
}

Command :: union {
    Clear,
    Fill_Rect,
    Fill_Rounded_Rect, 
    Stroke_Rect,
    Fill_Circle,
    Stroke_Line,
    Fill_Tri,
    Blit,
    Blit_Mono_To_Truecolor,
    Draw_Text,
}

Stroke_Style :: enum {
    Solid,
    Dash,
}

map_coord :: proc(v: f32, size, offset: i32) -> i32 {
    return i32((v * 0.5 + 0.5) * cast(f32)size) + offset
}

map_point :: proc(v: vec2f, rect: Rect) -> vec2 {
    sv := (v * 0.5 + 0.5) * vec2f{cast(f32)rect.w, cast(f32)rect.h}
    return {cast(i32)sv.x, cast(i32)sv.y} + {rect.x, rect.y}
}

fill_rect_nc :: proc(draw_context: ^Draw_Context, rc: BBoxf, color: Color_f, bbox: Rect) {
    draw_context->push_command(Fill_Rect {
        rect = util.bbox_to_rect(util.BBox {
            x0=map_coord(rc.x0, bbox.w, bbox.x),
            y0=map_coord(rc.y0, bbox.h, bbox.y),
            x1=map_coord(rc.x1, bbox.w, bbox.x),
            y1=map_coord(rc.y1, bbox.h, bbox.y),
        }),
        color=color,
    })
}

stroke_rect_nc :: proc(
    draw_context: ^Draw_Context,
    rc: BBoxf,
    color: Color_f, 
    line_width: i32,
    bbox: Rect) 
{
    draw_context->push_command(Stroke_Rect {
        rect = util.bbox_to_rect(util.BBox {
            x0=map_coord(rc.x0, bbox.w, bbox.x),
            y0=map_coord(rc.y0, bbox.h, bbox.y),
            x1=map_coord(rc.x1, bbox.w, bbox.x),
            y1=map_coord(rc.y1, bbox.h, bbox.y),
        }),
        line_width=line_width,
        color=color,
    })
}

stroke_line_nc :: proc(draw_context: ^Draw_Context, p0, p1: vec2f, color: Color_f, bbox: Rect) {
    draw_context->push_command(Stroke_Line {
        pts={
            map_point(p0, bbox),
            map_point(p1, bbox),
        },
        color=color,
    })
}

fill_tri_nc :: proc(draw_context: ^Draw_Context, v0, v1, v2: vec2f, color: Color_f, bbox: Rect) {
    draw_context->push_command(Fill_Tri {
        v0 = map_point(v0, bbox),
        v1 = map_point(v1, bbox),
        v2 = map_point(v2, bbox),
        color=color,
    })
}

fill_circle_nc :: proc(
    draw_context: ^Draw_Context, 
    origin: vec2f, 
    radius: f32, 
    color: Color_f, 
    bbox: Rect)
{
    draw_context->push_command(Fill_Circle {
        origin = map_point(origin, bbox),
        radius = i32(radius * cast(f32)math.min(bbox.w, bbox.h)) / 2,
        color=color,
    })
}
