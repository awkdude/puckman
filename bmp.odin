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
	bpp: u16le,
	compression_type: u32le,
	image_size: u32le,
	_, _: u32le,
	colors_used: u32le,
	important_colors: u32le,
}

load_bmp_indexed :: proc(
    path: string,
    palette: ^Palette,
    allocator := context.allocator) -> (Pixmap, bool)
{
    file, open_err := os.open(path)
    if open_err != nil do return {}, false
    defer os.close(file)

    // buffer: [128]u8
    bmp_header: BMP_Header
    os.read_ptr(file, &bmp_header, size_of(bmp_header))

    assert(bmp_header.compression_type == 0, "No compression supported")
    assert(bmp_header.num_planes == 1, "No color planes supported")
    assert(bmp_header.bpp == 8, "This only loads indexed bmps!")
    assert(
    	bmp_header.colors_used == 0 || bmp_header.colors_used == 256,
     	"256 colors must be present"
    )

    palette_4b: [256]Color_Quad
	os.read_slice(file, palette_4b[:])
    if palette != nil {
    	for i in 0..<256 {
   			palette^[i] = util.Color4f {
   				cast(f32)palette_4b[i].r / 255.0,
   				cast(f32)palette_4b[i].g / 255.0,
   				cast(f32)palette_4b[i].b / 255.0,
   				1.0,
      		}
        	log.debugf("%v: %v", i, palette_4b[i])
     	}
    }

    pixmap: Pixmap

    // if slice.cmp(transmute(string)buffer[:2], "BM") != .Equal {
    //     return {}, false
    // }

    // image_data_offset := u32_from_le_bytes(buffer[0xa:])
    // bmp_header_size := u32_from_le_bytes(buffer[0xe:])

    // if bmp_header_size != 124 {
    //     log.warn("NOT BITMAPV5HEADER!")
    //     return {}, false
    // }

    // os.read(file, buffer[:16])

    // width := i32(u32_from_le_bytes(buffer[:]))
    // height := i32(u32_from_le_bytes(buffer[4:]))
    // bits_per_pixel := u16(u16_from_le_bytes(buffer[0xa:]))
    // compression_method := u16(u16_from_le_bytes(buffer[0xc:]))

    // log.debugf("Header size: %v\nWidth: %v\nHeight: %v\nBits per pixel: %v\n" +
    //     "Compression method: %v\n",
    //        bmp_header_size, width, height, bits_per_pixel,
    //        compression_method_strs[compression_method])

    // if compression_method != 0 && compression_method != 3 {
    //     log.error("Compression method is not Bi_RGB")
    //     return {}, false
    // }

    // os.read(file, buffer[:bmp_header_size - 20])
    // // log.debugf("%.8x %.8x %.8x\n", u32_from_le_bytes(buffer[20:]),
    // //        u32_from_le_bytes(buffer[24:]), u32_from_le_bytes(buffer[28:]))

    // os.seek(file, i64(image_data_offset), .Start)

    // read_fn: proc(^os.File, ^util.Pixmap)
    // switch bits_per_pixel {
    //     case 16: read_fn = read_pixels_16
    //     case 24: read_fn = read_pixels_24
    //     case 32: read_fn = read_pixels_32
    //     case:
    //         return {}, false
    // }
    // pixmap, alloc_ok := util.make_pixmap(width, height, pixel_format)
    // if !alloc_ok {
    //     return {}, false
    // }

    // read_fn(file, &pixmap)
    return pixmap, true
}
