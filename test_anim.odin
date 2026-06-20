#+test

package main

import "core:testing"

@(test)
order :: proc(t: ^testing.T) {
	{
		anim := Sprite_Animatior {
			repeat_mode=.None,
			end_frame=2,
			inc=1,
		}
		expected_frames := [?]int {0, 1, 2, 2, 2, 2}
		for frame, i in expected_frames {
			testing.expectf(t, anim.frame_index == frame, "Not equal at index %v: %v != %v", i, anim.frame_index, frame)
			anim_advance(&anim)
		}
	}

	{
		anim := Sprite_Animatior {
			repeat_mode=.Ping_Pong,
			end_frame=2,
			inc=1,
		}
		expected_frames := [?]int {0, 1, 2, 1, 0, 1}
		for frame, i in expected_frames {
			testing.expectf(t, anim.frame_index == frame, "Not equal at index %v: %v != %v", i, anim.frame_index, frame)
			anim_advance(&anim)
		}
	}
    {
		anim := Sprite_Animatior {
			repeat_mode=.Wrap,
			end_frame=2,
			inc=1,
		}
		expected_frames := [?]int {0, 1, 2, 0, 1, 2, 0}
		for frame, i in expected_frames {
			testing.expectf(t, anim.frame_index == frame, "Not equal at index %v: %v != %v", i, anim.frame_index, frame)
			anim_advance(&anim)
		}
	}
}
