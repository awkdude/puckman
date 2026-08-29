#+build !windows
#+build !linux
package draw
import "core:math"
import "core:strings"
import "core:log"
import "core:c"
import "../util"
import "core:unicode/utf8"
import "../freetype"

// Not defined in shared:freetype.odin
FT_FACE_FLAG_KERNING: c.long : (1 << 6)
FT_KERNING_DEFAULT :: 0

when ODIN_OS == .Windows {
    foreign import freetype_extension "freetype.lib"
} else {
    foreign import freetype_extension "system:freetype2"
}


@(default_calling_convention="c")
foreign freetype_extension {
FT_Get_Kerning :: proc "c" (
    face: freetype.Face, 
    left_glyph, right_glyph, kern_mode: c.uint,
    akerning: ^freetype.Vector) -> freetype.Error ---
}

NUM_CHARS :: 128-32

Baked_Char :: struct {
    x0, y0, x1, y1, xoff, yoff, xadvance: i32, 
}


Font_Info :: struct {
    ft_face: freetype.Face,
    atlas: Pixmap,
    char_data: [NUM_CHARS]Baked_Char,
    pixel_height: i32,
    use_kerning: bool,
}

font_info_new_from_path :: proc(ft_library: freetype.Library, path: string) -> (Font_Info, bool) {
    ft_face: freetype.Face
    path := strings.clone_to_cstring(path)
    ft_error := freetype.new_face(ft_library, path, 0, &ft_face)
    if ft_error != .Ok do return {}, false
    use_kerning := (ft_face.face_flags & FT_FACE_FLAG_KERNING) != 0
    return {ft_face=ft_face, use_kerning=use_kerning}, true
}

@(private)
bake_font_pixmap :: proc(font_info: ^Font_Info, pixel_height: i32) {
    log.debug("BAKING FONT")
    freetype.set_pixel_sizes(font_info.ft_face, 0, cast(u32)pixel_height)
    font_info.atlas = util.make_pixmap(pixel_height * NUM_CHARS, (pixel_height * NUM_CHARS) + 1, 1)
    font_info.pixel_height = pixel_height
    pen := vec2{0, 0}
    dst_pixels := cast([^]u8)font_info.atlas.pixels
    ft_error: freetype.Error
    for ch in 33..<128 {
        log.debug(ch)
        ft_error = freetype.load_char(font_info.ft_face, cast(c.ulong)ch, {.Render})
        assert(ft_error == .Ok) 

        // glyph_index := freetype.get_char_index(font_info.ft_face, cast(u64)c)
        // ft_error = freetype.load_glyph(font_info.ft_face, glyph_index, {})
        // assert(ft_error == .Ok) 
        // ft_error = freetype.render_glyph(font_info.ft_face.glyph, .Normal)
        // assert(ft_error == .Ok) 
        bitmap := font_info.ft_face.glyph.bitmap
        src_pixels := cast([^]u8)font_info.ft_face.glyph.bitmap.buffer
        for y in 0..<cast(i32)bitmap.rows {
            dst_y := pen.y + y
            for x in 0..<cast(i32)bitmap.width {
                dst_x := pen.x + x
                dst_pixels[dst_y * font_info.atlas.w + dst_x] = 
                    bitmap.buffer[y * cast(i32)bitmap.width + x]
            }
        }
        advance_x := i32(font_info.ft_face.glyph.advance.x >> 6)
        // TODO: Set char_data for glyph
        font_info.char_data[ch-32] = {
            x0=pen.x,
            y0=0,
            x1=pen.x + cast(i32)bitmap.width,
            y1=pixel_height,
            xoff=0,
            yoff=0,
            xadvance=advance_x,
        }
        pen.x += advance_x
    }
}

font_info_kerning_advance :: proc(fi: ^Font_Info, prev_ch, curr_ch: rune) -> i32 {
    if !fi.use_kerning do return 0
    delta: freetype.Vector
    FT_Get_Kerning(fi.ft_face, cast(u32)prev_ch, cast(u32)curr_ch, FT_KERNING_DEFAULT, &delta)
    return i32(delta.x >> 6)
}

draw_text_single_line :: proc(
    draw_context: ^Draw_Context, 
    font_info: ^Font_Info,
    text: string,
    rect: Rect,
    color: util.Color_f) 
{
    text_height := rect.h
    ft_error: freetype.Error
    pen := vec2{rect.x, rect.y}
    if font_info.pixel_height != text_height {
        bake_font_pixmap(font_info, text_height)
    }
    for ch in text {
        baked_char := font_info.char_data[ch - 32]
        box := util.BBox{baked_char.x0, baked_char.y0, baked_char.x1, baked_char.y1}
        blit_pixmap_mono_to_truecolor(draw_context, &font_info.atlas, pen, color,
            util.rect_from_bbox(box))
        pen.x += baked_char.xadvance
    }
}


// text :: proc(pixmap, slot_pixmap: ^Pixmap, font_info: ^stbtt.fontinfo, text_str: string, off: Rect) {
//     line_height := off.h
//     scale := stbtt.ScaleForPixelHeight(font_info, cast(f32)line_height)
//
//     ascent, descent, line_gap, line_num: i32
//     stbtt.GetFontVMetrics(font_info, &ascent, &descent, &line_gap)
//     ascent  =  cast(i32)math.round(cast(f32)ascent * scale)
//     descent = cast(i32)math.round(cast(f32)descent * scale)
//
//     text := utf8.string_to_runes(text_str)
//
//     x := off.x
//     for c, i in text {
//         ax, lsb: i32
//
//         // TODO: Maybe check more escape characters
//         if c == '\n' {
//             line_num += 1
//             x = off.x
//             continue
//         }
//         stbtt.GetCodepointHMetrics(font_info, c, &ax, &lsb)
//         x0, y0, x1, y1: i32
//         stbtt.GetCodepointBitmapBox(font_info, c, scale, scale, &x0, &y0, &x1, &y1)
//         y := line_num * line_height + off.y + ascent + y0
//         byte_offset := x + cast(i32)math.round(cast(f32)lsb * scale) + y * pixmap.width
//         stbtt.MakeCodepointBitmap(font_info, slot_pixmap.pixels[byte_offset:], 
//             x1 - x0, y1 - y0, pixmap.width, scale, scale, c)
//         blit_from_8bpp(pixmap, slot_pixmap, {x, 0, pixmap.width, pixmap.height}, color_black)
//         x += cast(i32)math.round(cast(f32)ax * scale)
//         next_c := text[i+1] if i < len(text) - 1 else rune(0)
//         kern := stbtt.GetCodepointKernAdvance(font_info, c, next_c)
//         x += cast(i32)math.round(cast(f32)kern * scale)
//     }
// }

