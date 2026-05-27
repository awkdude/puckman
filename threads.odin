#+ignore
package main

import "core:thread"
import "core:sync"
import "core:time"
import "core:fmt"

frame_index := 0
cond: sync.Cond
mutex: sync.Mutex
wg: sync.Wait_Group

routine :: proc(data: rawptr) {
	n := transmute(int)data
	last_frame := 0
	for {
		if sync.guard(&mutex) {
			for frame_index <= last_frame {
				sync.wait(&cond, &mutex)
			}
		}
		// Work start
		fmt.printfln("T: %v, Gen: %v", n, last_frame)
		time.sleep(1 * time.Second)
		// Work end
		last_frame = frame_index
		sync.wait_group_done(&wg)
	}
}

NUM_THREADS :: 4

main :: proc() {
	for i in 0..<NUM_THREADS {
		thread.create_and_start_with_data(transmute(rawptr)i, routine)
	}
	for {
		if sync.guard(&mutex) {
			sync.wait_group_add(&wg, NUM_THREADS)
			// fmt.println("go!")
			frame_index += 1
			sync.broadcast(&cond)
		}
		sync.wait(&wg)
		fmt.printfln("done w/ %v", frame_index)
	}
}
