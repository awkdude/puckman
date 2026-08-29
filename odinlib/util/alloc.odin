package util

import "core:mem"

import "core:log"
import "core:time"
import "core:path/filepath"
import "base:runtime"


CC_NORMAL  :: "\x1B[0m"
CC_RED     :: "\x1B[31m"
CC_GREEN   :: "\x1B[32m"
CC_YELLOW  :: "\x1B[33m"
CC_BLUE    :: "\x1B[34m"
CC_MAGENTA :: "\x1B[35m"
CC_CYAN    :: "\x1B[36m"
CC_WHITE   :: "\x1B[37m"

Logging_Allocator :: struct {
    backing: runtime.Allocator,
    is_temp: bool,
}

logging_allocator_proc :: proc(
    allocator_data:  rawptr, 
    mode:            runtime.Allocator_Mode, 
    size, alignment: int, 
    old_memory:      rawptr, 
    old_size:        int, 
    loc := #caller_location) -> (alloc_mem: []u8, alloc_err: runtime.Allocator_Error)
{
    context.logger.options = {}
    data := cast(^Logging_Allocator)allocator_data
    buf: [16]u8

    alloc_mem = data.backing.procedure(
        data.backing.data,
        mode,
        size,
        alignment,
        old_memory,
        old_size,
        loc
    ) or_return
    if mode == .Alloc {
        log.debugf(
            CC_CYAN + "[ALLOC] --- " + CC_NORMAL +
            "[%v] [%v:%v:%v()] %M -> %p",
            time.time_to_string_hms(time.now(), buf[:]),
            filepath.base(loc.file_path),
            loc.line,
            loc.procedure,
            size,
            raw_data(alloc_mem)
        )
    } else if mode == .Free {
        log.debugf(
            CC_MAGENTA + "[FREED] --- " + CC_NORMAL +
            "[%v] [%v:%v:%v()] %p",
            time.time_to_string_hms(time.now(), buf[:]),
            filepath.base(loc.file_path),
            loc.line,
            loc.procedure,
            old_memory,
        )
    }
    return alloc_mem, alloc_err
}
logging_allocator_init :: proc(
    log_alloc: ^Logging_Allocator, 
    backing_allocator: runtime.Allocator) 
{
    log_alloc.backing = backing_allocator
} 

logging_allocator :: proc(log_alloc: ^Logging_Allocator) -> runtime.Allocator {
    return runtime.Allocator {
        data=log_alloc,
        procedure=logging_allocator_proc,
    }
}
