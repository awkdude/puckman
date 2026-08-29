package draw

import "../util"

SW_Context :: struct {
    pixmap: util.Pixmap,
    clip_rect_stack: [dynamic]Rect,
    // buffer: [dynamic]Command,
}

sw_push_clip_rect :: proc(draw_context: ^Draw_Context, rect: Rect) {
    sw_context := cast(^SW_Context)draw_context.data
    append(&sw_context.clip_rect_stack, rect)
}

sw_pop_clip_rect :: proc(draw_context: ^Draw_Context) {
    sw_context := cast(^SW_Context)draw_context.data
    pop(&sw_context.clip_rect_stack)
}

sw_begin_frame :: proc(draw_context: ^Draw_Context) {
}

sw_end_frame :: proc(draw_context: ^Draw_Context) {
}

sw_push_command :: proc(draw_context: ^Draw_Context, command: Command) {
    sw_context := cast(^SW_Context)draw_context.data
    #partial switch params in command {
    case Clear:
        _fill(&sw_context.pixmap, params.color)
    case Fill_Rect:
        _fill_rect(&sw_context.pixmap, params.rect, params.color)
    }
}

sw_get_render_target_dpi :: proc(draw_context: ^Draw_Context) -> i32 {
    panic("get_render_target_dpi was not set!")
}

sw_get_render_target_size :: proc(draw_context: ^Draw_Context) -> vec2 {
    sw_context := cast(^SW_Context)draw_context.data
    return vec2 {
        sw_context.pixmap.w,
        sw_context.pixmap.h,
    }
}

sw_measure_string :: proc(draw_context: ^Draw_Context, font: rawptr, text: string) -> vec2 {
    // TODO:
    return vec2{0, 0}
}

sw_create_font :: proc(
    draw_context: ^Draw_Context,
    font_name: string,
    font_size_dip: f32,
    resource_type: Font_Resource_Type) -> rawptr 
{
    // TODO:
    return nil
}

new_draw_context_sw :: proc(
    override_table: Draw_Context_VTable,
    allocator := context.allocator) -> Draw_Context
{
    draw_context: Draw_Context
    draw_context.data = new(SW_Context, allocator)
    draw_context.vtable = new_clone(SW_VTable, allocator)
    assert(draw_context.data != nil)
    // TODO: override others maybe. or maybe iterate pointers like it's an array
    if override_table.get_render_target_dpi != nil {
        draw_context.vtable.get_render_target_dpi = override_table.get_render_target_dpi 
    }
    if override_table.end_frame != nil {
        draw_context.vtable.end_frame = override_table.end_frame 
    }
    if override_table.resize != nil {
        draw_context.vtable.resize = override_table.resize 
    }
    return draw_context
}

SW_VTable := Draw_Context_VTable {
    push_clip_rect=sw_push_clip_rect,
    pop_clip_rect=sw_pop_clip_rect,
    begin_frame=sw_begin_frame,
    end_frame=sw_end_frame,
    get_render_target_dpi=sw_get_render_target_dpi,
    get_render_target_size=sw_get_render_target_size,
    measure_string=sw_measure_string,
    push_command=sw_push_command,
    create_font=sw_create_font,
}
