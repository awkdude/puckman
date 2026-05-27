package dumb

import eng "../"

import "odinlib:util"
import "core:log"

game: ^eng.Game_Context

@(export, link_name="module_init")
init :: proc(game_context: ^eng.Game_Context) {
	game = game_context
	log.debug("INIT")
	log.debug("Running: ", game.running)
}

@(export, link_name="module_update_render")
update_render :: proc() {
	log.debug("update_render")
	eng.render_group_push(&game.render_group, eng.color_orange)
}

@(export, link_name="module_handle_event")
handle_event :: proc(event: util.Window_Event) {
	log.debug("handle_event")
}

@(export, link_name="module_shutdown")
shutdown :: proc() {
	log.debug("shutdown")
}
