; Space Invaders (Taito 8080) hardware around the core, for the desktop.
;
;   $0000-$1FFF  8 KB ROM (writes ignored)
;   $2000-$23FF  work RAM
;   $2400-$3FFF  video RAM, 1 bpp: byte $2400 + x*32 + (y>>3), bit (y&7),
;                x = 0..223 across, y = 0..255 up from the bottom of the
;                upright (rotated) screen
;   $4000-$FFFF  mirrors of $0000-$3FFF
; 2 MHz, 33,333 cycles a 60 Hz frame: RST 1 at mid-screen, RST 2 at VBLANK.
; IN 1 / IN 2 inputs, OUT 2 / OUT 4 / IN 3 the shift register, OUT 3 / OUT 5
; the original sound effects, OUT 6 the watchdog. For the demos, a 4-channel
; tone device at OUT $10-$1F (not on the original board): channel c at
; $10 + 4c: +0 period low, +1 period high (bits 0-3), +2 volume 0-15,
; +3 wave (0 square, 1 25% pulse, 2 triangle, 3 noise); frequency =
; 62500 / (period + 1) Hz.

#INV_FRAME_CYCLES = 33333
#INV_MID_CYCLES = 16667
#INV_RATE = 44100

; Input bits (IN 1 unless noted).
#INV_COIN = $01
#INV_P2START = $02
#INV_P1START = $04
#INV_P1FIRE = $10
#INV_P1LEFT = $20
#INV_P1RIGHT = $40

Structure InvTone
  Period.i
  Volume.i
  Wave.i
  Phase.l              ; 16.16 fixed point, one cycle = $10000
EndStructure

Global InvShift.i, InvShiftAmt.i, InvIn1.i, InvIn2.i, InvSound3.i, InvSound5.i, InvSoundPrev3.i, InvSoundPrev5.i
Global InvCycleDebt.i, InvFrames.q, InvLoaded$, InvWatchdog.i
Global Dim InvTones.InvTone(3)
Global InvNoise.l = $1234
; Original effects: a timer and a phase each.
Global Dim InvFxTime.i(9)
Global Dim InvFxPhase.l(9)
Global Dim InvFleetHz.i(3)
InvFleetHz(0) = 98 : InvFleetHz(1) = 86 : InvFleetHz(2) = 76 : InvFleetHz(3) = 68

Procedure InvMap()
  Protected p.i
  For p = 0 To 255
    If p < $20
      CpuMemMap(p) = 1                 ; ROM: read directly, writes go to the trap (ignored)
    ElseIf p < $40
      CpuMemMap(p) = 3                 ; RAM and video RAM
    Else
      CpuMemMap(p) = 0                 ; mirrors: both ways through the trap
    EndIf
  Next
EndProcedure

Procedure.i InvReadTrap(adr.i)
  ProcedureReturn M(adr & $3FFF)
EndProcedure
Procedure InvWriteTrap(adr.i, value.i)
  adr & $3FFF
  If adr >= $2000
    M(adr) = value
  EndIf
EndProcedure

; Instruction fetches read M directly, so the ROM is copied into every
; mirror once: code jumping into a mirror still finds its bytes.
Procedure InvMirrorRom()
  Protected base.i
  For base = $4000 To $C000 Step $4000
    CopyMemory(@M(0), @M(base), $2000)
  Next
EndProcedure

