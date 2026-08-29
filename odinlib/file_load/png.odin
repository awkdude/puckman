package file_load

import "../util"
import "core:bytes"
import "core:os"
import "core:fmt"
import "core:slice"
import "core:mem"
import "core:math"
import "core:math/bits"
import "core:log"
import "core:c"
import "core:compress/zlib"

Color4b :: util.Color4b
ColorU32 :: util.ColorU32

file_header := [?]u8 {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}
PLTE :: 0x504c5445
IDAT :: 0x49444154
IEND :: 0x49454e44
bKGD :: 0x624b4744
tIME :: 0x74494d45
tRNS :: 0x74524e53

color_type_strs := [?]string {
    "Greyscale",
    "?",
    "Truecolour",
    "Indexed-colour",
    "Greyscale with alpha",
    "?",
    "Truecolour with alpha"
}

u32_from_be_bytes :: proc (bytes: []u8) -> u32be {
    return (^u32be)(slice.as_ptr(bytes))^
}

u16_from_be_bytes :: proc(bytes: []u8) -> u16be {
    return (^u16be)(slice.as_ptr(bytes))^
}

is_png :: proc(path: string) -> bool {
    file, open_err := os.open(path)
    if open_err != nil do return false
    defer os.close(file)

    buffer: [8]u8
    os.read(file, buffer[:])
    return bytes.compare(buffer[:], file_header[:]) == 0
}

