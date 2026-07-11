package main

import "core:c"
import "core:math"
import "core:log"
import "core:math/linalg"
import "core:slice"
import "odinlib:util"
import "base:runtime"
import "base:intrinsics"

Rectf :: util.Rectf

Palette :: [32]ColorU32

// NOTE: Concern that Palette makes each entry 128 bytes

white_texture_data := []ColorU32 {
	0xffffffff,
	0xffffffff,
	0xffffffff,
	0xffffffff,
}

real_framebuffer_ptr: rawptr
pacman_ptr: rawptr

// Queue of rendering commands
Render_Group :: struct {
    // buffer: [1024*1024]u8,
    // len: int,
    texture: Pixmap,
    buffer: [dynamic; 2048]RG_Entry,
    palette: Palette,
}

RG_Clear :: struct #align(4) {
	color: Color4b,
}

rg_clear :: proc(color: Color4b, loc := #caller_location) {
	entry := RG_Entry{
		type=.Clear,
		data={
			clear=RG_Clear{color=color},
		},
		loc=loc,
	}
	rg_push(entry, loc)
}

RG_Rect :: struct #align(4) {
	rect: Rect,
	color: Color4b,
}

rg_stroke_rect :: proc(rect: Rect, color: Color4b, loc := #caller_location) {
	entry := RG_Entry {
		type=.Stroke_Rect,
		data={
			rect=RG_Rect{
				rect=rect,
				color=color,
			}
		}
	}
	rg_push(entry, loc)
}

rg_fill_rect :: proc(rect: Rect, color: Color4b, loc := #caller_location) {
	entry := RG_Entry {
		type=.Fill_Rect,
		data={
			rect=RG_Rect{
				rect=rect,
				color=color,
			}
		}
	}
	rg_push(entry, loc)
}

Blit_Flag :: enum {
	Src_Rect,
	Dst_Rect,
	Flip_X,
	Flip_Y,
}

Blit_Flags :: bit_set[Blit_Flag]

Rect_i16 :: struct {
	x, y, w, h: i16,
}

// TODO: Use smaller data types
RG_Blit :: struct #align(4) {
	offset: vec2,
    src_rect : Maybe(Rect),
    dst_dims: Maybe(vec2),
    clip_rect: Maybe(Rect),
    flip: [2]bool,
    // TODO:
    // offset: [2]i16,
    // src_rect, dst_rect: Rect_i16,
    // flags: Blit_Flags,
}

rg_blit :: proc(
	offset: vec2,
	src_rect: Maybe(Rect) = nil,
	flip: [2]bool = {},
    dst_dims: Maybe(vec2) = nil,
    clip_rect: Maybe(Rect) = nil,
	loc := #caller_location)
{
	entry := RG_Entry{
		type=.Blit,
		blit=RG_Blit {
	    	offset=offset,
	    	src_rect=src_rect,
            dst_dims=dst_dims,
            clip_rect=clip_rect,
	    	flip=flip,
		}
	}
	rg_push(entry, loc)
}

RG_Palette :: struct #align(4) {
	idx: i32,
	color: Color4b,
}

rg_palette :: proc(idx: i32, color: Color4b, loc := #caller_location) {
	entry := RG_Entry{type=.Palette, palette=RG_Palette{idx=idx, color=color}}
	rg_push(entry, loc)
}

RG_Texture :: struct #align(4) {
	texture: Pixmap,
}

rg_texture :: proc(texture: Pixmap, loc := #caller_location) {
	entry := RG_Entry{ type=.Texture, texture=RG_Texture{texture=texture}}
	rg_push(entry, loc)
}

RG_Grid :: struct {
	rect: Rect,
	cell_size: vec2f,
	color: Color4f,
}

rg_grid :: proc(rect: Rect, cell_size: vec2f, color: Color4f, loc := #caller_location) {
    entry := RG_Entry {type=.Grid, grid=RG_Grid{rect=rect, cell_size=cell_size, color=color}}
    rg_push(entry, loc)
}

