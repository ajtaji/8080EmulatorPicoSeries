; Streaming sound for the machine: 44,100 Hz 16-bit through the Neon Arcade
; engine's sound service (GL_AudioOpen / Next / Play: waveOut on Windows,
; ALSA's default device on Linux), one buffer per emulated frame, six in
; flight (about 100 ms). AudioPush() takes the next free buffer, has the
; machine mix into it and queues it; a frame whose buffer is not back yet is
; dropped, never waited for. The machine mixes mono; the engine takes stereo
; pairs, so each sample goes to both sides. Include after the engine.

#AUDIO_BUFFERS = 6
#AUDIO_SAMPLES = 735          ; 44100 / 60

Global AudioOk.i, *AudioMono

Procedure AudioOpen()
  AudioOk = GL_AudioOpen(44100, #AUDIO_SAMPLES, #AUDIO_BUFFERS)
  If AudioOk And *AudioMono = 0 : *AudioMono = AllocateMemory(#AUDIO_SAMPLES * 2) : EndIf
EndProcedure

; #True when a frame's buffer was queued.
Procedure.i AudioPush()
  Protected *buf, i.i, v.w
  If AudioOk = #False : ProcedureReturn #False : EndIf
  *buf = GL_AudioNext()
  If *buf = 0 : ProcedureReturn #False : EndIf
  InvMix(*AudioMono, #AUDIO_SAMPLES)
  For i = 0 To #AUDIO_SAMPLES - 1
    v = PeekW(*AudioMono + i * 2)
    PokeW(*buf + i * 4, v) : PokeW(*buf + i * 4 + 2, v)
  Next
  GL_AudioPlay(*buf)
  ProcedureReturn #True
EndProcedure

Procedure AudioClose()
  If AudioOk
    GL_AudioClose()
    AudioOk = #False
  EndIf
EndProcedure
