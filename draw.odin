package main

import "odinlib:util"
import "core:slice"
import "core:math/linalg"
import "core:log"

Rect :: util.Rect
Color4f :: util.Color4f
ColorU32 :: util.ColorU32
Color4b :: util.Color4b
Pixmap :: util.Pixmap
pack_color :: util.pack_color
unpack_color_4f :: util.unpack_color_4f
unpack_color_4b :: util.unpack_color_4b


alpha_blend :: #force_inline proc "contextless" (top, bottom: Color4f) -> Color4f {
    one_minus_src_alpha := 1.0 - top.a
    final_c := top * top.a + bottom * one_minus_src_alpha
    final_c.a = 1.0
    return final_c
}

stroke_rect_f :: proc(pixmap: Pixmap, r: Rect, color: Color4f) {
    if color.a <= 0 do return
    b := util.rect_to_bbox(r)
    x0, x1, y0, y1 := b.x0, b.x1, b.y0, b.y1
    if pixmap.w == 0 || pixmap.h == 0 do return
    if x0 > x1 {
        x0, x1 = x1, x0
    }
    if y0 > y1 {
        y0, y1 = y1, y0
    }
    if x0 >= pixmap.w || y0 >= pixmap.h do return
    if x0 < 0 {
        x0 = 0
    }
    if y0 < 0 {
        y0 = 0
    }
    if x1 > pixmap.w {
        x1 = pixmap.w
    }
    if y1 > pixmap.h {
        y1 = pixmap.h
    }

    pixels := cast([^]ColorU32)pixmap.pixels
    row := y0 * pixmap.w

    one_minus_src_alpha := 1.0 - color.a
    src_b := color * color.a

    plot_pixel :: #force_inline proc "contextless" (
    	pixel: ^ColorU32,
        src_b: Color4f,
        one_minus_src_alpha: f32,
        pixel_format: util.Pixel_Format)
    {
        blended_c := src_b + unpack_color_4f(pixel^, pixel_format) * one_minus_src_alpha
        blended_c.a = 1.0
        pixel^ = pack_color(blended_c, pixel_format)
    }

    for y in y0..<y1 {
        plot_pixel(&pixels[row +  x0], src_b, one_minus_src_alpha, pixmap.pixel_format)
        plot_pixel(&pixels[row + x1 - 1], src_b, one_minus_src_alpha, pixmap.pixel_format)
        row += pixmap.w
        // log.debugf("LEFT: %v, RIGHT: %v", row, row + ((x1 - x0) - 1))
    }
    row = y0 * pixmap.w
    for x := x0 + 1; x < x1; x += 1 {
        plot_pixel(&pixels[y0 * pixmap.w + x], src_b, one_minus_src_alpha, pixmap.pixel_format)
        plot_pixel(&pixels[(y1 - 1) * pixmap.w + x], src_b, one_minus_src_alpha, pixmap.pixel_format)
    }
}

