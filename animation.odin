package main

import "core:time"

Repeat_Mode :: enum {
	None,
	Wrap,
	Ping_Pong,
}

Sprite_Animatior :: struct {
	frame_index, start_frame, end_frame: int,
	frame_interval: time.Duration,
	lag: time.Duration,
	last_frame_tick: time.Tick,
	repeat_mode: Repeat_Mode,
	// May consider using enum for this field
	inc: int,
}

anim_update :: proc(anim: ^Sprite_Animatior, current_tick: time.Tick) {
	assert(anim.start_frame < anim.end_frame)
	if anim.last_frame_tick != cast(time.Tick){} {
		duration := time.tick_diff(anim.last_frame_tick, current_tick)
		anim.lag += duration
		for anim.lag > anim.frame_interval {
			anim_advance(anim)
			anim.lag -= anim.frame_interval
		}
	}
	anim.last_frame_tick = current_tick
}

anim_advance :: proc(anim: ^Sprite_Animatior) {
	anim.frame_index += anim.inc
	if anim.frame_index > anim.end_frame {
		switch anim.repeat_mode {
		case .None:
			anim.frame_index = anim.end_frame
			anim.inc = 0
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
			anim.inc = 0
		case .Wrap:
			anim.frame_index = anim.end_frame
		case .Ping_Pong:
			anim.frame_index = anim.start_frame + 1
			anim.inc = 1
		}
	}
}
