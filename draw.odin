package main

import "odinlib:util"
import "core:mem"
import "core:math"
import fp "core:math/fixed"
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

Fixed :: fp.Fixed(i32, 18)
USE_ALPHA_BLEND :: false

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

// fast_blit_fp :: proc(
//     dst_pixmap, src_pixmap: Pixmap,
//     offset: vec2,
//     src_rect: Maybe(Rect) = nil,
//     dst_dims: Maybe(vec2) = nil,
//     clip_rect: Maybe(Rect) = nil,
//     flip: [2]bool = {false, false},
//     num_threads: int)
// {
//     n := dst_pixmap.h/cast(i32)num_threads
//     for i in 0..<num_threads-1 {
//         // Just testing it
//         // if i % 2 == 0 do continue
//         blit_fp(
//             dst_pixmap,
//             src_pixmap,
//             offset,
//             src_rect,
//             dst_dims,
//             Rect{0, (i32)(n*cast(i32)i), dst_pixmap.w, n},
//             flip,
//         )
//     }
// }

Blit_Info :: struct {
    dstb, srcb: util.BBox,
    src_start, src_inc: [2]Fixed,
}

// Abstracted away boilerplate code for blit routines
get_blit_info :: proc "contextless" (
    dst_pixmap, src_pixmap: Pixmap,
    offset: vec2,
    src_rect: Maybe(Rect),
    dst_dims: Maybe(vec2),
    clip_rect: Maybe(Rect),
    flip: [2]bool) -> (Blit_Info, bool) 
{
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
    src_inc_x, src_inc_y: Fixed
    fp.init_from_f64(&src_inc_x, (f64)(srcb.max.x - srcb.min.x) / (f64)(dstb.max.x - dstb.min.x))
    if flip.x {
        src_inc_x.i = -src_inc_x.i
    }
    fp.init_from_f64(&src_inc_y, (f64)(srcb.max.y - srcb.min.y) / (f64)(dstb.max.y - dstb.min.y))
    if flip.y {
        src_inc_y.i = -src_inc_y.i
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
        return {}, false
    }
    src_start_x, src_start_y: Fixed
    fp.init_from_parts(&src_start_y, srcb.max.y - 1 if flip.y else srcb.min.y, 0)
    fp.init_from_parts(&src_start_x, srcb.max.x - 1 if flip.x else srcb.min.x, 0)
    blit_info := Blit_Info {
        dstb=dstb,
        srcb=srcb,
        src_inc={src_inc_x, src_inc_y},
        src_start={src_start_x, src_start_y}
    }
    return blit_info, true
}

blit_fp :: proc(
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

    blit_info, blit_ok := get_blit_info(
        dst_pixmap,
        src_pixmap,
        offset,
        src_rect,
        dst_dims,
        clip_rect,
        flip
    )
    if !blit_ok do return

    dstb := blit_info.dstb
    srcb := blit_info.srcb
    sy := blit_info.src_start.y
    dst_ptr := mem.ptr_offset(cast([^]u8)dst_pixmap.pixels, dstb.min.y * dst_pixmap.pitch)
    src_ptr := mem.ptr_offset(
        cast([^]u8)src_pixmap.pixels,
        cast(i32)(sy.i >>  Fixed.Fraction_Width) * src_pixmap.pitch
    )

    for y := dstb.min.y; y < dstb.max.y; y += 1 {
        sx := blit_info.src_start.x
        sy_i := sy.i >> Fixed.Fraction_Width
        for x := dstb.min.x; x < dstb.max.x; x += 1 {
            sx_i := sx.i >> Fixed.Fraction_Width
            assert(sx_i >= srcb.min.x && sx_i < srcb.max.x)
            src_color_u32 := (cast([^]ColorU32)src_ptr)[cast(int)(sx.i >> Fixed.Fraction_Width)]
            when USE_ALPHA_BLEND {
                src_color_4f := util.unpack_color_4f(src_color_u32, src_pixmap.format)
                dst_color_4f := util.unpack_color_4f((cast([^]ColorU32)dst_ptr)[x], dst_pixmap.format)
                blended_color_4f := alpha_blend(src_color_4f, dst_color_4f)
                (cast([^]ColorU32)dst_ptr)[x] = util.pack_color(blended_color_4f, dst_pixmap.format)
            } else {
                (cast([^]ColorU32)dst_ptr)[x] = src_color_u32
            }
            sx = fp.add(sx, blit_info.src_inc.x)
        }
        sy = fp.add(sy, blit_info.src_inc.y)
        dst_ptr = mem.ptr_offset(dst_ptr, dst_pixmap.pitch)
        src_ptr = mem.ptr_offset(
            cast([^]u8)src_pixmap.pixels,
            (uintptr)(cast(i32)(sy.i >> Fixed.Fraction_Width) * src_pixmap.pitch)
        )
    }
}

blit_indexed_fp :: proc(
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

    blit_info, blit_ok := get_blit_info(
        dst_pixmap,
        src_pixmap,
        offset,
        src_rect,
        dst_dims,
        clip_rect,
        flip
    )
    if !blit_ok do return

    dstb := blit_info.dstb
    srcb := blit_info.srcb
    sy := blit_info.src_start.y
    dst_ptr := mem.ptr_offset(cast([^]u8)dst_pixmap.pixels, dstb.min.y * dst_pixmap.pitch)
    src_ptr := mem.ptr_offset(
        cast([^]u8)src_pixmap.pixels,
        cast(i32)(sy.i >>  Fixed.Fraction_Width) * src_pixmap.pitch
    )

    for y := dstb.min.y; y < dstb.max.y; y += 1 {
        sx := blit_info.src_start.x
        for x := dstb.min.x; x < dstb.max.x; x += 1 {
            final_sx := math.clamp(sx.i >> Fixed.Fraction_Width, blit_info.srcb.min.x, blit_info.srcb.max.x)
            color_idx := src_ptr[cast(int)(final_sx)] % len(palette^)
            if color_idx != 0 {
                (cast([^]ColorU32)dst_ptr)[x] = palette[color_idx]
            }
            sx = fp.add(sx, blit_info.src_inc.x)
        }
        sy = fp.add(sy, blit_info.src_inc.y)
        dst_ptr = mem.ptr_offset(dst_ptr, dst_pixmap.pitch)
        final_sy := math.clamp(sy.i >> Fixed.Fraction_Width, srcb.min.y, srcb.max.y - 1)
        src_ptr = mem.ptr_offset(cast([^]u8)src_pixmap.pixels, (uintptr)(final_sy * src_pixmap.pitch))
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