// TODO: replace off with dst_rect
// TODO: use integer scaling. currently sampling looks horrible!
blit_scaled :: proc(
    dst_pixmap, src_pixmap: Pixmap,
    off: vec2,
    _src_rect: Maybe(Rect) = nil,
    _dst_rect: Maybe(Rect) = nil) #no_bounds_check
{
	log.assertf(
		dst_pixmap.bytes_per_pixel == src_pixmap.bytes_per_pixel,
		"Dst bpp: %v, Src bpp: %v",
		dst_pixmap.bytes_per_pixel,
		src_pixmap.bytes_per_pixel
	)
	assert(dst_pixmap.pixel_format == src_pixmap.pixel_format)
	src_pixels := cast([^]ColorU32)src_pixmap.pixels
    dst_pixels := cast([^]ColorU32)dst_pixmap.pixels
    dst_min_x: i32 = off.x
    dst_max_x := off.x + src_pixmap.w
    dst_min_y: i32 = off.y
    dst_max_y := off.y + src_pixmap.h
    src_min_y: i32 = 0
    src_max_y := src_min_y + src_pixmap.h
    dst_rect := _dst_rect.?
    dst_min_x = off.x
    dst_max_x = off.x + cast(i32)dst_rect.w // src_pixmap.w
    dst_min_y = off.y
    dst_max_y = off.y + cast(i32)dst_rect.h // src_pixmap.h
    if src_rect, ok := _src_rect.?; ok {
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
    src_inc_x := (f32)(src_max_x - src_min_x) / (f32)(dst_max_x - dst_min_x)
    src_inc_y := (f32)(src_max_y - src_min_y) / (f32)(dst_max_y - dst_min_y)
    src_y := cast(f32)src_min_y
    for dst_y in dst_min_y..<dst_max_y {
        dst_x := dst_min_x
        src_x := cast(f32)src_min_x
        for dst_x in dst_min_x..<dst_max_x {
            // src_c := src_pixels[row_s + src_x]
            src_c := src_pixels[cast(i32)src_y * src_pixmap.w + cast(i32)src_x]
            src_alpha := (src_c >> src_pixmap.pixel_format.a) & 0xff
            if src_alpha == 255 {
                dst_pixels[row_d + dst_x] = src_c
            } else if src_alpha > 0 {
                dst_c := dst_pixels[row_d + dst_x]
                blended_c := alpha_blend(
                    unpack_color_4f(src_c, src_pixmap.pixel_format),
                    unpack_color_4f(dst_c, dst_pixmap.pixel_format)
                )
                dst_pixels[row_d + dst_x] = pack_color(blended_c, dst_pixmap.pixel_format)
            }
            src_x += src_inc_x
        }
        row_d += dst_pixmap.w
        src_y += src_inc_y
        // row_s += src_pixmap.w
    }
}

blit_indexed :: proc(
    dst_pixmap, src_pixmap: Pixmap,
    palette: ^Palette,
    off: vec2,
    _src_rect: Maybe(Rect) = nil,
    flip: [2]bool = {false, false}) #no_bounds_check
{
	assert(dst_pixmap.bytes_per_pixel == 4)
	assert(src_pixmap.bytes_per_pixel == 1)
	src_pixels := cast([^]u8)src_pixmap.pixels
    dst_pixels := cast([^]ColorU32)dst_pixmap.pixels
    dst_min_x: i32 = off.x
    dst_max_x := off.x + src_pixmap.w
    dst_min_y: i32 = off.y
    dst_max_y := off.y + src_pixmap.h
    src_min_y: i32 = 0
    src_max_y := src_min_y + src_pixmap.h
    src_min_x: i32 = 0
    src_max_x := src_pixmap.w
    if src_rect, ok := _src_rect.?; ok {
        src_min_x = cast(i32)src_rect.x
        src_max_x = cast(i32)(src_rect.x + src_rect.w)
        dst_max_x = cast(i32)(off.x + src_rect.w)
        src_min_y = cast(i32)src_rect.y
        src_max_y = cast(i32)(src_rect.y + src_rect.h)
        dst_max_y = cast(i32)(off.y + src_rect.h)
    }
    if off.y < 0 {
        dst_min_y = 0
        src_min_y = -off.y
    } else if dst_max_y > dst_pixmap.h {
        dst_max_y = dst_pixmap.h
        src_max_y = dst_max_y - off.y
    }

    if off.x < 0 {
        dst_min_x = 0
        src_min_x = -off.x
    } else if dst_max_x > dst_pixmap.w {
        dst_max_x = dst_pixmap.w
        src_max_x = dst_max_x - off.x
    }
    flip_offset_x := src_max_x - 1 if flip.x else src_min_x
    flip_sign_x: i32 = -1 if flip.x else 1
    flip_sign_y: i32 = -1 if flip.y else 1
    row_d := dst_min_y * dst_pixmap.w
    row_s := (src_max_y - 1 if flip.y else src_min_y) * src_pixmap.w
    for src_y in src_min_y..<src_max_y {
        dst_x := dst_min_x
        for src_x in 0..<(src_max_x-src_min_x) {
	       	src_xx := flip_offset_x + (src_x * flip_sign_x)
            src_c := src_pixels[row_s + src_xx]
            // NOTE: I don't know if I should take opacity into account if between 0 and 255
            src_4b := palette[src_c]
            if src_c != 0 && src_4b.a != 0 {
	            dst_pixels[row_d + dst_x] = util.pack_color_4b(src_4b, dst_pixmap.pixel_format)
            }
            dst_x += 1
        }
        row_d += dst_pixmap.w
        row_s += flip_sign_y * src_pixmap.w
    }
}

blit :: proc(
    dst_pixmap, src_pixmap: Pixmap,
    off: vec2,
    _src_rect: Maybe(Rect) = nil,
    flip: [2]bool = {false, false}) #no_bounds_check
{
	log.assertf(
		dst_pixmap.bytes_per_pixel == src_pixmap.bytes_per_pixel,
		"Dst bpp: %v, Src bpp: %v",
		dst_pixmap.bytes_per_pixel,
		src_pixmap.bytes_per_pixel
	)
	assert(dst_pixmap.pixels != nil)
	assert( dst_pixmap.pixel_format == src_pixmap.pixel_format )
	src_pixels := cast([^]ColorU32)src_pixmap.pixels
    dst_pixels := cast([^]ColorU32)dst_pixmap.pixels
    dst_min_x: i32 = off.x
    dst_max_x := off.x + src_pixmap.w
    dst_min_y: i32 = off.y
    dst_max_y := off.y + src_pixmap.h
    src_min_y: i32 = 0
    src_max_y := src_min_y + src_pixmap.h
    src_min_x: i32 = 0
    src_max_x := src_pixmap.w
    // if dst_rect, ok := _dst_rect.?; ok {
    //     // TODO:
    // }
    if src_rect, ok := _src_rect.?; ok {
        src_min_x = cast(i32)src_rect.x
        src_max_x = cast(i32)(src_rect.x + src_rect.w)
        dst_max_x = cast(i32)(off.x + src_rect.w)
        src_min_y = cast(i32)src_rect.y
        src_max_y = cast(i32)(src_rect.y + src_rect.h)
        dst_max_y = cast(i32)(off.y + src_rect.h)
    }
    // FIXME: Adjust if src_rect
    if off.y < 0 {
        dst_min_y = 0
        src_min_y = -off.y
    } else if dst_max_y > dst_pixmap.h {
        dst_max_y = dst_pixmap.h
        src_max_y = dst_max_y - off.y
    }

    if off.x < 0 {
        dst_min_x = 0
        src_min_x = -off.x
    } else if dst_max_x > dst_pixmap.w {
        dst_max_x = dst_pixmap.w
        src_max_x = dst_max_x - off.x
    }
    flip_offset_x := (src_max_x - 1) if flip.x else src_min_x
    flip_sign_x: i32 = -1 if flip.x else 1
    flip_sign_y: i32 = -1 if flip.y else 1
    row_d := dst_min_y * dst_pixmap.w
    row_s := (src_max_y - 1 if flip.y else src_min_y) * src_pixmap.w
    for src_y in src_min_y..<src_max_y {
        dst_x := dst_min_x
        for src_x in 0..<(src_max_x-src_min_x) {
	       	src_xx := flip_offset_x + (src_x * flip_sign_x)
            src_c := src_pixels[row_s + src_xx]
            src_alpha := (src_c >> src_pixmap.pixel_format.a) & 0xff
            if src_alpha == 255 {
                dst_pixels[row_d + dst_x] = src_c
            } else if src_alpha > 0 {
                dst_c := dst_pixels[row_d + dst_x]
                blended_c := alpha_blend(
                    unpack_color_4f(src_c,  src_pixmap.pixel_format),
                    unpack_color_4f(dst_c, dst_pixmap.pixel_format)
                )
                dst_pixels[row_d + dst_x] = pack_color(blended_c, dst_pixmap.pixel_format)
            }
            dst_x += 1
        }
        row_d += dst_pixmap.w
        row_s += flip_sign_y * src_pixmap.w
    }
}

fill_rect_f :: proc "contextless" (pixmap: Pixmap, r: Rect, color: Color4f) #no_bounds_check
{
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

    pixels := cast([^]ColorU32)pixmap.pixels
    row := y0 * pixmap.w

    one_minus_src_alpha := 1.0 - color.a
    src_b := color * color.a

    for y in y0..<y1 {
        for x in x0..<x1 {
            blended_c := src_b + unpack_color_4f(pixels[row+x], pixmap.pixel_format) * one_minus_src_alpha
            blended_c.a = 1.0
            pixels[row + x] = util.pack_color_4f(blended_c, pixmap.pixel_format)
        }
        row += pixmap.w
    }
}
