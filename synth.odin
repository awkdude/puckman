package main

import "odinlib:util"

COMMAND_BUFFER_SIZE :: 1024

Synthesizer :: struct {
    voices: [3][COMMAND_BUFFER_SIZE]Synth_Command,
}

// NOTE: subject to change
Synth_Command :: struct {
    waveform: Waveform_Type,
    freq_hz: int,
    sweep_freq_hz: int,
    volume, sweep_volume: f32,
}

Modulator :: union {
    Modulator_Func,
    Modulator_Data,
}

Modulator_Func :: #type proc(a, b, t: f32) -> f32
Modulator_Data :: []f32

synth_square :: proc(synth: ^Synthesizer) {

}

Waveform_Type :: enum {
    Square,
    Sine,
    Triangle,
    Sawtooth,
}

// Render audio samples to provided audio buffer
synth_to_output :: proc(synth: ^Synthesizer, audio_buffer: util.Audio_Buffer) {
    // TODO:
}
