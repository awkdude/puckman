package util
import "core:math"
import "core:math/fixed"
import "base:intrinsics"
import "core:time"

fixed_int :: #force_inline proc "contextless" (
    fp: $T/fixed.Fixed($Backing, $Fraction_Width)) -> i32 
    where intrinsics.type_is_integer(Backing),
    intrinsics.type_is_integer(Fraction_Width)
{
    return (i32)(fp.i >> Fraction_Width)
}

Rect :: struct {
    x, y, w, h: i32,
}

Rectf :: struct {
    x, y, w, h: f32,
}

// TODO: remove x[0, 1], y[0, 1] struct variant
BBox :: struct {
    using _: struct #raw_union {
    	using _: struct{x0, y0, x1, y1 : i32,},
    	using _: struct{min, max: vec2},
    },
}

// TODO: remove x[0, 1], y[0, 1] struct variant
BBoxf :: struct {
    using _: struct #raw_union {
    	using _: struct{x0, y0, x1, y1 : f32,},
    	using _: struct{min, max: vec2f},
    },
}

rect_to_f :: proc "contextless" (r: Rect) -> Rectf {
	return Rectf {
		x=cast(f32)r.x,
		y=cast(f32)r.y,
		w=cast(f32)r.w,
		h=cast(f32)r.h,
	}
}

rect_from_f :: proc "contextless" (r: Rectf) -> Rect {
	return Rect {
		x=cast(i32)r.x,
		y=cast(i32)r.y,
		w=cast(i32)r.w,
		h=cast(i32)r.h,
	}
}

bbox_from_f :: proc "contextless" (b: BBoxf) -> BBox {
    return BBox {
        min={
            cast(i32)b.min.x,
            cast(i32)b.min.y,
        },
        max={
            cast(i32)b.max.x,
            cast(i32)b.max.y,
        },
    }
}

vec2    :: [2]i32
vec2f   :: [2]f32
vec3f   :: [3]f32
mat2    :: matrix[2, 2]f32
mat3    :: matrix[3, 3]f32
mat4    :: matrix[4, 4]f32
Color3f :: [3]f32
Color4f :: [4]f32

PERP :: mat2{ 0, -1, 1, 0 }

// perp :: proc "contextless" (v: $T/[2]$E) -> T
// where intrinsics.type_is_numeric(E) #no_bounds_check
// {
// 	return {-v.y, v.x}
// }

color4b_to_4f :: proc(color4b: Color4b) -> Color4f {
	return Color4f {
		cast(f32)color4b.r / 255.0,
		cast(f32)color4b.g / 255.0,
		cast(f32)color4b.b / 255.0,
		cast(f32)color4b.a / 255.0,
	}
}

normalize_to_range :: proc "contextless" (value, mini, maxi, minf, maxf: $T) -> T
where intrinsics.type_is_float(T)
{
    return ((value - mini) / (maxi - mini)) * (maxf - minf) + minf;
}

point_in_rect_i :: proc "contextless" (p: vec2, rect: Rect) -> bool {
    return p.x >= rect.x && p.x < (rect.x + rect.w) &&
        p.y >= rect.y && p.y < (rect.y + rect.h)
}

point_in_rect_f :: proc "contextless" (p: vec2f, rect: Rectf) -> bool {
    return p.x >= rect.x && p.x < (rect.x + rect.w) &&
        p.y >= rect.y && p.y < (rect.y + rect.h)
}

point_in_rect :: proc {
    point_in_rect_i,
    point_in_rect_f
}

dip_to_px :: proc "contextless" (dip, dots_per_inch: i32) -> i32 {
    return i32(cast(f32)dip / 96.0 * cast(f32)dots_per_inch)
}

size_to_rect :: proc "contextless" (size: vec2) -> Rect {
    return Rect { w=size.x, h=size.y }
}


scale_vec2_s :: proc "contextless" (v: vec2, s: f32) -> vec2 {
    return cast(vec2)(cast(vec2f)v * s)
}

scale_vec2_v :: proc "contextless" (v: vec2, sv: vec2f) -> vec2 {
    return cast(vec2)(cast(vec2f)v * sv)
}

scale_vec2 :: proc {
    scale_vec2_s,
    scale_vec2_v,
}

pos_size_to_rect :: proc "contextless" (pos, size: vec2) -> Rect {
    return Rect {x=pos.x, y=pos.y, w=size.x, h=size.y}
}

// bbox rect conversion {{{
bbox_to_rect_i :: proc "contextless" (bbox: BBox) -> Rect {
    return Rect {
        x=min(bbox.x0, bbox.x1),
        y=min(bbox.y0, bbox.y1),
        w=math.abs(bbox.x1 - bbox.x0),
        h=math.abs(bbox.y1 - bbox.y0),
    }
}

bbox_to_rect_f :: proc "contextless" (bbox: BBoxf) -> Rectf {
    return Rectf {
        x=min(bbox.x0, bbox.x1),
        y=min(bbox.y0, bbox.y1),
        w=math.abs(bbox.x1 - bbox.x0),
        h=math.abs(bbox.y1 - bbox.y0),
    }
}

bbox_to_rect :: proc {
    bbox_to_rect_i,
    bbox_to_rect_f,
}

rect_to_bbox_i :: proc "contextless" (rect: Rect) -> BBox {
    bbox := BBox {
        x0=rect.x,
        y0=rect.y,
        x1=rect.x+rect.w,
        y1=rect.y+rect.h,
    }
    if rect.w < 0 {
        bbox.x0, bbox.x1 = bbox.x1, bbox.x0
    }
    if rect.h < 0 {
        bbox.y0, bbox.y1 = bbox.y1, bbox.y0
    }
    return bbox
}

