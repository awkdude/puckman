package main

import "core:c"
import "core:math"
import "core:log"
import "core:math/linalg"
import "odinlib:util"

Rectf :: util.Rectf

PERP :: util.PERP

white_texture_data := []ColorU32 {
	0xffffffff,
	0xffffffff,
	0xffffffff,
	0xffffffff,
}

WHITE_TEXTURE := Pixmap {
	pixels=raw_data(white_texture_data),
	w=2,
	h=2,
	pitch=8,
	bytes_per_pixel=4,
	pixel_format=util.DEFAULT_PIXEL_FORMAT,
}

// Queue of rendering commands
Render_Group :: struct {
    buffer: [dynamic; 1024]Render_Entry,
}

Render_Clear :: struct { color: Color4f }

Render_Fill_Rect :: struct {
    rect: Rectf,
    color: Color4f,
}

Render_Stroke_Rect :: struct {
	rect: Rectf,
	color: Color4f,
}

Render_Blit :: struct {
	texture: Pixmap,
    offset: vec2f,
    src_rect: Maybe(Rectf),
    flip: [2]bool,
    // color: color
}

Render_Blit_Scaled :: struct {
	texture: Pixmap,
	offset: vec2f,
	src_rect: Maybe(Rectf),
	dst_rect: Maybe(Rectf),
}

Render_Entry :: union {
    Render_Clear,
    Render_Fill_Rect,
    Render_Stroke_Rect,
    Render_Blit,
    Render_Blit_Scaled,
}

// Push render entry onto render group
render_group_push :: proc(rg: ^Render_Group, entry: Render_Entry) {
    append(&rg.buffer, entry)
}

inv_color :: proc(color: Color4f) -> Color4f {
	return Color4f {
		1.0-color.r,
		1.0-color.g,
		1.0-color.b,
		color.a,
	}
}

// Output render group to pixmap
render_group_to_output :: proc(rg: ^Render_Group, target_pixmap: Pixmap) {
    for entry in rg.buffer {
        switch cmd in entry {
        case Render_Clear:
            pixmap_fill(
                target_pixmap,
                cmd.color,
            )
        case Render_Blit:
            blit(
                target_pixmap,
                cmd.texture,
                cast(vec2)cmd.offset,
                cmd.src_rect,
                cmd.flip,
            )
        case Render_Blit_Scaled:
            blit_scaled(
                target_pixmap,
                cmd.texture,
                cast(vec2)cmd.offset,
                cmd.src_rect,
                cmd.dst_rect
            )
        case Render_Fill_Rect:
            fill_rect(target_pixmap, cmd.rect, cmd.color)
        case Render_Stroke_Rect:
            stroke_rect(target_pixmap, cmd.rect, cmd.color)
        }
    }
    clear(&rg.buffer)
}

render_clear :: proc(color: Color4f) {
    render_group_push(
        &game.render_group,
        Render_Clear {
            color=color,
        }
    )
}

render_blit :: proc(
    texture: Pixmap,
    offset: vec2f = {0, 0},
    src_rect: Maybe(Rectf) = nil,
    flip: [2]bool = {false, false})
{
	if texture.pixels == nil do return
    render_group_push(
        &game.render_group,
        Render_Blit {
            texture=texture,
            offset=offset,
            src_rect=src_rect,
            flip=flip,
        }
    )
}

render_blit_scaled :: proc(
    texture: Pixmap,
    offset: vec2f = {0, 0},
    src_rect: Maybe(Rectf) = nil,
    dst_rect: Maybe(Rectf) = nil)
{
    render_group_push(
        &game.render_group,
        Render_Blit_Scaled {
            texture=texture,
            offset=offset,
            src_rect=src_rect,
            dst_rect=dst_rect,
        }
    )
}

render_stroke_rect :: proc(rect: Rectf, color: Color4f) {
    render_group_push(
        &game.render_group,
        Render_Stroke_Rect {
            rect=rect,
            color=color,
        }
    )
}

stroke_rect :: proc(pixmap: Pixmap, r: Rectf, color: Color4f) {
    if color.a <= 0 do return
    r := util.rect_from_f(r)
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

    plot_pixel :: #force_inline proc "contextless" (pixel: ^ColorU32,
        src_b: Color4f,
        one_minus_src_alpha: f32,
        pixel_format: util.Pixel_Format)
    {
        blended_c := src_b + unpack_color_4f(pixel^, pixel_format) * one_minus_src_alpha
        blended_c.a = 1.0
        pixel^ = pack_color(blended_c, pixel_format)
    }

    log.debugf("HERE")
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

