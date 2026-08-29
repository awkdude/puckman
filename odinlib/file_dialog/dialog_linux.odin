package dialog

import "core:os"
import "core:strings"
import "core:fmt"
import "core:slice"
import "core:testing"
import "../platform"

@(test)
test_dialog :: proc(t: ^testing.T) {
    ofd, ok := open("", nil , {.Multiple_Files})
    if !testing.expect(t, ok, "Error with file dialog!") {
        return
    }
    defer delete_ofd(&ofd)
    testing.expect(t, len(ofd.paths) != 0, "No paths!")
    for path, i in ofd.paths {
        fmt.printfln("%d: %s, %d", i, path, len(path))
    }
}

open :: proc(
    start_dir: string,
    filters: []Filter,
    flags: bit_set[OFD_Opts] = {},
    allocator := context.temp_allocator) -> (ofd: OFD, ok: bool = true) 
{
// {{{
    MAX_RETURN_BUFFER_LEN :: 32*1024
    command_builder := strings.builder_make()
    defer strings.builder_destroy(&command_builder)
    strings.write_string(&command_builder, "zenity --file-selection --separator='|' ")
    if .Directory_Only in flags {
        strings.write_string(&command_builder, "--directory ")
    }
    if .Multiple_Files in flags {
        strings.write_string(&command_builder, "--multiple ")
    }
    if filters != nil {
        filter_buf: [1024]u8
        for filter in filters {
            str := fmt.bprintf(filter_buf[:], "--file-filter='%s | %s'  ", 
                filter.name, filter.pattern)
            strings.write_string(&command_builder, str)
            slice.fill(filter_buf[:len(str)], 0)
        }
    }
    // log.debug(strings.to_string(command_builder))
    return_buffer := make([]u8, MAX_RETURN_BUFFER_LEN, allocator)
    defer if !ok  {
        delete(return_buffer)
    }
    command_status := platform.pipe_command(strings.to_string(command_builder), return_buffer)
    return_string := strings.trim_right_null(cast(string)return_buffer)
    if command_status != 0 || len(return_string) == 0 {
        ok = false
        return
    }
    paths := strings.split(return_string, "|", allocator)
    // Exclude newline at the end
    last_idx := len(paths) - 1
    paths[last_idx] = strings.trim_space(paths[last_idx])
    ofd={paths=paths}
    return
// }}}
}

// save_file_dialog :: proc(...) -> ...
