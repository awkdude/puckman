package main

import "core:slice"
import "core:os"
import "core:log"

import "odinlib:util"

Color_Quad :: struct {
	b, g, r, _: u8,
}

BMP_Header :: struct #packed {
	sig: [2]u8,
	file_size: u32le,
	_: u32le,
	data_offset: u32le,
	header_size: u32le,
	width: u32le,
	height: u32le,
	num_planes: u16le,
	bits_per_pixel: u16le,
	compression_type: u32le,
	image_size: u32le,
	_, _: u32le,
	colors_used: u32le,
	important_colors: u32le,
}

load_bmp_indexed :: proc(
    path: string,
    palette: ^Palette = nil,
    allocator := context.allocator) -> (Pixmap, bool)
{
    file, open_err := os.open(path)
    if open_err != nil do return {}, false
    defer os.close(file)

    bmp_header: BMP_Header
    os.read_ptr(file, &bmp_header, size_of(bmp_header))

    assert(bmp_header.compression_type == 0, "No compression supported")
    assert(bmp_header.num_planes == 1, "No color planes supported")
    assert(bmp_header.bits_per_pixel == 8, "This only loads indexed bmps!")
    assert(
    	bmp_header.colors_used == 0 || bmp_header.colors_used == 256,
     	"256 colors must be present"
    )

    log.debug(path, ":", bmp_header)

    palette_quad: [256]Color_Quad
	os.read_slice(file, palette_quad[:])
    if palette != nil {
    	for &entry, i in palette[:] {
   			entry = util.Color4b {
   				palette_quad[i].r,
   				palette_quad[i].g,
   				palette_quad[i].b,
   				255,
      		}
     	}
    }

    pixmap := util.make_pixmap(
    	cast(i32)bmp_header.width,
     	cast(i32)bmp_header.height,
      	{},
       	bytes_per_pixel=1
    )
    w, h := cast(int)bmp_header.width, cast(int)bmp_header.height
    // TODO: optimize: maybe try os.read() entire image data then flip imag in-place
    pixels := cast([^]u8)pixmap.pixels
    when false {
	    for y := h - 1; y >= 0; y -= 1 {
	    	for x in 0..<w {
	     		b: [1]u8
	     		os.read(file, b[:])
	    		pixels[y * w + x] = b[0]
	     	}
	    }
    } else {
	    os.read_ptr(file, pixmap.pixels, w*h)
		for y in 0..<h/2 {
			y_inv := (h - 1) - y
			for x in 0..<w {
				top := &pixels[y * w + x]
				bottom := &pixels[y_inv * w + x]
				top^, bottom^ = bottom^, top^
			}
		}
    }
    return pixmap, true
}