RG_Entry_Type :: enum i32 {
    Clear,
    Palette,
    Fill_Rect,
    Stroke_Rect,
    Texture,
    Blit,
    Grid,
}

RG_Entry :: struct {
	type: RG_Entry_Type,
	using data: struct #raw_union {
		clear: RG_Clear,
		palette: RG_Palette,
		rect: RG_Rect,
		blit: RG_Blit,
		texture: RG_Texture,
        grid: RG_Grid,
	},
	loc: runtime.Source_Code_Location,
}

@(private)
rg_push :: #force_inline proc(entry: RG_Entry, loc := #caller_location) {
	// TODO: Make render commands variable length to reduce memory use
	entry := entry
	entry.loc = loc
	log.assertf(append(&game.render_group.buffer, entry) != 0, "render group buffer full! %v not added", entry.loc)
}

// Output render group to pixmap
rg_to_output :: proc(target_pixmap: Pixmap) {
	rg := &game.render_group
	for cmd in rg.buffer {
		switch cmd.type {
        case .Clear:
	        color_u32 := util.pack_color_4b(cmd.clear.color, target_pixmap.format)
			pixels := cast([^]ColorU32)target_pixmap.pixels
			area := target_pixmap.w * target_pixmap.h
            slice.fill(pixels[:area], color_u32)
        case .Palette:
        	assert(cmd.palette != {})
       		rg.palette[cmd.palette.idx] = util.pack_color(cmd.palette.color, target_pixmap.format)
        case .Blit:
        	if rg.texture.pixels == pacman_ptr {
         		// intrinsics.debug_trap()
	        }
	        if rg.texture.format.bytes_per_pixel == 4 {
				blit(
	                target_pixmap,
	                rg.texture,
	                cmd.blit.offset,
	                cmd.blit.src_rect,
                    cmd.blit.dst_dims,
                    cmd.blit.clip_rect,
	                cmd.blit.flip,
            	)
			} else if rg.texture.format.bytes_per_pixel == 1 {
				blit_indexed(
					&rg.palette,
	                target_pixmap,
	                rg.texture,
	                cmd.blit.offset,
	                cmd.blit.src_rect,
                    cmd.blit.dst_dims,
                    cmd.blit.clip_rect,
	                cmd.blit.flip,
            	)
			}
        case .Fill_Rect:
            fill_rect_f(target_pixmap, cmd.rect.rect, util.color4b_to_4f(cmd.rect.color))
        case .Stroke_Rect:
            stroke_rect_f(target_pixmap, cmd.rect.rect, util.color4b_to_4f(cmd.rect.color))
        case .Texture:
        	rg.texture = cmd.texture.texture
        case .Grid:
            pixels := cast([^]ColorU32)target_pixmap.pixels
            line_color := util.pack_color_4f(cmd.grid.color, target_pixmap.format)
            x := cast(f32)cmd.grid.rect.x
            max_x := cast(f32)cmd.grid.rect.x + cast(f32)cmd.grid.rect.w
        	x_inc := cmd.grid.cell_size.x
            for ; x < max_x; x += x_inc {
        		for y: i32 = 0; y < target_pixmap.h; y += 1 {
          			pixels[y*game.update_info.framebuffer.w + cast(i32)x] = line_color
          		}
        	}
        	y := cast(f32)cmd.grid.rect.x
            max_y := cast(f32)cmd.grid.rect.y + cast(f32)cmd.grid.rect.h
         	y_inc := cmd.grid.cell_size.y
        	for y := y_inc; y < max_y ; y += y_inc {
                for x: i32 = 0; x < target_pixmap.w; x += 1 {
                    pixels[cast(i32)y*game.update_info.framebuffer.w + x] = line_color
                }
            }
        }
    }
    rg.texture = {}
    clear(&rg.buffer)
}
