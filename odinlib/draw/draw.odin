package draw

import "core:mem"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:math/bits"
import "core:os"
import "core:log"
// import stbtt "vendor:stb/truetype"
// import "../freetype"
import stbi "vendor:stb/image"
import "../util"
import win "core:sys/windows"
import "../d2d"

vec2   :: util.vec2
Rect   :: util.Rect
BBox :: util.BBox
Color_f  :: util.Color_f
Color_4b :: util.Color_4b

Vertex :: struct { 
    pos: vec2,
    color: Color_f,
}

Vertex_uv :: struct { 
    pos: vec2,
    uv: vec2f,
}

Font :: rawptr

Font_Resource_Type :: enum {
    System,
    File,
}

Draw_Context :: struct {
    data: rawptr,
    using vtable: ^Draw_Context_VTable,
}

Draw_Context_VTable :: struct {
    push_clip_rect: proc(this: ^Draw_Context, rect: Rect),
    pop_clip_rect: proc(this: ^Draw_Context),
    begin_frame: proc(this: ^Draw_Context),
    end_frame: proc(this: ^Draw_Context),
    get_render_target_dpi: proc(this: ^Draw_Context) -> i32,
    get_render_target_size: proc(this: ^Draw_Context) -> vec2,
    measure_string: proc(this: ^Draw_Context, font: rawptr, text: string) -> vec2,
    push_command: proc(this: ^Draw_Context, command: Command),
    resize: proc(this: ^Draw_Context, size: vec2),
    create_font: proc(
        this: ^Draw_Context,
        name: string,
        size_dip: f32,
        type: Font_Resource_Type = .System
    ) -> Font,
    get_char_rect: proc(
        this: ^Draw_Context,
        font: Font,
        text: string,
        char_index: int) -> (Rect, bool),
}

color_4b_to_f :: proc(color: Color_4b) -> Color_f {
    return Color_f {
        cast(f32)color.r / 255.0,
        cast(f32)color.g / 255.0,
        cast(f32)color.b / 255.0,
        cast(f32)color.a / 255.0,
    }
}

color_f_to_4b :: proc(color: Color_f) -> Color_4b {
    return Color_4b {
        r=cast(u8)math.round(color.r * 255.0),
        g=cast(u8)math.round(color.g * 255.0),
        b=cast(u8)math.round(color.b * 255.0),
        a=cast(u8)math.round(color.a * 255.0),
    }
}

alpha_blend :: proc(top, bottom: Color_f) -> Color_f {
    one_minus_src_alpha := 1.0 - top.a
    final_c := top * top.a + bottom * one_minus_src_alpha
    final_c.a = 1.0
    return final_c
}

Pixmap :: util.Pixmap

import "core:slice"

_fill :: proc(pixmap: ^Pixmap, color: Color_f) {
    area := pixmap.w * pixmap.h
    pixels := cast([^]Color_f)pixmap.pixels

    slice.fill((cast([^]Color_4b)pixmap.pixels)[:area], color_f_to_4b(color))
}

_fill_rect :: proc(pixmap: ^Pixmap, r: Rect, color: Color_f) {
    if color.a <= 0 do return
    b := util.rect_to_bbox(r)
    x0, x1, y0, y1 := b.x0, b.x1, b.y0, b.y1 
    if pixmap.w == 0 || pixmap.h == 0 do return
    if x0 > x1 do x0, x1 = x1, x0
    if y0 > y1 do y0, y1 = y1, y0
    if x0 >= pixmap.w || y0 >= pixmap.h do return
    if x0 < 0 do x0 = 0
    if y0 < 0 do y0 = 0
    if x1 > pixmap.w do x1 = pixmap.w
    if y1 > pixmap.h do y1 = pixmap.h 

    pixels := cast([^]Color_4b)pixmap.pixels
    row := y0 * pixmap.w
    
    if color.a >= 1.0 {
        c_u8 := color_f_to_4b(color)
        for y in y0..<y1 {
            for x in x0..<x1 {
                pixels[row + x] = c_u8
            }
            row += pixmap.w
        }
    } else {
        one_minus_src_alpha := 1.0 - color.a
        src_b := color * color.a
        for y in y0..<y1 {
            for x in x0..<x1 {
                blended_c := src_b + color_4b_to_f(pixels[row+x]) * one_minus_src_alpha
                blended_c.a = 1.0
                pixels[row + x] = color_f_to_4b(blended_c)
            }
            row += pixmap.w
        }
    }
}
// load_pixmap :: proc(filename: cstring) -> (Pixmap, bool) {
//     w, h, channels: i32
//     pixels := stbi.load(filename, &w, &h, &channels, 4)
//     if pixels == nil {
//         return {}, false
//     }
//     area := int(w * h * 4)
//     for i := 0; i < area; i += 4 {
//         // Is this right?
//         pixels[i], pixels[i+2] = pixels[i+2], pixels[i]
//     }
//     return Pixmap { pixels=pixels, w=w, h=h, pitch=w*4 }, true
// }
//
// delete_pixmap :: proc(pixmap: ^Pixmap) {
//     mem.free(pixmap.pixels)
//     pixmap.pixels = nil
//     pixmap.w = 0
//     pixmap.h = 0
// }


// FIXME:
// stroke_rect :: proc(draw_context: ^Draw_Context, rect: Rect, color: Color_f, pixel_width: i32) {
//     if pixel_width == 0 do return
//     b := util.rect_to_bbox(rect)
//     x0, x1, y0, y1 := b.x0, b.x1, b.y0, b.y1 
//
//     // top
//     fill_rect(draw_context, util.bbox_to_rect({x0, y0 - pixel_width, x1, y0}), color)
//     // bottom
//     fill_rect(draw_context, util.bbox_to_rect({x0, y1, x1, y1 + pixel_width}), color)
//     // left
//     fill_rect(draw_context, util.bbox_to_rect(
//         {x0 - pixel_width, y0 - pixel_width, x0, y1 + pixel_width}
//     ), color)
//     // right
//     fill_rect(draw_context, util.bbox_to_rect(
//         {x1, y0 - pixel_width, x1 + pixel_width, y1 + pixel_width}
//     ), color)
// }
