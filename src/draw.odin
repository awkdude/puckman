package src

import "odinlib:util"
import "core:slice"

Rect :: util.Rect
Color4f :: util.Color4f
Color4b :: util.Color4b
Pixmap :: util.Pixmap
color4b_to_4f :: util.color4b_to_4f
color4f_to_4b :: util.color4f_to_4b


alpha_blend :: proc "contextless" (top, bottom: Color4f) -> Color4f {
    one_minus_src_alpha := 1.0 - top.a
    final_c := top * top.a + bottom * one_minus_src_alpha
    final_c.a = 1.0
    return final_c
}

blit :: proc "contextless" (
    dst_pixmap, src_pixmap: Pixmap,
    off: vec2,
    dst_rect: ^Rect = nil,
    src_rect: ^Rect = nil)
{
    src_pixels := cast([^]Color4b)src_pixmap.pixels
    dst_pixels := cast([^]Color4b)dst_pixmap.pixels
    dst_min_x: i32 = off.x
    dst_max_x := off.x + src_pixmap.w
    dst_min_y: i32 = off.y
    dst_max_y := off.y + src_pixmap.h
    src_min_y: i32 = 0
    src_max_y := src_min_y + src_pixmap.h
    if dst_rect != nil {
        // TODO:
    }
    if src_rect != nil {
        // TODO:
    }
    if off.y < 0 {
        dst_min_y = 0
        src_min_y = -off.y
    } else if dst_max_y > dst_pixmap.h {
        dst_max_y = dst_pixmap.h
        src_max_y = dst_max_y - off.y
    }

    src_min_x: i32 = 0
    src_max_x := src_pixmap.w
    if off.x < 0 {
        dst_min_x = 0
        src_min_x = -off.x
    } else if dst_max_x > dst_pixmap.w {
        dst_max_x = dst_pixmap.w
        src_max_x = dst_max_x - off.x
    }

    row_d := dst_min_y * dst_pixmap.w
    row_s := src_min_y * src_pixmap.w
    for src_y in src_min_y..<src_max_y {
        dst_x := dst_min_x
        for src_x in src_min_x..<src_max_x {
            src_c := src_pixels[row_s + src_x]
            src_alpha := (src_c >> src_pixmap.pixel_format.a) & 0xff
            if src_alpha == 255 {
                dst_pixels[row_d + dst_x] = src_c
            } else if src_alpha > 0 {
                dst_c := dst_pixels[row_d + dst_x]
                blended_c := alpha_blend(color4b_to_4f(src_c), color4b_to_4f(dst_c))
                dst_pixels[row_d + dst_x] = color4f_to_4b(blended_c)
            }
            dst_x += 1
        }
        row_d += dst_pixmap.w
        row_s += src_pixmap.w
    }
}

pixmap_fill :: proc "contextless" (pixmap: Pixmap, color: Color4f) {
	coloru8 := color4f_to_4b(color)
	pixels := cast([^]Color4b)pixmap.pixels
	area := pixmap.w * pixmap.h
    slice.fill(pixels[:area], coloru8)
}

fill_rect :: proc "contextless" (pixmap: Pixmap, r: Rect, color: Color4f) {
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

    pixels := cast([^]Color4b)pixmap.pixels
    row := y0 * pixmap.w

    if color.a >= 1.0 {
        c_u8 := color4f_to_4b(color)
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
                blended_c := src_b + color4b_to_4f(pixels[row+x]) * one_minus_src_alpha
                blended_c.a = 1.0
                pixels[row + x] = color4f_to_4b(blended_c)
            }
            row += pixmap.w
        }
    }
}
