package main

import "core:c"
import "core:math"
import "core:log"
import "core:math/linalg"
import "core:slice"
import "odinlib:util"
import "base:runtime"
import "base:intrinsics"
import "core:thread"
import "core:os"

Rectf :: util.Rectf

Palette :: [32]ColorU32

ENABLE_MULTITHREADING :: false 

// NOTE: Concern that Palette makes each entry 128 bytes

white_texture_data := []ColorU32 {
	0xffffffff,
    0xffffffff,
	0xffffffff,
	0xffffffff,
}

// Queue of rendering commands
Render_Group :: struct {
    // buffer: [1024*1024]u8,
    // len: int,
    target_pixmap, texture: Pixmap,
    palette: Palette,
    global_offset: vec2,
    buffer: [dynamic; 1024]RG_Entry,
    is_multithreading: bool,
    thread_pool: thread.Pool,
    initialized: bool,
    most_queued: int,
}

RG_Clear :: struct #align(4) {
	color: Color4b,
}

rg_init :: proc() {
    rg := &game.render_group
    // rg^ = {}
    thread.pool_init(&rg.thread_pool, context.allocator, os.get_processor_core_count())
    thread.pool_start(&rg.thread_pool)
    rg.initialized = true
}

rg_begin_multithread :: proc(loc := #caller_location) {
    entry := RG_Entry {
        type=.Begin_Multithread,
        loc=loc,
    }
    rg_push(entry, loc)
}

rg_end_multithread :: proc(loc := #caller_location) {
    entry := RG_Entry {
        type=.End_Multithread,
        loc=loc,
    }
    rg_push(entry, loc)
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

rg_translate :: proc(offset: vec2, loc := #caller_location) {
	entry := RG_Entry{ type=.Translate, offset=offset}
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
    Translate,
    // Marker to allow subsequent commands to be executed concurrently
    Begin_Multithread,
    // Marker to end subsequent commands from being executed concurrently
    End_Multithread,
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
        offset: vec2,
	},
	loc: runtime.Source_Code_Location,
}

@(private)
rg_push :: #force_inline proc(entry: RG_Entry, loc := #caller_location) {
	// TODO: Make render commands variable length to reduce memory use
	entry := entry
	entry.loc = loc
	log.assertf(append(&game.render_group.buffer, entry) != 0, "render group buffer full! %v at %v not added", entry.type, entry.loc)
}

@(private)
process_cmd :: proc(cmd: ^RG_Entry) {
	rg := &game.render_group
    #partial switch cmd.type {
    case .Clear:
        color_u32 := util.pack_color_4b(cmd.clear.color, rg.target_pixmap.format)
        pixels := cast([^]ColorU32)rg.target_pixmap.pixels
        area := rg.target_pixmap.w * rg.target_pixmap.h
        slice.fill(pixels[:area], color_u32)
    case .Palette:
        assert(cmd.palette != {})
        rg.palette[cmd.palette.idx] = util.pack_color(cmd.palette.color, rg.target_pixmap.format)
    case .Translate:
        rg.global_offset = cmd.offset
    case .Blit:
        if rg.texture.format.bytes_per_pixel == 4 {
            blit_fp(
                rg.target_pixmap,
                rg.texture,
                rg.global_offset + cmd.blit.offset,
                cmd.blit.src_rect,
                cmd.blit.dst_dims,
                cmd.blit.clip_rect,
                cmd.blit.flip,
                // 8
            )
        } else if rg.texture.format.bytes_per_pixel == 1 {
            blit_indexed_fp(
                &rg.palette,
                rg.target_pixmap,
                rg.texture,
                rg.global_offset + cmd.blit.offset,
                cmd.blit.src_rect,
                cmd.blit.dst_dims,
                cmd.blit.clip_rect,
                cmd.blit.flip,
            )
        }
    case .Fill_Rect:
        cmd := cmd
        cmd.rect.rect.x += rg.global_offset.x
        cmd.rect.rect.y += rg.global_offset.y
        fill_rect_f(rg.target_pixmap, cmd.rect.rect, util.color4b_to_4f(cmd.rect.color))
    case .Stroke_Rect:
        cmd := cmd
        cmd.rect.rect.x += rg.global_offset.x
        cmd.rect.rect.y += rg.global_offset.y
        stroke_rect_f(rg.target_pixmap, cmd.rect.rect, util.color4b_to_4f(cmd.rect.color))
    case .Texture:
        rg.texture = cmd.texture.texture
    case .Grid:
        cmd := cmd
        cmd.rect.rect.x += rg.global_offset.x
        cmd.rect.rect.y += rg.global_offset.y
        pixels := cast([^]ColorU32)rg.target_pixmap.pixels
        line_color := util.pack_color_4f(cmd.grid.color, rg.target_pixmap.format)
        // bbox := util.rect_to_bbox(util.rect_to_f(cmd.grid.rect))
        bbox := util.rect_to_bbox(cmd.grid.rect)
        x_inc := cmd.grid.cell_size.x
        minx := cast(f32)bbox.min.x
        maxx := cast(f32)bbox.max.x
        for x := minx; x < maxx; x += x_inc {
            for y: i32 = bbox.min.y; y < bbox.max.y; y += 1 {
                pixels[y*game.update_info.framebuffer.w + cast(i32)x] = line_color
            }
        }
        y_inc := cmd.grid.cell_size.y
        miny := cast(f32)bbox.min.y
        maxy := cast(f32)bbox.max.y
        for y := miny; y < maxy; y += y_inc {
            for x: i32 = 0; x < bbox.max.x; x += 1 {
                pixels[cast(i32)y*game.update_info.framebuffer.w + x] = line_color
            }
        }
    }
}

// Output render group to pixmap
rg_to_output :: proc(target_pixmap: Pixmap) {
	rg := &game.render_group
    assert(rg.initialized)
    rg.target_pixmap = target_pixmap
    if rg.most_queued < len(rg.buffer) {
        rg.most_queued = len(rg.buffer)
    }
	for &cmd in rg.buffer {
        when ENABLE_MULTITHREADING {
            if cmd.type == .Begin_Multithread {
                assert(!rg.is_multithreading)
                rg.is_multithreading = true
            } else if cmd.type == .End_Multithread {
                assert(rg.is_multithreading)
                rg.is_multithreading = false
                for thread.pool_num_outstanding(&rg.thread_pool) > 0 {}
            }
        }
        if rg.is_multithreading {
            thread.pool_add_task(
                &rg.thread_pool,
                allocator=context.allocator,
                procedure=proc(task: thread.Task) {
                    process_cmd(cast(^RG_Entry)task.data)
                },
                data=&cmd,
            )
        } else {
            process_cmd(&cmd)
        }
    }
    rg.target_pixmap = {}
    rg.texture = {}
    rg.global_offset = {}
    rg.is_multithreading = false
    clear(&rg.buffer)
}
