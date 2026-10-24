; Streaming sound for the machine: 44,100 Hz 16-bit mono through winmm's
; waveOut, one buffer per emulated frame, six in flight (about 100 ms).
; AudioPush() takes the next free buffer, has the machine mix into it and
; queues it; a frame whose buffer is not back yet is dropped, never waited for.

#AUDIO_BUFFERS = 6
#AUDIO_SAMPLES = 735          ; 44100 / 60

Global AudioDev.i, AudioOk.i
Global Dim AudioHdr.WAVEHDR(#AUDIO_BUFFERS - 1)
Global Dim *AudioMem(#AUDIO_BUFFERS - 1)

Procedure AudioOpen()
  Protected fmt.WAVEFORMATEX, i.i
  fmt\wFormatTag = #WAVE_FORMAT_PCM
  fmt\nChannels = 1
  fmt\nSamplesPerSec = 44100
  fmt\wBitsPerSample = 16
  fmt\nBlockAlign = 2
  fmt\nAvgBytesPerSec = 88200
  If waveOutOpen_(@AudioDev, #WAVE_MAPPER, @fmt, 0, 0, #CALLBACK_NULL) <> #MMSYSERR_NOERROR
    AudioOk = #False
    ProcedureReturn
  EndIf
  For i = 0 To #AUDIO_BUFFERS - 1
    *AudioMem(i) = AllocateMemory(#AUDIO_SAMPLES * 2)
    AudioHdr(i)\lpData = *AudioMem(i)
    AudioHdr(i)\dwBufferLength = #AUDIO_SAMPLES * 2
    AudioHdr(i)\dwFlags = #WHDR_DONE           ; free to fill
  Next
  AudioOk = #True
EndProcedure

Procedure AudioPush()
  Protected i.i
  If AudioOk = #False : ProcedureReturn : EndIf
  For i = 0 To #AUDIO_BUFFERS - 1
    If AudioHdr(i)\dwFlags & #WHDR_DONE
      If AudioHdr(i)\dwFlags & #WHDR_PREPARED
        waveOutUnprepareHeader_(AudioDev, @AudioHdr(i), SizeOf(WAVEHDR))
      EndIf
      InvMix(*AudioMem(i), #AUDIO_SAMPLES)
      AudioHdr(i)\dwFlags = 0
      waveOutPrepareHeader_(AudioDev, @AudioHdr(i), SizeOf(WAVEHDR))
      waveOutWrite_(AudioDev, @AudioHdr(i), SizeOf(WAVEHDR))
      ProcedureReturn
    EndIf
  Next
EndProcedure

Procedure AudioClose()
  If AudioOk
    waveOutReset_(AudioDev)
    waveOutClose_(AudioDev)
    AudioOk = #False
  EndIf
EndProcedure