load_png :: proc(
    path: string,
    pixel_format: util.Pixel_Format,
    allocator := context.allocator) -> (util.Pixmap, bool) #optional_ok
{
    // {{{
    file, open_err := os.open(path)
    if open_err != nil do return {}, false
    defer os.close(file)

    buffer: [64]u8
    os.seek(file, 0, .Start)
    // Read PNG signature + length + chunk type + IHDR data + CRC
    os.read(file, buffer[:33])
    if bytes.compare(buffer[:8], file_header[:]) != 0 {
        return {}, false
    }
    width :=  cast(i32)u32_from_be_bytes(buffer[0x10:0x14])
    height := cast(i32)u32_from_be_bytes(buffer[0x14:0x18])
    bits_per_channel := buffer[0x18]
    color_type := buffer[0x19]
    interlace_method := buffer[0x1c]

    bytes_per_pixel: i32
    if color_type == 0 || color_type == 3 {
        bytes_per_pixel = 1
    } else if color_type == 2 {
        bytes_per_pixel = 3
    } else if color_type == 4 {
        bytes_per_pixel = 2
    } else if color_type == 6 {
        bytes_per_pixel = 4
    }
    output_bufsize := uint(width * height * bytes_per_pixel + height)
    log.debugf(
    "IHDR (13 bytes)\n\tWidth: %d\n\tHeight: %d\n\tBit depth: %d\n\tColor type: " +
           "%s\n\tInterlace method: %d\n",
           width,
           height,
           bits_per_channel,
           color_type_strs[color_type],
           interlace_method
    )

    if bits_per_channel != 8 {
        return {}, false
    }
    // output_bytes := make([]u8, output_bufsize, allocator)
    // defer delete(output_bytes)

    color_lookup_table: []Color4b
    // TODO: use temp allocator
    if color_type == 3 {
    	color_lookup_table = make([]Color4b, 256, allocator)
    }
    defer if color_type == 3 {
    	delete(color_lookup_table)
    }
    reached_iend := false
    str: [4]u8
    idat_buffer := make([]u8, output_bufsize, allocator)
    defer delete(idat_buffer)
    input_offset := 0
    for !reached_iend {
        chunk_length, chunk_type: u32
        os.read_ptr(file, rawptr(&chunk_length), 4)
        os.read_ptr(file, rawptr(&chunk_type), 4)
        mem.copy(raw_data(&str), rawptr(&chunk_type), 4)
        chunk_length = bits.to_be_u32(chunk_length)
        chunk_type = bits.to_be_u32(chunk_type)
        log.debugf("Type: %s, Length: %d\n", str, chunk_length)
        switch chunk_type {
        case PLTE:
            entry: [4]u8
            num_entries := chunk_length / 3
            for i in 0..<num_entries {
                os.read(file, entry[:3])
                color_lookup_table[i].r = entry[0]
                color_lookup_table[i].g = entry[1]
                color_lookup_table[i].b = entry[2]
                color_lookup_table[i].a = 255
                // color_lookup_table[i] = util.pack_color(entry, pixel_format)
            }
        case IDAT:
            os.read(file, idat_buffer[input_offset:input_offset+cast(int)chunk_length])
            input_offset += cast(int)chunk_length
        case tRNS:
            // Discard if not color type is not indexed-color
            log.debug("Color type: ", color_type)
            if color_type != 3 {
                os.seek(file, cast(i64)chunk_length, .Current)
            } else {
                for i in 0..<chunk_length {
                    os.read_ptr(file, &color_lookup_table[i].a, 1)
                }
            }
        case bKGD:
            r, g, b: u8
            values: [3]u16

            if color_type == 0 || color_type == 4 {
                os.read_ptr(file, &values, 2)
                r = cast(u8)bits.to_be_u16(values[0])
                g, b = r, r
            } else if color_type == 2 || color_type == 6 {
                os.read_ptr(file, &values, 6)
                r = cast(u8)bits.to_be_u16(values[0])
                g = cast(u8)bits.to_be_u16(values[1])
                b = cast(u8)bits.to_be_u16(values[2])
            } else if color_type == 3 {
                idx: u8
                os.read_ptr(file, &idx, 1)
                r = color_lookup_table[idx].r
                g = color_lookup_table[idx].g
                b = color_lookup_table[idx].b
                // rgba := unpack_color_rgba(color_lookup_table[idx])
            }
            log.debugf("\tBackground color: %.2x %.2x %.2x\n", r, g, b)
        case IEND:
            reached_iend = true
        case:
            os.seek(file, cast(i64)chunk_length, .Current)
        }
        // Skip CRC
        os.seek(file, 4, .Current)
    }
    output_buffer: bytes.Buffer
    defer bytes.buffer_destroy(&output_buffer)
    // dest_len := cast(c.ulong)len(output_bytes)
    // zlib_ret := zlib.uncompress(raw_data(output_bytes), &dest_len,
    //     raw_data(idat_buffer), cast(c.ulong)input_offset)
    zlib.inflate(idat_buffer[:input_offset], &output_buffer)
    output_bytes := bytes.buffer_to_bytes(&output_buffer)
    png_unfilter_bytes(output_bytes, width, height, int(bytes_per_pixel))
    return png_read_pixels(
    	output_bytes,
     	width,
      	height,
       	color_type,
        color_lookup_table,
    	pixel_format
     )
// }}}
}

