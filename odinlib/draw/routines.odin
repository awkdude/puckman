#+build !windows
#+build !linux
package draw

import "core:mem"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:os"
import "core:log"
import stbtt "vendor:stb/truetype"
import stbi "vendor:stb/image"
import "../util"

vec2   :: util.vec2
Rect   :: util.Rect
BBox :: util.BBox
Color_f  :: util.Color_f
Color_4b :: util.Color_4b

stroke_line :: proc(pixmap: ^Pixmap, pt0, pt1: vec2, pixel_width: i32, color: Color_f) {
    x0 := math.clamp(pt0.x, 0, pixmap.w - 1)
    y0 := math.clamp(pt0.y, 0, pixmap.h - 1)
    x1 := math.clamp(pt1.x, 0, pixmap.w - 1)
    y1 := math.clamp(pt1.y, 0, pixmap.h - 1)

    if x0 == x1 || y0 == y1 {
        half_thick := pixel_width / 2
        _fill_rect(
            pixmap, 
            util.bbox_to_rect(
                BBox{
                    x0 - half_thick,
                    y0 - half_thick,
                    x1 + half_thick,
                    y1 + half_thick
                }
            ),
            color
        )
        return
    }

    dx := math.abs(x1 - x0)
    sx: i32 = 1 if (x0 < x1) else -1
    dy := -math.abs(y1 - y0)
    sy: i32 = (1 if (y0 < y1) else -1) * pixmap.w
    error := dx + dy

    // TODO: needs pixel_width
    pixels := cast([^]Color_4b)pixmap.pixels
    c_u8 := color_f_to_4b(color)
    row0 := y0 * pixmap.w
    row1 := y1 * pixmap.w
    for {
        pixels[row0 + x0] = c_u8
        if x0 == x1 && row0 == row1 do break
        e2 := 2 * error
        if e2 >= dy {
            if x0 == x1 do break
            error += dy
            x0 += sx
        }
        if e2 <= dx {
            if row0 == row1 do break
            error += dx
            row0 += sy
        }
    }
}

_fill :: proc(pixmap: ^Pixmap, color: Color_f) {
    area := pixmap.w * pixmap.h
    pixels := cast([^]Color_f)pixmap.pixels

    slice.fill((cast([^]Color_4b)pixmap.pixels)[:area], color_f_to_4b(color))
}


// Uses nearest-neighbor
strech_blit :: proc(dst_pixmap, src_pixmap: ^Pixmap, off: vec2, target_size: vec2) {
    // TODO:
}

_blit :: proc(
    dst_pixmap, src_pixmap: ^Pixmap,
    off: vec2,
    dst_rect: ^Rect = nil, 
    src_rect: ^Rect = nil) 
{
    src_pixels := cast([^]Color_4b)src_pixmap.pixels
    dst_pixels := cast([^]Color_4b)dst_pixmap.pixels
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
            if src_c.a == 255 {
                dst_pixels[row_d + dst_x] = src_c
            } else if src_c.a > 0 {
                dst_c := dst_pixels[row_d + dst_x]
                blended_c := alpha_blend(color_4b_to_f(src_c), color_4b_to_f(dst_c))
                dst_pixels[row_d + dst_x] = color_f_to_4b(blended_c)
            } 
            dst_x += 1
        }
        row_d += dst_pixmap.w
        row_s += src_pixmap.w
    }
}

_blit_pixmap_mono_to_truecolor :: proc(
    dst_pixmap,
    src_pixmap: ^Pixmap,
    off: vec2,
    color: Color_f, 
    src_rect: Maybe(Rect)=nil)
{
    src_pixels := cast([^]u8)src_pixmap.pixels
    dst_pixels := cast([^]Color_4b)dst_pixmap.pixels
    dst_min_x: i32 = off.x
    dst_max_x := off.x + src_pixmap.w
    dst_min_y: i32 = off.y
    dst_max_y := off.y + src_pixmap.h
    src_min_y: i32 = 0
    src_max_y := src_min_y + src_pixmap.h
    // if dst_rect != nil {
    //     // TODO:
    // }
    // if src_rect != nil {
    //     // TODO:
    // }
    if off.y < 0 {
        dst_min_y = 0
        src_min_y = -off.y
    } else if dst_max_y > dst_pixmap.h {
        dst_max_y = dst_pixmap.h
        src_max_y = dst_max_y - off.y
    }

    src_min_x: i32 = 0
    src_max_x := src_pixmap.w
    if src_rect, ok := src_rect.?; ok {
        src_min_x = src_rect.x
        src_max_x = src_rect.x + src_rect.w
        src_min_y = src_rect.y
        src_max_y = src_rect.y + src_rect.h
    }
    if off.x < 0 {
        dst_min_x = 0
        src_min_x = -off.x
    } else if dst_max_x > dst_pixmap.w {
        dst_max_x = dst_pixmap.w
        src_max_x = dst_max_x - off.x
    }

    row_d := dst_min_y * dst_pixmap.w
    row_s := src_min_y * src_pixmap.w
    c_u8 := color_f_to_4b(color)
    for src_y in src_min_y..<src_max_y {
        dst_x := dst_min_x 
        for src_x in src_min_x..<src_max_x {
            src_c := src_pixels[row_s + src_x]
            final_4b := c_u8
            if src_c > 0 && src_c < 0xff {
                // dst_pixels[row_d + dst_x] = c_u8
                dst_c := dst_pixels[row_d + dst_x]
                src_color_f := Color_f{color.r, color.g, color.b, cast(f32)src_c / 255.0}
                blended_c := alpha_blend(src_color_f, color_4b_to_f(dst_c))
                final_4b = color_f_to_4b(blended_c)
            }  
            // FIXME:
            if (row_d / dst_pixmap.w) > dst_pixmap.h {
                break
            }
            dst_pixels[row_d + dst_x] = final_4b
            dst_x += 1
        }
        row_d += dst_pixmap.w
        row_s += src_pixmap.w
    }
}

fill_circle :: proc(pixmap: ^Pixmap, pos: vec2, r: i32, color: Color_f) {
    if color.a <= 0 do return
    x0, x1, y0, y1 := pos.x - r, pos.x + r, pos.y - r, pos.y + r 
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
    
    r_sq := r * r
    if color.a >= 1.0 {
        c_u8 := color_f_to_4b(color)
        for y in y0..<y1 {
            ry := y - pos.y
            ry_sq := ry * ry
            for x in x0..<x1 {
                rx := x - pos.x
                if rx * rx + ry_sq < r_sq do pixels[row + x] = c_u8
            }
            row += pixmap.w
        }
    } else {
        one_minus_src_alpha := 1.0 - color.a
        src_b := color * color.a
        for y in y0..<y1 {
            ry := y - pos.y
            ry_sq := ry * ry
            for x in x0..<x1 {
                rx := x - pos.x
                if rx * rx + ry_sq < r_sq {
                    blended_c := src_b + color_4b_to_f(pixels[row+x]) * one_minus_src_alpha
                    blended_c.a = 1.0
                    pixels[row + x] = color_f_to_4b(blended_c)
                }
            }
            row += pixmap.w
        }
    }
}

_fill_rect_centered :: proc(pixmap: ^Pixmap, r: Rect, color: Color_f) {
    _fill_rect(pixmap, {r.x - r.w / 2, r.y - r.h / 2, r.w, r.h}, color)
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
