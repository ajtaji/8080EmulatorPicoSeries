; Checks the desktop sound path without making a sound: opens waveOut, sends
; one second of silence (60 one-frame buffers) through AudioPush exactly as
; the window does, and checks the device hands every buffer back.
;   pbcompilerc audio_check.pb /CONSOLE /EXE audio_check.exe
XIncludeFile "machine.pbi"
XIncludeFile "audio.pbi"
OpenConsole()
Define i.i, t.q, done.i, sent.i
AudioOpen()
If AudioOk = 0
  PrintN("audio check FAIL: waveOutOpen refused (no output device?)")
  End 1
EndIf
For i = 0 To 3 : InvTones(i)\Volume = 0 : Next   ; silence
t = ElapsedMilliseconds()
While sent < 60 And ElapsedMilliseconds() - t < 5000
  done = 0
  For i = 0 To #AUDIO_BUFFERS - 1
    If AudioHdr(i)\dwFlags & #WHDR_DONE : done + 1 : EndIf
  Next
  If done > 0 : AudioPush() : sent + 1 : EndIf
  Delay(2)
Wend
Delay(200)
done = 0
For i = 0 To #AUDIO_BUFFERS - 1
  If AudioHdr(i)\dwFlags & #WHDR_DONE : done + 1 : EndIf
Next
t = ElapsedMilliseconds() - t
AudioClose()
If sent = 60 And done = #AUDIO_BUFFERS
  PrintN("audio check PASS: 60 buffers played in " + Str(t) + " ms, all " + Str(done) + " returned")
  End 0
EndIf
PrintN("audio check FAIL: sent " + Str(sent) + " of 60, " + Str(done) + " of " + Str(#AUDIO_BUFFERS) + " returned, " + Str(t) + " ms")
End 1
