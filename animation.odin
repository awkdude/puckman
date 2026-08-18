package main

import "core:time"

Repeat_Mode :: enum {
	None,
	Wrap,
	Ping_Pong,
}

Sprite_Animator :: struct {
	frame_index, start_frame, end_frame: int,
	frame_interval: time.Duration,
	lag: time.Duration,
	last_frame_cpu_tick: time.Tick,
	repeat_mode: Repeat_Mode,
	inc: int,
    done: bool,
}

anim_update :: proc(anim: ^Sprite_Animator, current_cpu_tick: time.Tick) {
	assert(anim.start_frame < anim.end_frame)
	if !anim.done && anim.last_frame_cpu_tick != cast(time.Tick){} {
		duration := time.tick_diff(anim.last_frame_cpu_tick, current_cpu_tick)
		anim.lag += duration
		for anim.lag > anim.frame_interval {
			anim_advance(anim)
			anim.lag -= anim.frame_interval
		}
	}
	anim.last_frame_cpu_tick = current_cpu_tick
}

anim_reset :: proc(anim: ^Sprite_Animator, current_cpu_tick: time.Tick) {
    anim.frame_index = anim.start_frame
    anim.last_frame_cpu_tick = current_cpu_tick
    anim.done = false
}

anim_advance :: proc(anim: ^Sprite_Animator) {
	anim.frame_index += anim.inc
	if anim.frame_index > anim.end_frame {
		switch anim.repeat_mode {
		case .None:
			anim.frame_index = anim.end_frame
			anim.done = true
		case .Wrap:
			anim.frame_index = anim.start_frame
		case .Ping_Pong:
			anim.frame_index = anim.end_frame - 1
			anim.inc = -1
		}
	} else if anim.frame_index < anim.start_frame {
		switch anim.repeat_mode {
		case .None:
			anim.frame_index = anim.start_frame
			anim.done = true
		case .Wrap:
			anim.frame_index = anim.end_frame
		case .Ping_Pong:
			anim.frame_index = anim.start_frame + 1
			anim.inc = 1
		}
	}
}
