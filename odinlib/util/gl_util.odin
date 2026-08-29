package util

import "core:os"
import "core:log"
import "core:strings"
import "core:math/linalg"
import gl "vendor:OpenGL"

default_shader_program_2d, default_shader_program_3d: Maybe(u32)

Source_Shader :: struct {
    /* TODO:
    using source: #raw_union {
        using file: struct {
            vertex_source_path, fragment_source_path: string,
        },
        using source: struct {
            vertex_source, fragment_source,
        },
    },
    source_type: enum {
        File,
        String,
    },
    */
    vertex_source_path, fragment_source_path: string,
    program: u32,
    use_2d_default: bool,
    userdata: rawptr,
    on_update_proc: proc(program: u32, userdata: rawptr),
}

source_shader_update :: proc(src_shader: ^Source_Shader) -> Shader_Error {
    // {{{
    if src_shader.vertex_source_path == "" {
        log.errorf("No vertex shader source path!")
        return .No_Source_Path
    }
    if src_shader.fragment_source_path == "" {
        log.errorf("No fragment shader source path!")
        return .No_Source_Path
    }
    new_program, err := shader_program_from_file(
        src_shader.vertex_source_path,
        src_shader.fragment_source_path,
    )
    if err == nil {
        if src_shader.program != 0 && gl.IsProgram(src_shader.program) {
            gl.DeleteProgram(src_shader.program)
            src_shader.program = 0
        }
        src_shader.program = new_program
        if src_shader.on_update_proc != nil {
            gl.UseProgram(src_shader.program)
            src_shader.on_update_proc(src_shader.program, src_shader.userdata)
        }
    } else {
        if src_shader.program == 0 || !gl.IsProgram(src_shader.program) {
            log.debugf(
                "Using default %v shader",
                "2d" if src_shader.use_2d_default else "3d"
            )
            if src_shader.use_2d_default {
                src_shader.program = get_default_program_2d()
            } else {
                src_shader.program = get_default_program_3d()
            }
        } else {
            log.debug("Using current shader program")
        }
    }
    return err
    // }}}
}

Shader_Error :: enum {
    None,
    No_Source_Path,
    File_Not_Found,
    Compile_Error,
    Link_Error,
}

Shader_Type :: enum {
    Vertex,
    Fragment,
}

shader_program_from_file :: proc(
    vertex_source_path,
    fragment_source_path: string,
    allocator := context.temp_allocator
) -> (shader_program: u32, program_err: Shader_Error)
{
    // {{{
    shader_program = 0
    program_err = nil
    vertex_source, v_err := os.read_entire_file_from_path(vertex_source_path, allocator)
    if v_err != nil {
        log.errorf("'%v' does not exist!", vertex_source_path)
        program_err = .File_Not_Found
        return
    }
    defer delete(vertex_source, allocator)
    fragment_source, f_err := os.read_entire_file_from_path(fragment_source_path, allocator)
    if f_err != nil {
        log.errorf("'%v' does not exist!", fragment_source_path)
        program_err = .File_Not_Found
        return
    }
    defer delete(fragment_source, allocator)
    shader_program, program_err = shader_program_from_source(
        transmute(string)vertex_source,
        transmute(string)fragment_source
    )
    if program_err != nil {
        log.errorf("%v, %v", vertex_source_path, fragment_source_path)
    }
    return
    // }}}
}

shader_program_from_source :: proc(
    vertex_source, fragment_source: string,
) -> (shader_program: u32, program_err: Shader_Error)
{
// {{{
    shader_program = 0
    program_err = nil
    vertex_shader := compile_shader(.Vertex, vertex_source) or_return
    defer gl.DeleteShader(vertex_shader)
    fragment_shader := compile_shader(.Fragment, fragment_source) or_return
    defer gl.DeleteShader(fragment_shader)
    shader_program = gl.CreateProgram()
    gl.AttachShader(shader_program, vertex_shader)
    defer gl.DetachShader(shader_program, vertex_shader)
    gl.AttachShader(shader_program, fragment_shader)
    defer gl.DetachShader(shader_program, fragment_shader)
    gl.LinkProgram(shader_program)
    success: i32
    gl.GetProgramiv(shader_program, gl.LINK_STATUS, &success)
    info_log: [512]u8
    if success == 0 {
        gl.GetProgramInfoLog(shader_program, size_of(info_log), nil, raw_data(info_log[:]))
        log.errorf("Shader program: %v", transmute(string)info_log[:])
        gl.DeleteProgram(shader_program)
        program_err = .Link_Error
        return
    }
    return
// }}}
}

compile_shader :: proc(type: Shader_Type, source: string) -> (u32, Shader_Error) {
// {{{
    gl_shader_type: u32
    shader_str: string
    switch type {
    case .Vertex:
        gl_shader_type = gl.VERTEX_SHADER
        shader_str = "Vertex"
    case .Fragment:
        gl_shader_type = gl.FRAGMENT_SHADER
        shader_str = "Fragment"
    }
    shader := gl.CreateShader(gl_shader_type)
    source_cstr := cstring(raw_data(source))
    source_len := cast(i32)len(source)
    gl.ShaderSource(shader, 1, &source_cstr, &source_len)
    gl.CompileShader(shader)
    success: i32
    gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success)
    info_log: [512]u8
    if success == 0 {
        gl.GetShaderInfoLog(shader, size_of(info_log), nil, raw_data(info_log[:]))
        log.errorf(
            "%v shader: %v",
            shader_str,
            transmute(string)info_log[:]
        )
        return 0, .Compile_Error
    }
    return shader, nil
