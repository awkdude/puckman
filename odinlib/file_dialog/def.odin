package dialog

OFD_Opts :: enum {
     Multiple_Files,
     Directories_Only,
}

OFD :: struct {
    // _super_string: []u8 `fmt:"s"`,
    paths: []string,
}

// Example: { "JPEG Files", "*.jpeg;*.jpg"
Filter :: struct {
    name, pattern: string
}