Procedure InvReset()
  Protected i.i
  MachineSelect(#MACHINE_INVADERS)
  InvMap()
  InvMirrorRom()
  For i = $2000 To $3FFF : M(i) = 0 : Next
  CpuReset()
  InvShift = 0 : InvShiftAmt = 0 : InvIn1 = 0 : InvIn2 = 0 : InvSound3 = 0 : InvSound5 = 0
  InvSoundPrev3 = 0 : InvSoundPrev5 = 0 : InvCycleDebt = 0 : InvFrames = 0
  For i = 0 To 3 : InvTones(i)\Period = 0 : InvTones(i)\Volume = 0 : InvTones(i)\Wave = 0 : Next
  For i = 0 To 9 : InvFxTime(i) = 0 : Next
EndProcedure

; One 8 KB image, or the four 2 KB chips invaders.h, .g, .f, .e in a folder.
Procedure.i InvLoadRom(path$)
  Protected f.i, size.i, i.i, part$
  For i = 0 To $3FFF : M(i) = 0 : Next
  If FileSize(path$) = -2
    For i = 0 To 3
      part$ = path$ + "\invaders." + Mid("hgfe", i + 1, 1)
      f = ReadFile(#PB_Any, part$)
      If f = 0 : ProcedureReturn 0 : EndIf
      If Lof(f) <> $800 : CloseFile(f) : ProcedureReturn 0 : EndIf
      ReadData(f, @M(i * $800), $800)
      CloseFile(f)
    Next
  Else
    f = ReadFile(#PB_Any, path$)
    If f = 0 : ProcedureReturn 0 : EndIf
    size = Lof(f)
    If size < 1 Or size > $2000 : CloseFile(f) : ProcedureReturn 0 : EndIf
    ReadData(f, @M(0), size)
    CloseFile(f)
  EndIf
  InvLoaded$ = path$
  InvReset()
  ProcedureReturn 1
EndProcedure

Procedure.i InvPortIn(port.i)
  Select port
    Case 0 : ProcedureReturn $0E
    Case 1 : ProcedureReturn (InvIn1 | $08) & 255
    Case 2 : ProcedureReturn InvIn2 & 255
    Case 3 : ProcedureReturn (InvShift >> (8 - InvShiftAmt)) & 255
  EndSelect
  ProcedureReturn 0
EndProcedure

Procedure InvPortOut(port.i, value.i)
  Protected c.i, r.i
  Select port
    Case 2 : InvShiftAmt = value & 7
    Case 4 : InvShift = ((value & 255) << 8) | (InvShift >> 8)
    Case 3 : InvSound3 = value
    Case 5 : InvSound5 = value
    Case 6 : InvWatchdog + 1
    Case $10 To $1F
      c = (port - $10) >> 2 : r = port & 3
      Select r
        Case 0 : InvTones(c)\Period = (InvTones(c)\Period & $F00) | (value & 255)
        Case 1 : InvTones(c)\Period = (InvTones(c)\Period & $FF) | ((value & 15) << 8)
        Case 2 : InvTones(c)\Volume = value & 15
        Case 3 : InvTones(c)\Wave = value & 3
      EndSelect
  EndSelect
EndProcedure

; One 60 Hz frame: run to mid-screen, RST 1, run to VBLANK, RST 2. The
; cycles a window overshoots are taken off the next one.
Procedure InvRunFrame()
  Protected n.i
  n = #INV_MID_CYCLES - InvCycleDebt
  If n > 0 : InvCycleDebt = CpuRun(n) - n : Else : InvCycleDebt = -n : EndIf
  InvCycleDebt + CpuInterrupt($CF)
  n = #INV_FRAME_CYCLES - #INV_MID_CYCLES - InvCycleDebt
  If n > 0 : InvCycleDebt = CpuRun(n) - n : Else : InvCycleDebt = -n : EndIf
  InvCycleDebt + CpuInterrupt($D7)
  InvFrames + 1
EndProcedure

; The screen, upright (224 x 256), into a 32-bit buffer, bottom row first
; (the order glTexImage2D and Windows bitmaps use), with the colour overlay
; of the original cabinet: a red band near the top, green near the bottom.
Procedure InvRender(*buf)
  Protected x.i, j.i, b.i, k.i, y.i, row.i, col.l, *p.Long
  For x = 0 To 223
    For j = 0 To 31
      b = M($2400 + x * 32 + j)
      For k = 0 To 7
        y = j * 8 + k                  ; 0 = bottom of the upright screen
        row = 255 - y                  ; 0 = top
        If b & (1 << k)
          If row >= 32 And row < 64
            col = $FFFF3040            ; red ($AARRGGBB is B,G,R,A in memory: GL_BGRA)
          ElseIf row >= 184 And row < 240
            col = $FF30FF60
          ElseIf row >= 240 And x >= 16 And x < 134
            col = $FF30FF60
          Else
            col = $FFF0F0F0
          EndIf
        Else
          col = $FF000000
        EndIf
        *p = *buf + (y * 224 + x) * 4
        *p\l = col
      Next
    Next
  Next
EndProcedure

; Sound: the demo's tone channels and simple synthesized stand-ins for the
; original board's discrete effects, mixed to 16-bit mono.
Procedure.i InvToneSample(*t.InvTone)
  Protected stp.i, s.i, ph.i
  If *t\Volume = 0 Or *t\Period = 0 : ProcedureReturn 0 : EndIf
  stp = (62500 * 65536) / ((*t\Period + 1) * #INV_RATE)
  *t\Phase = (*t\Phase + stp) & $FFFF
  ph = *t\Phase
  Select *t\Wave
    Case 0 : s = (Bool(ph < $8000) * 2 - 1) * 127
    Case 1 : s = (Bool(ph < $4000) * 2 - 1) * 127
    Case 2
      If ph < $8000 : s = (ph >> 7) - 128 : Else : s = 127 - ((ph - $8000) >> 7) : EndIf
    Default
      If ph < stp                    ; a new noise value once per period
        InvNoise = (InvNoise >> 1) ! (-(InvNoise & 1) & $B400)
      EndIf
      s = ((InvNoise & 1) * 2 - 1) * 127
  EndSelect
  ProcedureReturn s * *t\Volume
EndProcedure

Procedure.i InvSquare(i.i, hz.f, vol.i)
  InvFxPhase(i) = (InvFxPhase(i) + Int(hz * 65536 / #INV_RATE)) & $FFFF
  ProcedureReturn (Bool(InvFxPhase(i) < $8000) * 2 - 1) * vol
EndProcedure

Procedure.i InvNoiseSample(vol.i)
  InvNoise = (InvNoise >> 1) ! (-(InvNoise & 1) & $B400)
  ProcedureReturn ((InvNoise & 1) * 2 - 1) * vol
EndProcedure

Procedure InvMix(*out, samples.i)
  Protected i.i, c.i, v.i, t.i, *w.Word
  ; Effects start on a rising bit (one-shots) or sound while held (loops).
  If (InvSound3 & 2) And Not (InvSoundPrev3 & 2) : InvFxTime(1) = #INV_RATE / 4 : EndIf
  If (InvSound3 & 4) And Not (InvSoundPrev3 & 4) : InvFxTime(2) = #INV_RATE : EndIf
  If (InvSound3 & 8) And Not (InvSoundPrev3 & 8) : InvFxTime(3) = #INV_RATE / 6 : EndIf
  If (InvSound3 & 16) And Not (InvSoundPrev3 & 16) : InvFxTime(4) = #INV_RATE / 2 : EndIf
  For c = 0 To 3
    If (InvSound5 & (1 << c)) And Not (InvSoundPrev5 & (1 << c)) : InvFxTime(5 + c) = #INV_RATE / 12 : EndIf
  Next
  If (InvSound5 & 16) And Not (InvSoundPrev5 & 16) : InvFxTime(9) = #INV_RATE / 2 : EndIf
  InvSoundPrev3 = InvSound3 : InvSoundPrev5 = InvSound5
  For i = 0 To samples - 1
    v = 0
    For c = 0 To 3 : v + InvToneSample(@InvTones(c)) : Next
    If InvSound3 & 1                            ; UFO: a warble while the bit is held
      v + InvSquare(0, 560 + 120 * Sin(i * 0.0025 + InvFrames * 0.3), 900)
    EndIf
    If InvFxTime(1) > 0                         ; shot: a falling buzz
      t = InvFxTime(1) : InvFxTime(1) - 1
      v + InvSquare(1, 300 + t / 20.0, 1100) / 2 + InvNoiseSample(500) * t / (#INV_RATE / 4)
    EndIf
    If InvFxTime(2) > 0                         ; the player dies: noise dying away
      t = InvFxTime(2) : InvFxTime(2) - 1
      v + InvNoiseSample(2200) * t / #INV_RATE
    EndIf
    If InvFxTime(3) > 0                         ; an invader dies: a short crack
      t = InvFxTime(3) : InvFxTime(3) - 1
      v + InvNoiseSample(1800) * t / (#INV_RATE / 6)
    EndIf
    If InvFxTime(4) > 0                         ; extra life: a high chirp
      InvFxTime(4) - 1
      v + InvSquare(4, 1800, 700)
    EndIf
    For c = 0 To 3                              ; the fleet's four footsteps
      If InvFxTime(5 + c) > 0
        InvFxTime(5 + c) - 1
        v + InvSquare(5 + c, InvFleetHz(c), 1600)
      EndIf
    Next
    If InvFxTime(9) > 0                         ; UFO hit: a rising sweep
      t = InvFxTime(9) : InvFxTime(9) - 1
      v + InvSquare(9, 1600 - t / 30.0, 900)
    EndIf
    If v > 32767 : v = 32767 : ElseIf v < -32768 : v = -32768 : EndIf
    *w = *out + i * 2 : *w\w = v
  Next
EndProcedure
