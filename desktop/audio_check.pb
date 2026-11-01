; Checks the desktop sound path without making a sound: opens the engine's
; sound service (waveOut on Windows, ALSA on Linux), sends one second of
; silence (60 one-frame buffers) through AudioPush exactly as the window does,
; and checks the device takes them all at the rate it plays them.
;   Windows: pbcompilerc audio_check.pb /CONSOLE /EXE audio_check.exe
;   Linux:   pbcompilerc audio_check.pb -cl -o audio_check
CompilerIf Defined(GL_ENGINE_DIR$, #PB_Constant) = 0
  #GL_ENGINE_DIR$ = "../../Neon-Arcade-Dispay-Engine/"   ; the engine cloned beside this repository
CompilerEndIf
XIncludeFile "machine.pbi"
IncludePath #GL_ENGINE_DIR$
XIncludeFile "GlTypes.pbi"
XIncludeFile "GlUtilities.pbi"
IncludePath ""
XIncludeFile "audio.pbi"
OpenConsole()
Define i.i, t.q, sent.i
AudioOpen()
If AudioOk = 0
  PrintN("audio check FAIL: the sound device would not open (no output device?)")
  End 1
EndIf
For i = 0 To 3 : InvTones(i)\Volume = 0 : Next   ; silence
t = ElapsedMilliseconds()
While sent < 60 And ElapsedMilliseconds() - t < 5000
  If AudioPush() : sent + 1 : Else : Delay(2) : EndIf
Wend
t = ElapsedMilliseconds() - t
AudioClose()
; Six buffers go at once; the other 54 only as the device plays them (54 frames, 900 ms).
If sent = 60 And t >= 700
  PrintN("audio check PASS: 60 buffers played in " + Str(t) + " ms")
  End 0
EndIf
PrintN("audio check FAIL: sent " + Str(sent) + " of 60 in " + Str(t) + " ms")
End 1
