package file_load

import "core:os"
import "core:mem"
import "core:log"
import "core:math"
import "core:math/bits"
import "../util"

Audio_Buffer :: util.Audio_Buffer
bytes_per_sample_from_format :: util.bytes_per_sample_from_format 

is_wav :: proc(path: string) -> bool {
    file, open_err := os.open(path)
    if open_err != nil {
        return false
    }
    defer os.close(file)

    header_buf: [16]u8
    os.read(file, header_buf[:])

    return mem.compare(header_buf[:4], transmute([]u8)string("RIFF")) == 0 &&
        mem.compare(header_buf[8:12], transmute([]u8)string("WAVE")) == 0
}

load_wav :: proc(
    path: string,
    target_spec: Maybe(util.Audio_Spec) = nil,
    allocator := context.allocator) -> (Audio_Buffer, bool) #optional_ok
{
    file, open_err := os.open(path)
    if open_err != nil {
        return {}, false
    }
    defer os.close(file)

    header_buf: [44]u8
    os.read(file, header_buf[:])

    if mem.compare(header_buf[:4], transmute([]u8)string("RIFF")) != 0 ||
        mem.compare(header_buf[8:12], transmute([]u8)string("WAVE")) != 0 {
        log.error("Invalid header!\n")
        return {}, false
    }

    data_size :=  cast(uint)u32_from_le_bytes(header_buf[40:44])
    bits_per_sample := cast(i32)u16_from_le_bytes(header_buf[34:36])
    bit_format: util.Audio_Format
    if bits_per_sample == 8 {
        bit_format = .U8
    } else if bits_per_sample == 16 {
        bit_format = .S16
    }
    num_channels := cast(i32)u16_from_le_bytes(header_buf[22:24])
    sample_rate := cast(i32)u32_from_le_bytes(header_buf[24:28])

    audio_buf := Audio_Buffer {
        data            = make([]u8, data_size),
        num_channels    = num_channels,
        sample_rate     = sample_rate,
        bit_format      = bit_format,
    }

    audio_buf.sample_count = data_size / (uint)(audio_buf.num_channels * (bits_per_sample / 8))

    log.debugf(
        "Channels: %d\nSample rate: %dHz\nBits per sample: %d\nSample count: %d\n",
        audio_buf.num_channels,
        audio_buf.sample_rate,
        bits_per_sample,
        audio_buf.sample_count
    )
    os.read(file, audio_buf.data[:])

    if target_spec, ok := target_spec.?; ok {
        new_sample_count := cast(uint)math.ceil(cast(f32)audio_buf.sample_count * (cast(f32)target_spec.sample_rate / cast(f32)audio_buf.spec.sample_rate))
        new_bytes_per_sample := bytes_per_sample_from_format(target_spec.bit_format)
        new_data_size := new_sample_count * cast(uint)target_spec.num_channels * new_bytes_per_sample
    	new_audio_buf := Audio_Buffer{
            data=make([]u8, new_data_size),
            sample_count=new_sample_count,
            spec=target_spec,
        }
        assert(target_spec.bit_format == .F32_LE)
        for p := 0; p < cast(int)new_data_size; {
            // For now, assume only S16 -> F32_LE
            new_data_f32 := cast([^]f32)raw_data(new_audio_buf.data)
            old_data_i16 := cast([^]i16)raw_data(audio_buf.data)
            new_i_l := p / 4
            new_i_r := p / 4 + 1
            old_i_l := (int)(cast(f32)new_i_l * (cast(f32)audio_buf.sample_rate / cast(f32)target_spec.sample_rate))
            old_i_r := (int)(cast(f32)new_i_r * (cast(f32)audio_buf.sample_rate / cast(f32)target_spec.sample_rate))
            new_data_f32[new_i_l] = util.normalize_to_range(
                cast(f32)old_data_i16[old_i_l],
                cast(f32)bits.I16_MIN,
                cast(f32)bits.I16_MAX,
                -1.0,
                1.0
            )
            new_data_f32[new_i_r] = util.normalize_to_range(
                cast(f32)old_data_i16[old_i_r],
                cast(f32)bits.I16_MIN,
                cast(f32)bits.I16_MAX,
                -1.0,
                1.0
            )
            p += 8
        }
    	// TODO: Convert to target audio spec
        return new_audio_buf, true
    }

    return audio_buf, true
}