png_unfilter_bytes :: proc(
	png_bytes: []u8,
 	width, height: i32,
  	bytes_per_pixel: int)
{
// {{{
    /*
       -----------------------
       | top_left | top_byte |
       -----------------------
       |    left |      byte |
       -----------------------
    */
    stride := cast(int)width * bytes_per_pixel
    byte_i: int = 0
    left_byte_i := -bytes_per_pixel
    top_byte_i := -stride - 1
    top_left_byte_i := -stride - bytes_per_pixel - 1
    for scanline in 0..<cast(int)height {
        filter_byte := png_bytes[byte_i]
        byte_i += 1
        left_byte_i += 1
        top_byte_i += 1
        top_left_byte_i += 1
        if filter_byte == 0 {
            byte_i += stride
            left_byte_i += stride
            top_byte_i += stride
            top_left_byte_i += stride
            continue
        }
        for x in 0..<stride {
            byte := png_bytes[byte_i]
            left_byte := png_bytes[left_byte_i] if (x >= bytes_per_pixel) else 0
            top_byte := png_bytes[top_byte_i] if scanline > 0 else 0
            top_left_byte := png_bytes[top_left_byte_i] if
                (x >= bytes_per_pixel && scanline > 0) else 0

            pr: i32
            if filter_byte == 1 {
                png_bytes[byte_i] = byte + left_byte
            } else if filter_byte == 2 {
                png_bytes[byte_i] = byte + top_byte
            } else if filter_byte == 3 {
                png_bytes[byte_i] = byte + u8((cast(f32)left_byte + cast(f32)top_byte) / 2)
            } else if filter_byte == 4 {
                p := cast(i32)left_byte + cast(i32)top_byte - cast(i32)top_left_byte
                pa := math.abs(p - cast(i32)left_byte)
                pb := math.abs(p - cast(i32)top_byte)
                pc := math.abs(p - cast(i32)top_left_byte)
                if pa <= pb && pa <= pc {
                    pr = cast(i32)left_byte
                } else if pb <= pc {
                    pr = cast(i32)top_byte
                } else {
                    pr = cast(i32)top_left_byte
                }
                png_bytes[byte_i] = u8((cast(i32)byte + pr) % 256)
            }
            byte_i += 1
            left_byte_i += 1
            top_byte_i += 1
            top_left_byte_i += 1
        }
    }
// }}}
}

png_read_pixels :: proc(
    png_bytes: []u8,
    width, height: i32,
    color_type: u8,
    color_lookup_table: []Color4b,
    pixel_format: util.Pixel_Format) -> (util.Pixmap, bool)
{
// {{{
    pixmap, alloc_ok := util.make_pixmap(width, height, pixel_format)
    if !alloc_ok {
        return {}, false
    }
    color: Color4b
    byte_i: uint = 0
    row: i32
    pixels := cast([^]ColorU32)pixmap.pixels
    switch color_type {
    case 0:
        for y in 0..<pixmap.h {
            byte_i += 1
            for x in 0..<pixmap.w {
                color.r = png_bytes[byte_i]
                color.g = png_bytes[byte_i]
                color.b = png_bytes[byte_i]
                color.a = 255
                pixels[row + x] = util.pack_color(color, pixel_format)
                byte_i += 1
            }
            row += pixmap.w
        }
    case 4:
        for y in 0..<pixmap.h {
            byte_i += 1
            for x in 0..<pixmap.w {
                color.r = png_bytes[byte_i]
                color.g = png_bytes[byte_i]
                color.b = png_bytes[byte_i]
                color.a = png_bytes[byte_i + 1]
                pixels[row + x] = util.pack_color(color, pixel_format)
                byte_i += 2
            }
            row += pixmap.w
        }
    case 2:
        for y in 0..<pixmap.h {
            byte_i += 1
            for x in 0..<pixmap.w {
                color.r = png_bytes[byte_i]
                color.g = png_bytes[byte_i + 1]
                color.b = png_bytes[byte_i + 2]
                color.a = 255
                pixels[row + x] = util.pack_color(color, pixel_format)
                byte_i += 3
            }
            row += pixmap.w
        }
    case 6:
        for y in 0..<pixmap.h {
            byte_i += 1
            for x in 0..<pixmap.w {
                color.r = png_bytes[byte_i]
                color.g = png_bytes[byte_i + 1]
                color.b = png_bytes[byte_i + 2]
                color.a = png_bytes[byte_i + 3]
                pixels[row + x] =  util.pack_color(color, pixel_format)
                byte_i += 4
            }
            row += pixmap.w
        }
    case 3:
        for y in 0..<pixmap.h {
            byte_i += 1
            for x in 0..<pixmap.w {
                color.r = color_lookup_table[png_bytes[byte_i]].r
                color.g = color_lookup_table[png_bytes[byte_i]].g
                color.b = color_lookup_table[png_bytes[byte_i]].b
                color.a = color_lookup_table[png_bytes[byte_i]].a
                pixels[row + x] = util.pack_color(color, pixel_format)
                byte_i += 1
            }
            row += pixmap.w
        }
    case:
    }
    return pixmap, true
// }}}
}