// }}}
}

@(private)
location :: #force_inline proc(shader: u32, name: string) -> i32 {
    return gl.GetUniformLocation(shader, strings.unsafe_string_to_cstring(name))
}

// shader uniform procs {{{
shader_uniform_int :: #force_inline proc(shader: u32, name: string, #any_int v: i32) {
    gl.Uniform1i(location(shader, name), v)
}

// @(private)
// shader_uniform_uint :: #force_inline proc(shader: u32, name: string, v: u32) {
//     gl.Uniform1ui(location(shader, name), v)
// }

@(private)
shader_uniform_ivec :: #force_inline proc(shader: u32, name: string, v: []i32) {
    gl.Uniform1iv(location(shader, name), cast(i32)len(v), raw_data(v))
}

@(private)
shader_uniform_float :: #force_inline proc(shader: u32, name: string, v: f32) {
    gl.Uniform1f(location(shader, name), v)
}

@(private)
shader_uniform_vec3 :: #force_inline proc(shader: u32, name: string, v: [3]f32) {
    v := v
    gl.Uniform3fv(location(shader, name), 1, raw_data(v[:]))
}

@(private)
shader_uniform_vec4 :: #force_inline proc(shader: u32, name: string, v: [4]f32) {
    v := v
    gl.Uniform4fv(location(shader, name), 1, raw_data(v[:]))
}

@(private)
shader_uniform_mat3 :: #force_inline proc(shader: u32, name: string, m: ^matrix[3, 3]f32) {
    gl.UniformMatrix3fv(
        location(shader, name),
        1,
        false,
        linalg.matrix_to_ptr(m)
    )
}

@(private)
shader_uniform_mat4 :: #force_inline proc(shader: u32, name: string, m: ^matrix[4, 4]f32) {
    gl.UniformMatrix4fv(
        location(shader, name),
        1,
        false,
        linalg.matrix_to_ptr(m)
    )
}
// }}}

shader_uniform :: proc{
    shader_uniform_int,
    // shader_uniform_uint,
    shader_uniform_ivec,
    shader_uniform_float,
    shader_uniform_mat3,
    shader_uniform_mat4,
    shader_uniform_vec3,
    shader_uniform_vec4,
}

// default shaders {{{
@(private)
get_default_program_2d :: proc() -> u32 {
    program: u32
    if default_program, ok := default_shader_program_2d.?; ok {
        program = default_program
    } else {
        new_program, err := shader_program_from_source(
            default_vertex_shader_2d,
            default_fragment_shader,
        )
        assert(err == nil)
        program = new_program
    }
    return program
}

@(private)
get_default_program_3d :: proc() -> u32 {
    program: u32
    if default_program, ok := default_shader_program_3d.?; ok {
        program = default_program
    } else {
        new_program, err := shader_program_from_source(
            default_vertex_shader_3d,
            default_fragment_shader,
        )
        assert(err == nil)
        program = new_program
    }
    return program
}

default_vertex_shader_2d := `
#version 330 core

layout (location = 0) in vec2 a_pos;

uniform mat4 u_proj;

void main() {
    gl_Position = u_proj * vec4(a_pos, 1.0);
}
`

default_vertex_shader_3d := `
#version 330 core

layout (location = 0) in vec3 a_pos;

uniform mat4 u_proj, u_view, u_model;

void main() {
    gl_Position = u_proj * u_view * u_model * vec4(a_pos, 1.0);
}
`

default_fragment_shader := `
#version 330 core

out vec4 frag_color;

void main() {
    frag_color = vec4(1.0);
}
`
// }}}

Texture_Options :: struct {
    min_filter_linear, max_filter_linear: bool,
    generate_mipmap: bool,
}

create_texture_from_pixmap :: proc(
    pixmap: Pixmap,
    tex_options: Texture_Options = {}) -> (u32, bool) #optional_ok
{
// {{{
    // TODO: check errors?
    tex_id: u32
    gl.GenTextures(1, &tex_id)
    gl.BindTexture(gl.TEXTURE_2D, tex_id)
    gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)
    tex_format: i32
    pixmap_format: u32
    if pixmap.format.bytes_per_pixel == 1 {
        tex_format = gl.RED
        pixmap_format = gl.RED
    } else if pixmap.format.bytes_per_pixel == 4 {
        tex_format = gl.RGBA8
        pixmap_format = gl.BGRA
    } else {
        log.panicf("Invalid BPP provided (%v)", pixmap.format.bytes_per_pixel)
    }
    min_filter := cast(i32)(gl.LINEAR if tex_options.min_filter_linear else gl.NEAREST)
    max_filter := cast(i32)(gl.LINEAR if tex_options.max_filter_linear else gl.NEAREST)
    gl.TexImage2D(
        gl.TEXTURE_2D,
        0,
        tex_format,
        pixmap.w,
        pixmap.h,
        0,
        pixmap_format,
        gl.UNSIGNED_BYTE,
        pixmap.pixels,
    )
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, min_filter)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, max_filter)
    if tex_options.generate_mipmap {
        gl.GenerateMipmap(gl.TEXTURE_2D)
    }
    gl.BindTexture(gl.TEXTURE_2D, 0)
    return tex_id, true
// }}}
}


projection_mat_from_window_size :: proc "contextless" (window_size: vec2) -> mat4 {
    return linalg.matrix_ortho3d(
        0.0,
        cast(f32)window_size.x,
        cast(f32)window_size.y,
        0.0,
        -1.0,
        1.0
    )
}
