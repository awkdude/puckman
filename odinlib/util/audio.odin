package util

Audio_Buffer :: struct {
    data: []u8,
    sample_count: uint,
    using spec: Audio_Spec,
}

Audio_Spec :: struct {
	num_channels, sample_rate: i32,
    bit_format: Audio_Format,
}

Audio_Format :: enum i32 {
    U8,
    S16,
    F32_LE,
}

bytes_per_sample_from_format :: proc "contextless" (bit_format: Audio_Format) -> uint {
    switch bit_format {
    case .U8:
        return 1
    case .S16:
        return 2
    case .F32_LE:
        return 4
    }
    return 0
}
