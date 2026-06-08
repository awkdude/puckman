package main

import "core:c"
import "core:math"
import "core:math/linalg"
import "odinlib:util"

Rectf :: util.Rectf

perp :: util.perp

// Queue of rendering commands
Render_Group :: struct {
	coord_system: Render_Coord_System,
    buffer: [dynamic; 1024]Render_Entry,
}

Render_Clear :: Color4f

Render_Fill_Rect :: struct {
    rect: Rectf,
    color: Color4f,
}

Render_Stroke_Rect :: struct {
	rect: Rectf,
	color: Color4f,
	line_width: f32,
}

Render_Line:: struct {
	start, end: vec2f,
	line_width: f32,
	color: Color4f,
}

Render_Pixmap :: struct {
    pixmap: Pixmap,
    offset: vec2f,
    dst_rect, src_rect: ^Rectf,
}

Render_Coord_System :: struct {
    origin, basis_x, basis_y: vec2f,
    color: Color4f,
    texture: Maybe(Pixmap),
}

Render_Entry :: union {
    Render_Clear,
    Render_Fill_Rect,
    Render_Stroke_Rect,
    Render_Line,
    Render_Pixmap,
    Render_Coord_System,
}

// Push render entry onto render group
render_group_push :: proc(rg: ^Render_Group, entry: Render_Entry) {
	if rg.coord_system == cast(Render_Coord_System){} {
		rg.coord_system = Render_Coord_System {
			origin={0, 0},
			basis_x={1,0},
			basis_y={0,1},
			color=color_white,
		}
	}
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
                cmd
            )
        case Render_Fill_Rect:
            fill_rect(target_pixmap, cmd.rect, cmd.color)
        case Render_Stroke_Rect:
        // TODO:
        case Render_Line:
	        new_draw(target_pixmap, cmd.start, cmd.end - cmd.start, cmd.line_width, cmd.color)
        // TODO:
        case Render_Pixmap:
	        blit(
                target_pixmap,
                cmd.pixmap,
                cast(vec2)cmd.offset,
                cmd.dst_rect,
                cmd.src_rect,
            )
        case Render_Coord_System:
        	i_color := inv_color(cmd.color)
        	new_draw(
         		target_pixmap,
           		cmd.origin, // * (rg.coord_system.basis_x + rg.coord_system.basis_y),
             	cmd.basis_x,
              	cmd.basis_y,
               	cmd.color,
                cmd.texture
	         )
        	p := cmd.origin
      		fill_rect(target_pixmap, {p.x, p.y, 5, 5}, i_color)
        	p = cmd.origin + cmd.basis_x
            fill_rect(target_pixmap, {p.x, p.y, 5, 5}, i_color)
	       	p = cmd.origin + cmd.basis_y
      		fill_rect(target_pixmap, {p.x, p.y, 5, 5}, i_color)
	        p = cmd.origin + cmd.basis_x + cmd.basis_y
     		fill_rect(target_pixmap, {p.x, p.y, 5, 5}, i_color)
        	rg.coord_system = cmd
        }
    }
    clear(&rg.buffer)
}

new_draw :: proc(
	pixmap: Pixmap,
	origin, basis_x, basis_y: vec2f,
	color: Color4f,
	texture: Pixmap)
{
	c_u32 := pack_color(color, pixmap.pixel_format)
	pixels := cast([^]ColorU32)pixmap.pixels
	v0 := origin
	v1 := origin + basis_x
	v2 := origin + basis_y
	v3 := origin + basis_x + basis_y
	p_min_x := cast(i32)min(v0.x, v1.x, v2.x, v3.x)
	p_min_y := cast(i32)min(v0.y, v1.y, v2.y, v3.y)
	p_max_x := cast(i32)max(v0.x, v1.x, v2.x, v3.x)
	p_max_y := cast(i32)max(v0.y, v1.y, v2.y, v3.y)
	p_min_x = max(p_min_x, 0)
	p_min_y = max(p_min_y, 0)
	if p_min_x >= pixmap.w || p_min_y >= pixmap.h {
		return
	}
	p_max_x = min(p_max_x, pixmap.w)
	p_max_y = min(p_max_y, pixmap.h)
	if p_max_x < 0 || p_max_y < 0 {
		return
	}

	v_min := origin
	v_max := origin + basis_x + basis_y
	inv_x_length_sq := 1.0 / linalg.length2(basis_x)
	inv_y_length_sq := 1.0 / linalg.length2(basis_y)
	for y := p_min_y; y < p_max_y; y += 1 {
		row_fill_count := 0
		for x := p_min_x; x < p_max_x; x += 1 {
			color := color
			p := cast(vec2f) vec2{x, y}
			dp := p - origin
			e0 := linalg.dot(dp, -perp(basis_x))
			e1 := linalg.dot(dp - basis_x, -perp(basis_y))
			e2 := linalg.dot(dp - basis_x - basis_y, perp(basis_x))
			e3 := linalg.dot(dp - basis_y, perp(basis_y))
			if e0 < 0 && e1 < 0 && e2 < 0 && e3 < 0 {
				dst_c := unpack_color_4f(pixels[y * pixmap.w + x], pixmap.pixel_format)
				// NOTE: may need to clamp
				tex_x := cast(i32)(linalg.dot(dp, basis_x) * inv_x_length_sq * (cast(f32)texture.w - 1))
				tex_y := cast(i32)(linalg.dot(dp, basis_y) * inv_y_length_sq * (cast(f32)texture.h - 1))
				tex_pixels := cast([^]ColorU32)texture.pixels
				tex_sample := unpack_color_4f(tex_pixels[tex_y * texture.w + tex_x], texture.pixel_format)
				color *= tex_sample
				blended_c := alpha_blend(color, dst_c)
				pixels[y * pixmap.w + x] = pack_color(blended_c, pixmap.pixel_format)
				row_fill_count += 1
			} else if row_fill_count > 0 {
				break
			}
		}
	}
}