rect_to_bbox_f :: proc "contextless" (rect: Rectf) -> BBoxf {
    bbox := BBoxf {
        x0=rect.x,
        y0=rect.y,
        x1=rect.x+rect.w,
        y1=rect.y+rect.h,
    }
    if rect.w < 0 {
        bbox.x0, bbox.x1 = bbox.x1, bbox.x0
    }
    if rect.h < 0 {
        bbox.y0, bbox.y1 = bbox.y1, bbox.y0
    }
    return bbox
}

rect_to_bbox :: proc  {
    rect_to_bbox_i,
    rect_to_bbox_f,
}
// }}}

rect_to_centered_i :: proc "contextless" (r: Rect) -> Rect {
    return Rect{r.x - r.w / 2, r.y - r.h / 2, r.w, r.h}
}

rect_to_centered_f :: proc "contextless" (r: Rectf) -> Rectf {
    return Rectf{r.x - r.w / 2, r.y - r.h / 2, r.w, r.h}
}

rect_to_centered :: proc {
	rect_to_centered_i,
	rect_to_centered_f,
}

rect_centered_in_rect :: proc "contextless" (inner_rect, outer_rect: Rect) -> Rect {
    outer_center := vec2{outer_rect.w / 2, outer_rect.h/2}
    return Rect {
        outer_center.x - (inner_rect.w / 2),
        outer_center.y - (inner_rect.h / 2),
        inner_rect.w,
        inner_rect.h,
    }
}

union_rect_i :: proc "contextless" (r0, r1: Rect) -> Rect {
    // TODO: This seems kinda redundant. Optimize!
    bbox0 := rect_to_bbox(r0)
    bbox1 := rect_to_bbox(r1)
    return bbox_to_rect(BBox {
        x0=min(bbox0.x0, bbox1.x0),
        y0=min(bbox0.y0, bbox1.y0),
        x1=max(bbox0.x1, bbox1.x1),
        y1=max(bbox0.y1, bbox1.y1),
    })
}

union_rect_f :: proc "contextless" (r0, r1: Rectf) -> Rectf {
    // TODO: This seems kinda redundant. Optimize!
    bbox0 := rect_to_bbox(r0)
    bbox1 := rect_to_bbox(r1)
    return bbox_to_rect(BBoxf {
        x0=min(bbox0.x0, bbox1.x0),
        y0=min(bbox0.y0, bbox1.y0),
        x1=max(bbox0.x1, bbox1.x1),
        y1=max(bbox0.y1, bbox1.y1),
    })
}

union_rect :: proc {
    union_rect_i,
    union_rect_f,
}

intersection_rect :: proc "contextless" (r0, r1: Rect) -> Rect {
    bbox0 := rect_to_bbox(r0)
    bbox1 := rect_to_bbox(r1)
    return bbox_to_rect(intersection_bbox(bbox0, bbox1))
}

intersection_bbox :: proc "contextless" (b0, b1: BBox) -> BBox {
    bbox: BBox
    bbox.min=vec2{max(b0.min.x, b1.min.x), max(b0.min.y, b1.min.y)}
    bbox.max=vec2{min(b0.max.x, b1.max.x), min(b0.max.y, b1.max.y)}
    return bbox
}

rects_collide :: proc "contextless" (r0, r1: Rectf) -> bool {
	return r0.x + r0.w >= r1.x &&
		r0.x < r1.x + r1.w &&
		r0.y + r0.h >= r1.y &&
		r0.y < r1.y + r1.h
}

Radix :: enum int {
    Binary = 2,
    Octal = 8,
    Decimal = 10,
    Hex = 16,
}

// Returns true if character is a valid digit of radix
is_digit_in_radix :: proc "contextless" (c: rune, radix: Radix) -> bool {
    result: bool
    switch radix {
    case .Binary:
        result = c == '0' || c == '1'
    case .Octal:
        result = c >= '0' && c <= '7'
    case .Decimal:
        result = c >= '0' && c <= '9'
    case .Hex:
        result = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    }
    return result
}


wrap :: proc "contextless" (x, y: $T) -> T
where intrinsics.type_is_integer(T), !intrinsics.type_is_array(T)
{
    res := x % y
    return res + y if res < 0 else res
}

// Set bit in bit array
bit_modify :: proc "contextless" (bits: []u8, #any_int bit_idx: uint, set: bool) {
    byte_idx := bit_idx / 8
    bit := bit_idx % 8
    if set {
        bits[byte_idx] |= (1 << bit)
    } else {
        bits[byte_idx] &= ~(1 << bit)
    }
}

// Test if bit is set at bit index
bit_test :: proc "contextless" (bits: []u8, #any_int bit_idx: uint) -> bool {
    byte_idx := bit_idx / 8
    bit := bit_idx % 8
    return (bits[byte_idx] & (1 << bit)) != 0
}

// Returns 0 if val < period/2 else 1
// Useful for flashing graphics
// TODO: Give better name
blink_state :: proc "contextless" (#any_int val, period: i32) -> i32 {
	return 1 if ((val % period) >= (period / 2)) else 0
}

// TODO: rename something better
time_sin :: proc "contextless" (
	freq: f32 = 1.0,
    min: f32 = 0.0,
    max: f32 = 1.0,
    phase_shift: f32 = 0.0) -> f32
{
    duration := time.duration_seconds(time.tick_since({})) * cast(f64)freq
    return normalize_to_range(
        cast(f32)math.sin(duration * math.TAU + cast(f64)phase_shift),
        -1.0,
        1.0,
        min,
        max
    )
}