// Won't be needing this
// new_draw :: proc(
// 	pixmap: Pixmap,
// 	origin, basis_x, basis_y: vec2f,
// 	color: Color4f,
// 	_texture: Maybe(Pixmap) = nil,
// 	_src_rect: Maybe(Rectf) = nil) #no_bounds_check
// {
// 	texture: Pixmap
// 	if tex, ok := _texture.?; ok {
// 		texture = tex
// 	} else {
// 		texture = WHITE_TEXTURE
// 		texture.pixel_format = pixmap.pixel_format
// 	}
// 	src_rect: Rectf
// 	if r, ok := _src_rect.?; ok {
// 		src_rect = r
// 	} else {
// 		src_rect = Rectf{0, 0, cast(f32)texture.w, cast(f32)texture.h}
// 	}
// 	c_u32 := pack_color(color, pixmap.pixel_format)
// 	pixels := cast([^]ColorU32)pixmap.pixels
// 	v0 := origin
// 	v1 := origin + basis_y
// 	v2 := origin + basis_x + basis_y
// 	v3 := origin + basis_x
// 	p_min_x := cast(i32)min(v0.x, v1.x, v2.x, v3.x)
// 	p_min_y := cast(i32)min(v0.y, v1.y, v2.y, v3.y)
// 	p_max_x := cast(i32)max(v0.x, v1.x, v2.x, v3.x)
// 	p_max_y := cast(i32)max(v0.y, v1.y, v2.y, v3.y)
// 	p_min_x = max(p_min_x, 0)
// 	p_min_y = max(p_min_y, 0)
// 	if p_min_x >= pixmap.w || p_min_y >= pixmap.h {
// 		return
// 	}
// 	p_max_x = min(p_max_x, pixmap.w)
// 	p_max_y = min(p_max_y, pixmap.h)
// 	if p_max_x < 0 || p_max_y < 0 {
// 		return
// 	}
// 	// Basically determines if "sign" of quad winding order
// 	// NOTE: Shoelace formula: Need to actually understand
// 	sign := -math.sign(
// 		(v0.x * v1.y - v0.y * v1.x) +
// 	 	(v1.x * v2.y - v2.y * v2.x) +
// 		(v2.x * v3.y - v2.y * v3.x) +
// 	 	(v3.x * v0.y - v3.y * v0.x)
// 	)
// 	v_min := origin
// 	v_max := origin + basis_x + basis_y
// 	inv_x_length_sq := 1.0 / linalg.length2(basis_x)
// 	inv_y_length_sq := 1.0 / linalg.length2(basis_y)
// 	for y := p_min_y; y < p_max_y; y += 1 {
// 		row_fill_count := 0
// 		for x := p_min_x; x < p_max_x; x += 1 {
// 			color := color
// 			p := cast(vec2f) vec2{x, y}
// 			dp := p - origin
// 			// e0 := sign * linalg.dot(dp, -perp(basis_x))
// 			// e1 := sign * linalg.dot(dp - basis_x, -perp(basis_y))
// 			// e2 := sign * linalg.dot(dp - basis_x - basis_y, perp(basis_x))
// 			// e3 := sign * linalg.dot(dp - basis_y, perp(basis_y))
// 			when false {
// 				e0 := sign * linalg.dot(dp, -(PERP * basis_x))
// 				e1 := sign * linalg.dot(dp - basis_x, -(PERP * basis_y))
// 				e2 := sign * linalg.dot(dp - basis_x - basis_y, PERP * basis_x)
// 				e3 := sign * linalg.dot(dp - basis_y, PERP * basis_y)
// 				cond := e0 < 0 && e1 < 0 && e2 < 0 && e3 < 0
// 			} else {
// 				cond := true
// 			}
// 			if cond {
// 				dst_c := unpack_color_4f(pixels[y * pixmap.w + x], pixmap.pixel_format)
// 				// NOTE: may need to clamp
// 				tex_x := cast(i32)(src_rect.x + linalg.dot(dp, basis_x) * inv_x_length_sq * (cast(f32)src_rect.w - 1))
// 				tex_y := cast(i32)(src_rect.y + linalg.dot(dp, basis_y) * inv_y_length_sq * (cast(f32)src_rect.h - 1))
// 				tex_pixels := cast([^]ColorU32)texture.pixels
// 				tex_sample := unpack_color_4f(
//                     tex_pixels[tex_y * texture.w + tex_x],
//                     texture.pixel_format
//                 )
// 				color *= tex_sample
// 				blended_c := alpha_blend(color, dst_c)
// 				pixels[y * pixmap.w + x] = pack_color(blended_c, pixmap.pixel_format)
// 				row_fill_count += 1
// 			} else{
// 				if row_fill_count > 0 {
//                     break
// 				}
// 			}
// 		}
// 	}
// }
