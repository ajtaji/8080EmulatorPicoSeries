; Runs a Space Invaders machine ROM without a window, for checks:
;   invaders_cli <rom file | folder of invaders.h/g/f/e> [frames] [--ports] [--png file] [--right a-b] [--fire a-b]
;                [--peek address count]   (decimal or $hex; prints those RAM bytes after the run)
;                [--checksum]   (video RAM as h = h * 31 + byte, 32-bit signed - the Pico prints the same)
; Prints the frames run, the instruction and cycle counts, the SHA-256 of
; video RAM and (--ports) every OUT with its frame. --right / --fire hold
; that control for frames a to b. Exit 0, or 1 if the ROM cannot be read.
;   pbcompilerc invaders_cli.pb /CONSOLE /OPTIMIZER /EXE invaders_cli.exe
XIncludeFile "machine.pbi"
UseSHA2Fingerprint()
UsePNGImageEncoder()
OpenConsole()
Define rom$ = ProgramParameter(0), frames.i = 600, i.i, arg$, png$, f.i, cycles.q, rightA.i = -1, rightB.i = -1, fireA.i = -1, fireB.i = -1
Define *buf, img.i, x.i, y.i, *px.Long, peekAt.i = -1, peekN.i, line$, sum.l, wantSum.i
For i = 1 To CountProgramParameters() - 1
  arg$ = ProgramParameter(i)
  Select LCase(arg$)
    Case "--ports" : InvLogPorts = 1
    Case "--checksum" : wantSum = 1
    Case "--png" : i + 1 : png$ = ProgramParameter(i)
    Case "--right" : i + 1 : rightA = Val(StringField(ProgramParameter(i), 1, "-")) : rightB = Val(StringField(ProgramParameter(i), 2, "-"))
    Case "--peek" : peekAt = Val(ProgramParameter(i + 1)) : peekN = Val(ProgramParameter(i + 2)) : i + 2
    Case "--fire" : i + 1 : fireA = Val(StringField(ProgramParameter(i), 1, "-")) : fireB = Val(StringField(ProgramParameter(i), 2, "-"))
    Default : If Val(arg$) > 0 : frames = Val(arg$) : EndIf
  EndSelect
Next
If rom$ = "" Or InvLoadRom(rom$) = 0
  PrintN("invaders_cli: cannot read the ROM '" + rom$ + "' (one file up to 8 KB, or a folder with invaders.h/g/f/e)")
  End 1
EndIf
For f = 0 To frames - 1
  InvIn1 = 0
  If f >= rightA And f <= rightB : InvIn1 | #INV_P1RIGHT : EndIf
  If f >= fireA And f <= fireB : InvIn1 | #INV_P1FIRE : EndIf
  InvRunFrame()
Next
cycles = InvFrames * #INV_FRAME_CYCLES - InvCycleDebt
PrintN("frames=" + Str(InvFrames) + " instructions=" + Str(CpuInstr) + " cycles=" + Str(cycles) + " pc=$" + RSet(Hex(CpuPC), 4, "0") +
       " halted=" + Str(CpuHalted) + " ie=" + Str(CpuIE))
PrintN("vram_sha256=" + Fingerprint(@M($2400), $1C00, #PB_Cipher_SHA2, 256))
If wantSum
  For x = $2400 To $3FFF : sum = sum * 31 + M(x) : Next
  PrintN("vram_sum=" + Str(sum))
EndIf
If peekAt >= 0
  For x = 0 To peekN - 1
    If x % 16 = 0 : If line$ <> "" : PrintN(line$) : EndIf : line$ = "ram $" + RSet(Hex(peekAt + x), 4, "0") + ":" : EndIf
    line$ + " " + RSet(Hex(M((peekAt + x) & $FFFF)), 2, "0")
  Next
  PrintN(line$)
EndIf
If InvLogPorts
  PrintN("port writes: " + Str(ListSize(InvPortLog$())))
  ForEach InvPortLog$() : PrintN(InvPortLog$()) : Next
EndIf
If png$ <> ""
  *buf = AllocateMemory(224 * 256 * 4)
  InvRender(*buf)
  img = CreateImage(#PB_Any, 224, 256, 24)
  StartDrawing(ImageOutput(img))
  For y = 0 To 255
    For x = 0 To 223
      *px = *buf + ((255 - y) * 224 + x) * 4          ; InvRender is bottom row first
      Plot(x, y, RGB((*px\l >> 16) & $FF, (*px\l >> 8) & $FF, *px\l & $FF))
    Next
  Next
  StopDrawing()
  SaveImage(img, png$, #PB_ImagePlugin_PNG)
  PrintN("screen saved to " + png$)
EndIf
End 0
