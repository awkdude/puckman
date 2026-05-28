package dumb

import eng "../"

import "odinlib:util"
import "core:log"

eng_context: ^eng.Engine_Context

@(export, link_name="module_init")
game_init :: proc(_eng_context: ^eng.Engine_Context) {
	eng_context = _eng_context
	log.debug("INIT")
	log.debug("Running: ", eng_context.running)
}

@(export, link_name="module_update_render")
game_update_render :: proc() {
	log.debug("update_render")
	v := cast(f32)eng_context.input_state.mouse_position.y / cast(f32)eng_context.update_info.framebuffer.h
	eng.render_group_push(&eng_context.render_group, eng.color_orange * v)
}

@(export, link_name="module_handle_event")
game_handle_event :: proc(event: util.Window_Event) {
	log.debug("handle_event")
}

@(export, link_name="module_shutdown")
game_shutdown :: proc() {
	log.debug("shutdown")
}
