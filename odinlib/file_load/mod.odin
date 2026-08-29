package file_load

import "../util"

Pixmap :: util.Pixmap

load_image :: proc(
    path: string,
    pixel_format: util.Pixel_Format,
    allocator := context.allocator) -> (Pixmap, bool)
{
    pixmap: Pixmap
    load_ok: bool
    pixmap, load_ok = load_png(path, pixel_format, allocator)
    if load_ok {
        return pixmap, load_ok
    }
    pixmap, load_ok = load_bmp(path, pixel_format, allocator)
    if load_ok {
        return pixmap, load_ok
    }
    return {}, false
}
