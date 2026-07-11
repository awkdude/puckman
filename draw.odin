package main

import "odinlib:util"
import "core:mem"
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

inv_color_4b :: #force_inline proc "contextless" (color: Color4b) -> Color4b {
	return {255 - color.r, 255 - color.g, 255 - color.b, color.a}
}

inv_color_4f :: #force_inline proc "contextless" (color: Color4f) -> Color4f {
	return {1.0 - color.r, 1.0 - color.g, 1.0 - color.b, color.a}
}

inv_color :: proc {
	inv_color_4b,
	inv_color_4f,
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
        plot_pixel(&pixels[row +  x0], src_b, one_minus_src_alpha, pixmap.format)
        plot_pixel(&pixels[row + x1 - 1], src_b, one_minus_src_alpha, pixmap.format)
        row += pixmap.w
        // log.debugf("LEFT: %v, RIGHT: %v", row, row + ((x1 - x0) - 1))
    }
    row = y0 * pixmap.w
    for x := x0 + 1; x < x1; x += 1 {
        plot_pixel(&pixels[y0 * pixmap.w + x], src_b, one_minus_src_alpha, pixmap.format)
        plot_pixel(&pixels[(y1 - 1) * pixmap.w + x], src_b, one_minus_src_alpha, pixmap.format)
    }
}

// FIXME: off by 1 error when flip y
// TODO: dup to blit when fixed
blit_indexed :: proc(
    palette: ^Palette,
    dst_pixmap, src_pixmap: Pixmap,
    offset: vec2,
    src_rect: Maybe(Rect) = nil,
    dst_dims: Maybe(vec2) = nil,
    clip_rect: Maybe(Rect) = nil,
    flip: [2]bool = {false, false})
{
    assert(dst_pixmap.pitch != 0)
    assert(src_pixmap.pitch != 0)
    assert(dst_pixmap.format.bytes_per_pixel == 4)
    assert(src_pixmap.format.bytes_per_pixel == 1)
    dstb, srcb: util.BBox
    src_rect, src_rect_ok := src_rect.?
    if src_rect_ok {
        srcb = util.rect_to_bbox(src_rect)
        srcb.min.x = max(0, src_rect.x)
        srcb.max.x = min(srcb.max.x, src_pixmap.w)
        srcb.min.y = max(0, src_rect.y)
        srcb.max.y = min(srcb.max.y, src_pixmap.h)
    } else {
        srcb = util.rect_to_bbox(Rect{0, 0, src_pixmap.w, src_pixmap.h})
    }
    if dst_dims, ok := dst_dims.?; ok {
        dstb = util.rect_to_bbox(Rect{offset.x, offset.y, dst_dims.x, dst_dims.y})
    } else {
        dstb = util.rect_to_bbox(Rect{offset.x, offset.y, srcb.max.x - srcb.min.x, srcb.max.y - srcb.min.y})
    }
    // get src inc before clamping dst bbox
    src_inc_x: f32 = (f32)(srcb.max.x - srcb.min.x) / (f32)(dstb.max.x - dstb.min.x)
    if flip.x {
        src_inc_x = -src_inc_x
    }
    src_inc_y: f32 = (f32)(srcb.max.y - srcb.min.y) / (f32)(dstb.max.y - dstb.min.y)
    if flip.y {
        src_inc_y = -src_inc_y
    }
    clip_rect := clip_rect.? or_else Rect{0, 0, dst_pixmap.w, dst_pixmap.h}
    clip_box := util.rect_to_bbox(clip_rect)
    if dstb.min.x < clip_box.min.x {
        if flip.x {
            srcb.max.x -= (clip_box.min.x - dstb.min.x)
        } else {
            srcb.min.x += (clip_box.min.x - dstb.min.x)
        }
    }
    if dstb.min.y < clip_box.min.y {
        if flip.y {
            srcb.max.y -= (clip_box.min.y - dstb.min.y)
        } else {
            srcb.min.y += (clip_box.min.y - dstb.min.y)
        }
    }
    dstb = util.intersection_bbox(dstb, clip_box)
    // Return if clip rect and dst rect don't intersect
    if dstb.max.x < dstb.min.x || dstb.max.y < dstb.min.y {
        return
    }
    sy: f32 = cast(f32)srcb.max.y - 1 if flip.y else cast(f32)srcb.min.y

    dst_ptr := mem.ptr_offset(cast([^]u8)dst_pixmap.pixels, dstb.min.y * dst_pixmap.pitch)
    src_ptr := mem.ptr_offset(cast([^]u8)src_pixmap.pixels, srcb.min.y * src_pixmap.pitch)
    src_start_x := cast(f32)srcb.max.x - 1 if flip.x else cast(f32)srcb.min.x

    for y := dstb.min.y; y < dstb.max.y; y += 1 {
        sx := src_start_x
        for x := dstb.min.x; x < dstb.max.x; x += 1 {
            color_idx := src_ptr[cast(int)sx]
            if color_idx != 0 {
                (cast([^]ColorU32)dst_ptr)[x] = palette[color_idx]
            }
            sx += src_inc_x
        }
        sy += src_inc_y
        dst_ptr = mem.ptr_offset(dst_ptr, dst_pixmap.pitch)
        src_ptr = mem.ptr_offset(cast([^]u8)src_pixmap.pixels, (uintptr)(cast(i32)sy * src_pixmap.pitch))
    }
}

