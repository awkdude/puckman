package main

import "core:c"
import "odinlib:util"

Rectf :: util.Rectf

// Queue of rendering commands
Render_Group :: struct {
    buffer: [dynamic; 1024]Render_Entry,
}

Render_Clear :: Color4f

Render_Fill_Rect :: struct {
    rect: Rectf,
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
}

Render_Entry :: union {
    Render_Clear,
    Render_Fill_Rect,
    Render_Pixmap,
    Render_Coord_System,
}

// Push render entry onto render group
render_group_push :: proc(rg: ^Render_Group, entry: Render_Entry) {
    append(&rg.buffer, entry)
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
        case Render_Pixmap:
	        blit(
                target_pixmap,
                cmd.pixmap,
                cast(vec2)cmd.offset,
                cmd.dst_rect,
                cmd.src_rect,
            )
        case Render_Coord_System:
        	p := cmd.origin
      		fill_rect(target_pixmap, {p.x, p.y, 5, 5}, cmd.color)
        	p = cmd.origin + cmd.basis_x
            fill_rect(target_pixmap, {p.x, p.y, 5, 5}, cmd.color)
	       	p = cmd.origin + cmd.basis_y
      		fill_rect(target_pixmap, {p.x, p.y, 5, 5}, cmd.color)
        }
    }
    clear(&rg.buffer)
}
