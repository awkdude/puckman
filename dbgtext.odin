package main

import "core:fmt"
import "core:math"

// TODO: Might actually queue the strings before calling draw_text

Dbg_Text :: struct {
    scale: f32,
    scroll_offset: f32,
    output_dims: vec2,
    origin, offset, padding: vec2f,
    prev_frame_content_height: i32,
}

dbgtext_context: ^Dbg_Text

dbgtext_init :: proc(dbgtext: ^Dbg_Text) {
    dbgtext.scale = 1
}

dbgtext_frame :: proc(dbgtext: ^Dbg_Text, output_dims: vec2, scroll_delta: vec2f) {
    dbgtext.offset = dbgtext.padding
    dbgtext_context = dbgtext
    dbgtext.output_dims = output_dims
    height_diff := dbgtext.prev_frame_content_height - output_dims.y
    if height_diff > 0 {
        dbgtext.scroll_offset += scroll_delta.y
        dbgtext.scroll_offset = math.clamp(dbgtext.scroll_offset, 0, cast(f32)height_diff)
        dbgtext.offset.y -= cast(f32)dbgtext.scroll_offset
    }
    dbgtext.prev_frame_content_height = 0
}

dbgtext_print :: proc(args: ..any) {
    rg_palette(1, color_white_4b)
    buffer: [256]u8
    text_str := fmt.bprint(buffer[:], ..args)
    _dbgtext_push(text_str)
}

dbgtext_printf :: proc(fmt_str: string, args: ..any) {
    rg_palette(1, color_white_4b)
    buffer: [256]u8
    text_str := fmt.bprintf(buffer[:], fmt_str, ..args)
    _dbgtext_push(text_str)
}

@(private="file")
_dbgtext_push :: proc(text_str: string) {
    text_height := cast(f32)CELL_SIZE*dbgtext_context.scale
    y_advance := text_height + dbgtext_context.padding.y
    draw_text(text_str, cast(vec2)dbgtext_context.origin+cast(vec2)dbgtext_context.offset, dbgtext_context.scale)
    dbgtext_context.offset.y += y_advance
    dbgtext_context.prev_frame_content_height += cast(i32)math.round(y_advance)
    dbgtext_context.offset.x = dbgtext_context.padding.x
}