blit :: proc(
    dst_pixmap, src_pixmap: Pixmap,
    offset: vec2,
    src_rect: Maybe(Rect) = nil,
    dst_dims: Maybe(vec2) = nil,
    clip_rect: Maybe(Rect) = nil,
    flip: [2]bool = {false, false})
{
    assert(dst_pixmap.pitch != 0)
    assert(src_pixmap.pitch != 0)
    assert(dst_pixmap.format == src_pixmap.format)
    dstb, srcb: util.BBox
    if dst_dims, ok := dst_dims.?; ok {
        dstb = util.rect_to_bbox(Rect{offset.x, offset.y, dst_dims.x, dst_dims.y})
    } else {
        dstb = util.rect_to_bbox(Rect{offset.x, offset.y, src_pixmap.w, src_pixmap.h})
    }
    if src_rect, ok := src_rect.?; ok {
        srcb = util.rect_to_bbox(src_rect)
        srcb.min.x = max(0, src_rect.x)
        srcb.max.x = min(srcb.max.x, src_pixmap.w)
        srcb.min.y = max(0, src_rect.y)
        srcb.max.y = min(srcb.max.y, src_pixmap.h)
    } else {
        srcb = util.rect_to_bbox(Rect{0, 0, src_pixmap.w, src_pixmap.h})
    }
    // get src inc before clamping dst bbox
    src_inc_x: f32 = (f32)(srcb.max.x - srcb.min.x) / (f32)(dstb.max.x - dstb.min.x)
    if flip.x {
        src_inc_x = -src_inc_x
    }
    src_inc_y: f32 = (f32)(srcb.max.y - srcb.min.y) / (f32)(dstb.max.y - dstb.min.y)
    if flip.y {
        src_inc_y = -src_inc_y
    }
    dstb.min.x = max(dstb.min.x, 0)
    dstb.max.x = min(dstb.max.x, dst_pixmap.w)
    dstb.min.y = max(dstb.min.y, 0)
    dstb.max.y = min(dstb.max.y, dst_pixmap.h)
    if clip_rect, ok := clip_rect.?; ok {
        clip_box := util.rect_to_bbox(clip_rect)
        if dstb.min.x < clip_box.min.x {
            if flip.x {
                srcb.max.x -= (clip_box.min.x - dstb.min.x)
            } else {
                srcb.min.x += (clip_box.min.x - dstb.min.x)
            }
        }
        if dstb.min.y < clip_box.min.y {
            if flip.y {
                srcb.max.y -= (clip_box.min.y - dstb.min.y)
            } else {
                srcb.min.y += (clip_box.min.y - dstb.min.y)
            }
        }
        dstb = util.intersection_bbox(dstb, clip_box)
        // Return if clip rect and dst rect don't intersect
        if dstb.max.x < dstb.min.x || dstb.max.y < dstb.min.y {
            return
        }
    }
    sy: f32 = cast(f32)srcb.max.y - 1 if flip.y else cast(f32)srcb.min.y

    dst_ptr := mem.ptr_offset(cast([^]u8)dst_pixmap.pixels, dstb.min.y * dst_pixmap.pitch)
    src_ptr := mem.ptr_offset(cast([^]u8)src_pixmap.pixels, srcb.min.y * src_pixmap.pitch)
    src_start_x := cast(f32)srcb.max.x - 1 if flip.x else cast(f32)srcb.min.x

    for y := dstb.min.y; y < dstb.max.y; y += 1 {
        sx := src_start_x
        for x := dstb.min.x; x < dstb.max.x; x += 1 {
            // TODO: alpha blending
            (cast([^]ColorU32)dst_ptr)[x] = (cast([^]ColorU32)src_ptr)[cast(int)sx]
            sx += src_inc_x
        }
        sy += src_inc_y
        dst_ptr = mem.ptr_offset(dst_ptr, dst_pixmap.pitch)
        src_ptr = mem.ptr_offset(cast([^]u8)src_pixmap.pixels, (uintptr)(cast(i32)sy * src_pixmap.pitch))
    }
}


// TODO: rename
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
            blended_c := src_b + unpack_color_4f(pixels[row+x], pixmap.format) * one_minus_src_alpha
            blended_c.a = 1.0
            pixels[row + x] = util.pack_color_4f(blended_c, pixmap.format)
        }
        row += pixmap.w
    }
}
