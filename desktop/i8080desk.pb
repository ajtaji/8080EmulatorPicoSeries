; Intel 8080 on the desktop - the core, a CP/M test machine and a debugger,
; drawn with the Neon Arcade Display Engine.
;
; Build (PowerShell, x64), with the Neon Arcade Display Engine
; (https://github.com/ajtaji/Neon-Arcade-Dispay-Engine) cloned beside this
; repository:
;   & 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' i8080desk.pb /THREAD /DPIAWARE /OPTIMIZER /EXE i8080desk.exe
; The engine elsewhere: add /CONSTANT GL_ENGINE_DIR$=<its folder>/ (with the trailing slash).
;
; Command line: a .COM file or a machine ROM to load (add --mute for no sound,
; anywhere on the line); --selftest (run the four
; diagnostics in the window, save desktop\selftest.png and the verdicts to
; desktop\selftest.log, then close); --machine-selftest (run the Space Invaders
; test ROM 150 frames with "right" held for 30 of them - or the ROM and frame
; count given after it - save desktop\machine-selftest.png and .log, then close).

CompilerIf Defined(GL_ENGINE_DIR$, #PB_Constant) = 0
  #GL_ENGINE_DIR$ = "../../Neon-Arcade-Dispay-Engine/"   ; the engine cloned beside this repository
CompilerEndIf
#CPU_DISPATCH = 0          ; computed goto: measured fastest on the PC
XIncludeFile "machine.pbi"
XIncludeFile "audio.pbi"
IncludePath #GL_ENGINE_DIR$
XIncludeFile "GlTypes.pbi"
XIncludeFile "GlUtilities.pbi"
XIncludeFile "GlMath.pbi"
XIncludeFile "GlSpriteFunctions.pbi"
XIncludeFile "GlUI.pbi"
XIncludeFile "GlUIChrome.pbi"
IncludePath ""
UsePNGImageEncoder()

; ---------------------------------------------------------------- state
Global Win.i, Gl.i, CanvasW.i, CanvasH.i, Scale.f = 1.0
Global MouseDown.b, Wheel.i, KeyCode.i, KeyChar.i, LastMs.q, Quit.i
Global Running.i, Breakpoint.i = -1, BpText.String, MemText.String, MemTop.i, ConTop.i
Global Status$, RightTab.i, SelfTest.i, SelfTestDone.i
Global SpeedInstr.q, SpeedMs.q, SpeedShown$, RunCycles.q, LoadedName$
Global SuiteIndex.i = -1, SuiteCycles.q, SuiteStartMs.q
Global Dim Mn$(255)
Global Dim OpLen.i(255)
Global NewList Results$()
Global Folder$
Global *ScreenTex.GLSprite, *ScreenBuf, MachineAcc.f, MachineMs.q, MachineSelfTest.i, MachineFramesRun.i, MachineSelfTestFrames.i = 150
Declare MachineSlice()
Global ProfMarks$, ProfLast.q
Procedure ProfMark(name$)
  ProfMarks$ + " " + name$ + "=" + Str(ElapsedMilliseconds() - ProfLast)
  ProfLast = ElapsedMilliseconds()
EndProcedure
Global ProfT.q, ProfRun.q, ProfDraw.q, ProfFlip.q, ProfFrames.i, ProfEvents.q, ProfStartup.q, ProfBoot.q = ElapsedMilliseconds()   ; where the window's time goes (self-test log)

Procedure InitDisasm()
  Protected i.i, n.a
  Restore CpuMnemonicData
  For i = 0 To 255 : Read.s Mn$(i) : Next
  Restore CpuLengthData
  For i = 0 To 255 : Read.a n : OpLen(i) = n : Next
EndProcedure

Procedure.s Disasm(adr.i)
  Protected op.i = M(adr & $FFFF), t$ = Mn$(op), sep$ = " "
  If FindString(t$, " ") : sep$ = "," : EndIf
  Select OpLen(op)
    Case 2 : t$ + sep$ + "$" + RSet(Hex(M((adr + 1) & $FFFF)), 2, "0")
    Case 3 : t$ + sep$ + "$" + RSet(Hex(M((adr + 1) & $FFFF) | (M((adr + 2) & $FFFF) << 8)), 4, "0")
  EndSelect
  ProcedureReturn t$
EndProcedure

Procedure.s H4(v.i) : ProcedureReturn RSet(Hex(v & $FFFF), 4, "0") : EndProcedure
Procedure.s H2(v.i) : ProcedureReturn RSet(Hex(v & $FF), 2, "0") : EndProcedure

; ---------------------------------------------------------------- machine
Procedure LoadProgram(file$, name$)
  If CpmLoad(file$)
    LoadedName$ = name$ : RunCycles = 0 : Running = #False : ConTop = 0
    Status$ = "Loaded " + name$ + " at $0100"
  Else
    Status$ = "Cannot read " + file$ + " - fetch the diagnostics with tools/fetch_tests.py"
  EndIf
EndProcedure

Procedure.s Verdict(i.i)
  Protected ok.i = Bool(CpmFinished And FindString(CpmOut$, CpmTests(i)\Pass$) And FindString(CpmOut$, "ERROR") = 0 And
                        CpuInstr = CpmTests(i)\RefInstr And RunCycles = CpmTests(i)\RefCycles)
  ProcedureReturn CpmTests(i)\Name$ + "  " + StringField("FAIL|PASS", 1 + ok, "|") + "   instructions " + Str(CpuInstr) + " / " +
                  Str(CpmTests(i)\RefInstr) + "   cycles " + Str(RunCycles) + " / " + Str(CpmTests(i)\RefCycles) +
                  "   " + StrF((ElapsedMilliseconds() - SuiteStartMs) / 1000.0, 2) + " s"
EndProcedure

Procedure StartSuite(i.i)
  SuiteIndex = i
  If i > 3
    SuiteIndex = -1 : Running = #False
    Status$ = "Suite finished"
    ProcedureReturn
  EndIf
  LoadProgram(Folder$ + CpmTests(i)\File$, CpmTests(i)\Name$)
  If LoadedName$ <> CpmTests(i)\Name$
    AddElement(Results$()) : Results$() = CpmTests(i)\Name$ + "  FAIL   " + Status$
    StartSuite(i + 1)
    ProcedureReturn
  EndIf
  SuiteStartMs = ElapsedMilliseconds()
  Running = #True : RightTab = 1
EndProcedure

; Runs the guest for about `ms` milliseconds of host time.
Procedure RunSlice(ms.i)
  Protected t0.q = ElapsedMilliseconds(), before.q = CpuInstr, n.i
  If Machine = #MACHINE_INVADERS
    MachineSlice()
    ProcedureReturn
  EndIf
  While Running And ElapsedMilliseconds() - t0 < ms
    If Breakpoint >= 0
      ; Instruction by instruction, so the stop lands exactly on the address.
      For n = 1 To 20000
        RunCycles + CpuRun(1)
        If CpuPC = Breakpoint Or CpmFinished Or CpuHalted
          Break
        EndIf
      Next
      If CpuPC = Breakpoint
        Running = #False : Status$ = "Breakpoint at $" + H4(Breakpoint)
      EndIf
    Else
      RunCycles + CpuRun(2000000)
    EndIf
    If CpmFinished Or CpuHalted
      Running = #False
      If CpmFinished : Status$ = LoadedName$ + " finished (OUT 0)" : Else : Status$ = "Halted at $" + H4(CpuPC) : EndIf
    EndIf
  Wend
  SpeedInstr + (CpuInstr - before)
  SpeedMs + (ElapsedMilliseconds() - t0)
  If SpeedMs >= 500
    SpeedShown$ = StrF(SpeedInstr / (SpeedMs * 1000.0), 1) + " M instructions/s"
    SpeedInstr = 0 : SpeedMs = 0
  EndIf
  If SuiteIndex >= 0 And Running = #False And (CpmFinished Or CpuHalted)
    AddElement(Results$()) : Results$() = Verdict(SuiteIndex)
    StartSuite(SuiteIndex + 1)
  EndIf
EndProcedure

; The machine test ROM: machine\invaders_test.rom beside Diagnostics.
Procedure.s MachineTestRom()
  Protected d$ = Left(Folder$, Len(Folder$) - 1)       ; ...\Diagnostics\upstream
  d$ = GetPathPart(d$)                                 ; ...\Diagnostics\
  d$ = GetPathPart(Left(d$, Len(d$) - 1))              ; the repository
  ProcedureReturn d$ + "machine\invaders_test.rom"
EndProcedure

Procedure LoadMachine(path$, name$)
  If InvLoadRom(path$)
    LoadedName$ = name$ : RunCycles = 0 : SuiteIndex = -1 : RightTab = 0
    MachineAcc = 0 : MachineMs = ElapsedMilliseconds() : MachineFramesRun = 0
    Running = #True
    Status$ = "Space Invaders hardware: " + name$ + " - arrows move, Space fires, 1/2 start, C coin"
  Else
    Status$ = "Cannot read the ROM " + path$ + " (one file up to 8 KB, or a folder with invaders.h/g/f/e)"
  EndIf
EndProcedure

; The cabinet's controls, read while the window has the focus.
Procedure MachineInputs()
  Protected v.i
  If GetActiveWindow() = Win
    If GetAsyncKeyState_(#VK_LEFT) & $8000 : v | #INV_P1LEFT : EndIf
    If GetAsyncKeyState_(#VK_RIGHT) & $8000 : v | #INV_P1RIGHT : EndIf
    If GetAsyncKeyState_(#VK_SPACE) & $8000 : v | #INV_P1FIRE : EndIf
    If GetAsyncKeyState_(#VK_1) & $8000 : v | #INV_P1START : EndIf
    If GetAsyncKeyState_(#VK_2) & $8000 : v | #INV_P2START : EndIf
    If GetAsyncKeyState_(#VK_C) & $8000 : v | #INV_COIN : EndIf
  EndIf
  InvIn1 = v
EndProcedure

Procedure MachineFrame()
  InvRunFrame()
  RunCycles + #INV_FRAME_CYCLES
  MachineFramesRun + 1
  If MachineSelfTest = 0 : AudioPush() : EndIf
EndProcedure

; 60 frames a second of host time; at most four frames to catch up. The
; self-test runs two frames a drawn frame, with "right" held for frames 30-59.
Procedure MachineSlice()
  Protected now.q = ElapsedMilliseconds(), n.i, before.q = CpuInstr
  If MachineSelfTest
    For n = 1 To 2
      InvIn1 = Bool(MachineFramesRun >= 30 And MachineFramesRun < 60) * #INV_P1RIGHT
      MachineFrame()
    Next
    ProcedureReturn
  EndIf
  MachineInputs()
  MachineAcc + (now - MachineMs) : MachineMs = now
  If MachineAcc > 100 : MachineAcc = 100 : EndIf
  While MachineAcc >= 1000.0 / 60 And n < 4
    MachineFrame() : n + 1
    MachineAcc - 1000.0 / 60
  Wend
  SpeedInstr + (CpuInstr - before) : SpeedMs + (n * 1000) / 60
  If SpeedMs >= 1000
    SpeedShown$ = "60 frames/s, guest " + StrF(SpeedInstr / (SpeedMs * 1000.0), 2) + " M instructions/s"
    SpeedInstr = 0 : SpeedMs = 0
  EndIf
EndProcedure

; ---------------------------------------------------------------- window
Procedure.f DisplayScale()
  Protected lib.i = OpenLibrary(#PB_Any, "user32.dll"), fn.i, dpi.i
  If lib
    fn = GetFunction(lib, "GetDpiForWindow")
    If fn : dpi = CallFunctionFast(fn, WindowID(Win)) : EndIf
    CloseLibrary(lib)
  EndIf
  If dpi <= 0 : ProcedureReturn 1.0 : EndIf
  ProcedureReturn dpi / 96.0
EndProcedure

Procedure BuildFonts()
  *Neon_FontUI    = Neon_CreateFontPx("Segoe UI", Round(14 * Scale, #PB_Round_Nearest))
  *Neon_FontSmall = Neon_CreateFontPx("Segoe UI", Round(12 * Scale, #PB_Round_Nearest))
  *Neon_FontBold  = Neon_CreateFontPx("Segoe UI", Round(15 * Scale, #PB_Round_Nearest), #PB_Font_Bold)
  *Neon_FontMono  = Neon_CreateFontPx("Consolas", Round(14 * Scale, #PB_Round_Nearest))
  GLFontSetSnapToPixel(*Neon_FontUI, #True) : GLFontSetSnapToPixel(*Neon_FontSmall, #True)
  GLFontSetSnapToPixel(*Neon_FontBold, #True) : GLFontSetSnapToPixel(*Neon_FontMono, #True)
EndProcedure

Procedure SizeCanvas()
  Protected cw.i = WindowWidth(Win, #PB_Window_InnerCoordinate), ch.i = WindowHeight(Win, #PB_Window_InnerCoordinate)
  Protected r.RECT
  If cw <= 0 Or ch <= 0 : ProcedureReturn : EndIf
  ResizeGadget(Gl, 0, 0, cw, ch)
  GetClientRect_(WindowID(Win), @r)
  CanvasW = r\right - r\left : CanvasH = r\bottom - r\top
  If CanvasW < 1 : CanvasW = 1 : EndIf
  If CanvasH < 1 : CanvasH = 1 : EndIf
  Util_BaseWidth = CanvasW : Util_BaseHeight = CanvasH
  Util_WinWidth = cw : Util_WinHeight = ch
  GL_ViewportX = 0 : GL_ViewportY = 0 : GL_ViewportW = CanvasW : GL_ViewportH = CanvasH
EndProcedure

; The frame being drawn, to a PNG. glReadPixels gives rows bottom-up, as a
; Windows 24-bit image keeps them, so each row is copied straight across
; (RGBA to BGR) into the image's own buffer - Plot() per pixel took most of
; a minute for a full window.
Procedure SaveScreenshot(file$)
  Protected img.i = CreateImage(#PB_Any, CanvasW, CanvasH, 24), *dst, pitch.i, y.i, x.i, *s.Ascii, *d.Ascii, *row
  Protected *pix = AllocateMemory(CanvasW * CanvasH * 4)
  glPixelStorei_(#GL_PACK_ALIGNMENT, 1)
  glReadPixels_(0, 0, CanvasW, CanvasH, #GL_RGBA, #GL_UNSIGNED_BYTE, *pix)
  If StartDrawing(ImageOutput(img))
    *dst = DrawingBuffer() : pitch = DrawingBufferPitch()
    For y = 0 To CanvasH - 1
      If DrawingBufferPixelFormat() & #PB_PixelFormat_ReversedY
        *row = *dst + y * pitch               ; bottom-up, like glReadPixels
      Else
        *row = *dst + (CanvasH - 1 - y) * pitch
      EndIf
      *s = *pix + y * CanvasW * 4
      For x = 0 To CanvasW - 1
        *d = *row + x * 3
        PokeA(*d, PeekA(*s + 2)) : PokeA(*d + 1, PeekA(*s + 1)) : PokeA(*d + 2, PeekA(*s))
        *s + 4
      Next
    Next
    StopDrawing()
  EndIf
  SaveImage(img, file$, #PB_ImagePlugin_PNG)
  FreeImage(img) : FreeMemory(*pix)
EndProcedure

; ---------------------------------------------------------------- panes
Procedure RegistersPane(x.f, y.f, w.f, h.f)
  Protected s.f = Scale, lh.f = GLFontLineHeight(*Neon_FontMono) + 2 * s, ty.f, fl.i = CpuFlags(), i.i
  Protected names$ = "S Z - A - P - C", bit.i
  Neon_Panel(x, y, w, h, "Registers", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB, Neon_S(26))
  ty = y + Neon_S(34)
  Neon_Text(*Neon_FontMono, x + 12 * s, ty, "A  " + H2(CpuA) + "     PSW " + H4((CpuA << 8) | fl), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, x + 12 * s, ty, "BC " + H4(CpuBC) + "   DE  " + H4(CpuDE), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, x + 12 * s, ty, "HL " + H4(CpuHL) + "   SP  " + H4(CpuSP), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, x + 12 * s, ty, "PC " + H4(CpuPC) + "   (HL) " + H2(M(CpuHL)), Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB) : ty + lh * 1.4
  ; Flags, each lit when set.
  Protected fx.f = x + 12 * s, label$
  For i = 0 To 4
    label$ = StringField("S|Z|AC|P|CY", i + 1, "|")
    bit = Val(StringField("128|64|16|4|1", i + 1, "|"))
    If fl & bit
      Neon_Box(fx, ty, 34 * s, lh, 0.157, 0.365, 0.408)
      Neon_Text(*Neon_FontMono, fx + 6 * s, ty + 1 * s, label$, Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
    Else
      Neon_Frame(fx, ty, 34 * s, lh, Neon_C_LineR, Neon_C_LineG, Neon_C_LineB)
      Neon_Text(*Neon_FontMono, fx + 6 * s, ty + 1 * s, label$, Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
    EndIf
    fx + 40 * s
  Next
  ty + lh * 1.5
  Neon_Text(*Neon_FontMono, x + 12 * s, ty, "INTE " + Str(CpuIE) + "   HALT " + Str(CpuHalted), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Neon_Text(*Neon_FontMono, x + 12 * s, ty, "instructions " + Str(CpuInstr), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Neon_Text(*Neon_FontMono, x + 12 * s, ty, "cycles       " + Str(RunCycles), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Neon_Text(*Neon_FontMono, x + 12 * s, ty, "at 2 MHz     " + StrF(RunCycles / 2000000.0, 2) + " s", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
EndProcedure

Procedure DisasmPane(x.f, y.f, w.f, h.f)
  Protected s.f = Scale, lh.f = GLFontLineHeight(*Neon_FontMono) + 2 * s, ty.f = y + Neon_S(32), adr.i = CpuPC, i.i, bytes$, k.i
  Neon_Panel(x, y, w, h, "Disassembly", Neon_C_VioR, Neon_C_VioG, Neon_C_VioB, Neon_S(26))
  While ty + lh < y + h - 6 * s
    bytes$ = ""
    For k = 0 To OpLen(M(adr)) - 1 : bytes$ + H2(M((adr + k) & $FFFF)) + " " : Next
    If adr = CpuPC
      Neon_Box(x + 2, ty - 1 * s, w - 4, lh, 0.20, 0.22, 0.26)
    EndIf
    If adr = Breakpoint
      Neon_Box(x + 4 * s, ty + 3 * s, 6 * s, lh - 6 * s, Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
    EndIf
    Neon_Text(*Neon_FontMono, x + 14 * s, ty, H4(adr) + "  " + LSet(bytes$, 10) + Disasm(adr),
              Bool(adr = CpuPC) * (Neon_C_AmbR - Neon_C_TextR) + Neon_C_TextR, Bool(adr = CpuPC) * (Neon_C_AmbG - Neon_C_TextG) + Neon_C_TextG,
              Bool(adr = CpuPC) * (Neon_C_AmbB - Neon_C_TextB) + Neon_C_TextB)
    adr = (adr + OpLen(M(adr))) & $FFFF
    ty + lh
  Wend
EndProcedure

Procedure MemoryPane(x.f, y.f, w.f, h.f)
  Protected s.f = Scale, lh.f = GLFontLineHeight(*Neon_FontMono) + 2 * s, ty.f, rows.i, r.i, c.i, line$, asc$, adr.i, v.i
  Neon_Text(*Neon_FontUI, x + 10 * s, y + 9 * s, "Go to", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  If Neon_TextInput(201, x + 60 * s, y + 4 * s, 90 * s, 26 * s, @MemText, "hex")
    MemTop = (Val("$" + MemText\s) & $FFF0) / 16
  EndIf
  If Neon_Button(x + 160 * s, y + 4 * s, 70 * s, 26 * s, "PC") : MemTop = (CpuPC & $FFF0) / 16 : EndIf
  If Neon_Button(x + 236 * s, y + 4 * s, 70 * s, 26 * s, "SP") : MemTop = (CpuSP & $FFF0) / 16 : EndIf
  If Neon_Button(x + 312 * s, y + 4 * s, 70 * s, 26 * s, "HL") : MemTop = (CpuHL & $FFF0) / 16 : EndIf
  ty = y + 40 * s
  rows = (h - 46 * s) / lh
  If Neon_Hit(x, ty, w, h - 40 * s) And Neon_Wheel : MemTop - Neon_Wheel * 3 : EndIf
  If MemTop > 4096 - rows : MemTop = 4096 - rows : EndIf
  If MemTop < 0 : MemTop = 0 : EndIf
  Neon_ScrollBarV(202, x + w - 14 * s, ty, 12 * s, h - 46 * s, 4096, rows, @MemTop)
  For r = 0 To rows - 1
    adr = (MemTop + r) * 16
    If adr > $FFF0 : Break : EndIf
    line$ = H4(adr) + "  " : asc$ = ""
    For c = 0 To 15
      v = M(adr + c)
      line$ + H2(v) + " "
      If c = 7 : line$ + " " : EndIf
      If v >= 32 And v < 127 : asc$ + Chr(v) : Else : asc$ + "." : EndIf
    Next
    Neon_Text(*Neon_FontMono, x + 10 * s, ty, line$ + " " + asc$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB)
    ty + lh
  Next
EndProcedure

Procedure ConsolePane(x.f, y.f, w.f, h.f)
  Protected s.f = Scale, lh.f = GLFontLineHeight(*Neon_FontMono) + 2 * s, n.i = CountString(CpmOut$, #LF$) + 1
  Protected rows.i = (h - 12 * s) / lh, i.i, ty.f = y + 6 * s, first.i
  first = n - rows
  If first < 0 : first = 0 : EndIf
  For i = first To n - 1
    Neon_Text(*Neon_FontMono, x + 10 * s, ty, StringField(CpmOut$, i + 1, #LF$), Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    ty + lh
  Next
EndProcedure

Procedure ResultsPane(x.f, y.f, w.f, h.f)
  Protected s.f = Scale, lh.f = GLFontLineHeight(*Neon_FontMono) + 6 * s, ty.f = y + 8 * s
  Neon_Text(*Neon_FontSmall, x + 10 * s, ty, "Instruction and cycle counts must equal the published reference (superzazu/8080).",
            Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  ty + lh * 1.3
  ForEach Results$()
    If FindString(Results$(), "PASS")
      Neon_Text(*Neon_FontMono, x + 10 * s, ty, Results$(), Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    Else
      Neon_Text(*Neon_FontMono, x + 10 * s, ty, Results$(), Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
    EndIf
    ty + lh
  Next
  If SuiteIndex >= 0
    Neon_Text(*Neon_FontMono, x + 10 * s, ty, CpmTests(SuiteIndex)\Name$ + "  running...  " + Str(CpuInstr) + " instructions",
              Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  EndIf
EndProcedure

Procedure ScreenInit()
  *ScreenBuf = AllocateMemory(224 * 256 * 4)
  *ScreenTex = AllocateMemory(SizeOf(GLSprite))
  *ScreenTex\Width = 224 : *ScreenTex\Height = 256
  glGenTextures_(1, @*ScreenTex\TextureID)
  glBindTexture_(#GL_TEXTURE_2D, *ScreenTex\TextureID)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MIN_FILTER, #GL_NEAREST)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MAG_FILTER, #GL_NEAREST)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_S, #GL_CLAMP_TO_EDGE)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_T, #GL_CLAMP_TO_EDGE)
  glTexImage2D_(#GL_TEXTURE_2D, 0, #GL_RGBA, 224, 256, 0, #GL_BGRA_EXT, #GL_UNSIGNED_BYTE, *ScreenBuf)
EndProcedure

Procedure ScreenPane(x.f, y.f, w.f, h.f)
  Protected s.f = Scale, k.i, sx.f, sy.f, lh.f = GLFontLineHeight(*Neon_FontSmall) + 4 * s, ty.f
  If Neon_Button(x + 10 * s, y + 6 * s, 150 * s, 28 * s, "Machine test ROM", Bool(InvLoaded$ = MachineTestRom() And Machine = #MACHINE_INVADERS))
    LoadMachine(MachineTestRom(), "invaders_test.rom")
  EndIf
  Neon_Text(*Neon_FontSmall, x + 172 * s, y + 12 * s, "Space Invaders (Taito 8080) hardware. Open... loads a ROM: 8 KB, or a folder of invaders.h/g/f/e",
            Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  If Machine <> #MACHINE_INVADERS
    Neon_Text(*Neon_FontUI, x + 14 * s, y + 60 * s, "No machine ROM loaded.", Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
    ProcedureReturn
  EndIf
  InvRender(*ScreenBuf)
  glBindTexture_(#GL_TEXTURE_2D, *ScreenTex\TextureID)
  glTexSubImage2D_(#GL_TEXTURE_2D, 0, 0, 0, 224, 256, #GL_BGRA_EXT, #GL_UNSIGNED_BYTE, *ScreenBuf)
  k = Int((h - 60 * s) / 256)
  If Int((w - 280 * s) / 224) < k : k = Int((w - 280 * s) / 224) : EndIf
  If k < 1 : k = 1 : EndIf
  sx = x + 14 * s : sy = y + 44 * s
  Neon_Box(sx - 2, sy - 2, 224 * k + 4, 256 * k + 4, 0.0, 0.0, 0.0)
  DrawGLSprite(*ScreenTex, sx, sy, 0.0, k, 1.0, 1.0, 1.0, 1.0, #True, -1.0, -1.0, -1.0, -1.0, #True)
  ; Beside the screen: the machine's state.
  ty = sy
  sx + 224 * k + 24 * s
  Neon_Text(*Neon_FontMono, sx, ty, "frame " + Str(InvFrames), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, sx, ty, "IN 1  " + RSet(Bin(InvPortIn(1)), 8, "0"), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, sx, ty, "OUT 3 " + RSet(Bin(InvSound3 & 255), 8, "0"), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, sx, ty, "OUT 5 " + RSet(Bin(InvSound5 & 255), 8, "0"), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, sx, ty, "shift " + H4(InvShift) + " >> " + Str(8 - InvShiftAmt), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh * 1.5
  For k = 0 To 3
    Neon_Text(*Neon_FontMono, sx, ty, "tone " + Str(k) + "  " + StrF(62500.0 / (InvTones(k)\Period + 1), 0) + " Hz  vol " + Str(InvTones(k)\Volume) +
              "  " + StringField("square|pulse|triangle|noise", InvTones(k)\Wave + 1, "|"), Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB) : ty + lh
  Next
  ty + lh
  Neon_Text(*Neon_FontSmall, sx, ty, "arrows move, Space fires", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Neon_Text(*Neon_FontSmall, sx, ty, "1 / 2 start, C coin", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  If AudioOk = 0
    Neon_Text(*Neon_FontSmall, sx, ty, "sound off", Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
  EndIf
EndProcedure

Procedure DrawFrame()
  Protected s.f = Scale, bx.f, by.f, bw.f = 96 * s, bh.f = 30 * s, i.i, colW.f, top.f, half.f, sel.i
  Protected f$
  ; Toolbar.
  Neon_Box(0, 0, CanvasW, 48 * s, Neon_C_HeadR, Neon_C_HeadG, Neon_C_HeadB)
  Neon_Text(*Neon_FontBold, 14 * s, 14 * s, "INTEL 8080", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  bx = 120 * s : by = 9 * s
  If Neon_Button(bx, by, bw, bh, "Open...")
    f$ = OpenFileRequester("Load a CP/M program or a machine ROM", Folder$, "CP/M program (*.com)|*.com;*.COM|Machine ROM (*.rom, *.bin)|*.rom;*.bin|All files|*.*", 0)
    If f$
      SuiteIndex = -1
      If LCase(GetExtensionPart(f$)) = "com"
        LoadProgram(f$, GetFilePart(f$)) : RightTab = 1
      Else
        LoadMachine(f$, GetFilePart(f$))
      EndIf
    EndIf
  EndIf
  bx + bw + 6 * s
  For i = 0 To 3
    If Neon_Button(bx, by, 84 * s, bh, CpmTests(i)\Name$, Bool(LoadedName$ = CpmTests(i)\Name$))
      SuiteIndex = -1 : LoadProgram(Folder$ + CpmTests(i)\File$, CpmTests(i)\Name$) : RightTab = 1
    EndIf
    bx + 90 * s
  Next
  If Neon_Button(bx, by, 120 * s, bh, "Run all suites", Bool(SuiteIndex >= 0))
    ClearList(Results$()) : StartSuite(0)
  EndIf
  bx + 136 * s
  If Neon_Button(bx, by, 70 * s, bh, "Run", Running, Bool(Running = 0)) : Running = #True : Status$ = "Running" : EndIf
  bx + 76 * s
  If Neon_Button(bx, by, 70 * s, bh, "Pause", #False, Running) : Running = #False : Status$ = "Paused at $" + H4(CpuPC) : EndIf
  bx + 76 * s
  If Neon_Button(bx, by, 70 * s, bh, "Step", #False, Bool(Running = 0))
    RunCycles + CpuRun(1) : Status$ = "Stepped to $" + H4(CpuPC)
  EndIf
  bx + 76 * s
  If Neon_Button(bx, by, 80 * s, bh, "Step 100", #False, Bool(Running = 0))
    For i = 1 To 100
      RunCycles + CpuRun(1)
      If CpmFinished Or CpuHalted Or CpuPC = Breakpoint : Break : EndIf
    Next
    Status$ = "Stepped to $" + H4(CpuPC)
  EndIf
  bx + 86 * s
  If Neon_Button(bx, by, 70 * s, bh, "Reset", #False, Bool(LoadedName$ <> ""))
    SuiteIndex = -1
    If Machine = #MACHINE_INVADERS
      LoadMachine(InvLoaded$, LoadedName$)
    ElseIf LoadedName$ <> "" And FindString(CpmLoaded$, ".")
      LoadProgram(CpmLoaded$, LoadedName$)
    EndIf
  EndIf
  bx + 84 * s
  Neon_Text(*Neon_FontUI, bx, by + 6 * s, "Break at", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  If Neon_TextInput(101, bx + 64 * s, by, 80 * s, bh, @BpText, "none")
    If Trim(BpText\s) = "" : Breakpoint = -1 : Else : Breakpoint = Val("$" + Trim(BpText\s)) & $FFFF : EndIf
  EndIf
  Neon_TextRight(*Neon_FontUI, CanvasW - 14 * s, by + 6 * s, SpeedShown$, Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)

  ; Panes: registers and disassembly on the left; console, memory, results on the right.
  top = 56 * s
  colW = 440 * s
  RegistersPane(8 * s, top, colW, 300 * s)
  DisasmPane(8 * s, top + 308 * s, colW, CanvasH - top - 308 * s - 40 * s)
  Neon_Panel(colW + 16 * s, top, CanvasW - colW - 24 * s, CanvasH - top - 40 * s, "", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  sel = Neon_TabStrip(300, colW + 17 * s, top + 1, CanvasW - colW - 26 * s, 30 * s, "Screen|Console|Memory|Suite results", RightTab)
  If sel <> RightTab : RightTab = sel : EndIf
  Select RightTab
    Case 0 : ScreenPane(colW + 16 * s, top + 34 * s, CanvasW - colW - 24 * s, CanvasH - top - 78 * s)
    Case 1 : ConsolePane(colW + 16 * s, top + 34 * s, CanvasW - colW - 24 * s, CanvasH - top - 78 * s)
    Case 2 : MemoryPane(colW + 16 * s, top + 34 * s, CanvasW - colW - 24 * s, CanvasH - top - 78 * s)
    Default : ResultsPane(colW + 16 * s, top + 34 * s, CanvasW - colW - 24 * s, CanvasH - top - 78 * s)
  EndSelect
  ; Status line.
  Neon_Box(0, CanvasH - 30 * s, CanvasW, 30 * s, Neon_C_HeadR, Neon_C_HeadG, Neon_C_HeadB)
  Neon_Text(*Neon_FontSmall, 12 * s, CanvasH - 23 * s, Status$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB)
  Neon_TextRight(*Neon_FontSmall, CanvasW - 12 * s, CanvasH - 23 * s,
                 "core: generated from the Pico core's opcode table - dispatch: computed goto", Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
EndProcedure

; ---------------------------------------------------------------- main
Procedure Main()
  Protected ev.i, now.q, dt.f, arg$ = ProgramParameter(0), lib.i, fn.i, w.i = 1400, h.i = 880, down.b, log.i, k.i, mute.i
  For k = 0 To CountProgramParameters() - 1
    If LCase(ProgramParameter(k)) = "--mute" : mute = #True : EndIf
  Next
  If LCase(arg$) = "--mute" : arg$ = ProgramParameter(1) : EndIf
  ; Per-monitor DPI awareness before any window exists.
  lib = OpenLibrary(#PB_Any, "user32.dll")
  If lib
    fn = GetFunction(lib, "SetProcessDpiAwarenessContext")
    If fn : CallFunctionFast(fn, -4) : EndIf
    CloseLibrary(lib)
  EndIf
  ProfMark("dpi")
  CpmInitTests()
  InitDisasm()
  Folder$ = CpmTestFolder()
  ProfMark("tables")
  ExamineDesktops()
  If w > DesktopWidth(0) * 0.9 : w = DesktopWidth(0) * 0.9 : EndIf
  If h > DesktopHeight(0) * 0.85 : h = DesktopHeight(0) * 0.85 : EndIf
  Gl = OpenGLWindow("Intel 8080 - PureBasic desktop core", w, h,
                    #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_SizeGadget | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget)
  ProfMark("window")
  Win = Util_MainWindowID
  If Gl = 0 Or Win = 0
    MessageRequester("Intel 8080", "The OpenGL window could not be opened.")
    ProcedureReturn
  EndIf
  Scale = DisplayScale()
  Neon_UIScale = Scale
  ProfMark("scale")
  BuildFonts()
  ProfMark("fonts")
  SizeCanvas()
  ProfMark("canvas")
  ScreenInit()
  If LCase(arg$) = "--selftest"
    SelfTest = #True
    StartSuite(0)
  ElseIf LCase(arg$) = "--machine-selftest"
    ; optionally: a ROM (file or folder) and how many frames to run first
    MachineSelfTest = #True
    If ProgramParameter(1) <> ""
      LoadMachine(ProgramParameter(1), GetFilePart(RTrim(ProgramParameter(1), "\")))
      If Val(ProgramParameter(2)) > 0 : MachineSelfTestFrames = Val(ProgramParameter(2)) : EndIf
    Else
      LoadMachine(MachineTestRom(), "invaders_test.rom")
    EndIf
  ElseIf arg$ <> ""
    If mute = 0 : AudioOpen() : EndIf
    If LCase(GetExtensionPart(arg$)) = "com"
      LoadProgram(arg$, GetFilePart(arg$)) : RightTab = 1
    Else
      LoadMachine(arg$, GetFilePart(arg$))
    EndIf
  Else
    If mute = 0 : AudioOpen() : EndIf
    LoadProgram(Folder$ + CpmTests(0)\File$, CpmTests(0)\Name$)
  EndIf
  ProfMark("loaded")
  LastMs = ElapsedMilliseconds()
  ProfStartup = ElapsedMilliseconds() - ProfBoot
  Repeat
    ProfT = ElapsedMilliseconds()
    Repeat
      ev = WindowEvent()
      Select ev
        Case #PB_Event_CloseWindow : Quit = #True
        Case #PB_Event_SizeWindow : SizeCanvas()
        Case #PB_Event_Gadget
          If EventGadget() = Gl
            Select EventType()
              Case #PB_EventType_LeftButtonDown : MouseDown = #True
              Case #PB_EventType_LeftButtonUp : MouseDown = #False
              Case #PB_EventType_MouseWheel : Wheel + GetGadgetAttribute(Gl, #PB_OpenGL_WheelDelta)
              Case #PB_EventType_KeyDown : KeyCode = GetGadgetAttribute(Gl, #PB_OpenGL_Key)
              Case #PB_EventType_Input : KeyChar = GetGadgetAttribute(Gl, #PB_OpenGL_Input)
            EndSelect
          EndIf
      EndSelect
    Until ev = 0
    ProfEvents + ElapsedMilliseconds() - ProfT
    ProfT = ElapsedMilliseconds()
    If Running : RunSlice(14) : EndIf
    ProfRun + ElapsedMilliseconds() - ProfT
    now = ElapsedMilliseconds() : dt = (now - LastMs) / 1000.0 : LastMs = now
    down = Bool(MouseDown Or (GetActiveWindow() = Win And (GetAsyncKeyState_(#VK_LBUTTON) & $8000)))
    SetGadgetAttribute(Gl, #PB_OpenGL_SetContext, #True)
    Neon_ChromeBeginFrame(WindowMouseX(Win), WindowMouseY(Win), down, Wheel, KeyCode, KeyChar, dt)
    Wheel = 0 : KeyCode = 0 : KeyChar = 0
    glBindFramebuffer(#GL_FRAMEBUFFER, 0)
    glDisable_(#GL_SCISSOR_TEST)
    glViewport_(0, 0, CanvasW, CanvasH)
    glClearColor_(Neon_C_BgR, Neon_C_BgG, Neon_C_BgB, 1.0)
    glClear_(#GL_COLOR_BUFFER_BIT)
    ProfT = ElapsedMilliseconds()
    DrawFrame()
    ProfDraw + ElapsedMilliseconds() - ProfT
    Neon_ChromeEndFrame()
    If SelfTest And SuiteIndex = -1 And SelfTestDone = 0
      SelfTestDone = 1
      RightTab = 3                      ; draw the results tab once more, then capture it
    ElseIf SelfTestDone = 1 And MachineSelfTest
      SaveScreenshot(GetPathPart(ProgramFilename()) + "machine-selftest.png")
      log = CreateFile(#PB_Any, GetPathPart(ProgramFilename()) + "machine-selftest.log")
      If log
        WriteStringN(log, "frames=" + Str(InvFrames) + " RST1=" + Str(M($2000)) + " RST2=" + Str(M($2001)) + " frame=" + Str(M($2002)) +
                          " sprite=" + Str(M($2003)) + " shift=" + Str(M($2010)) + "," + Str(M($2011)) + "," + Str(M($2012)) + "," + Str(M($2013)) +
                          " tone0 period=" + Str(InvTones(0)\Period) + " volume=" + Str(InvTones(0)\Volume))
        WriteStringN(log, "drawn=" + Str(ProfFrames) + " run_ms=" + Str(ProfRun) + " draw_ms=" + Str(ProfDraw) + " flip_ms=" + Str(ProfFlip) + " events_ms=" + Str(ProfEvents) + " startup_ms=" + Str(ProfStartup) + " total_ms=" + Str(ElapsedMilliseconds() - ProfBoot))
        WriteStringN(log, "startup:" + ProfMarks$)
        CloseFile(log)
      EndIf
      Quit = #True
    ElseIf SelfTestDone = 1
      SaveScreenshot(GetPathPart(ProgramFilename()) + "selftest.png")
      log = CreateFile(#PB_Any, GetPathPart(ProgramFilename()) + "selftest.log")
      If log
        ForEach Results$() : WriteStringN(log, Results$()) : Next
        CloseFile(log)
      EndIf
      Quit = #True
    EndIf
    If MachineSelfTest And MachineFramesRun >= MachineSelfTestFrames And SelfTestDone = 0
      SelfTestDone = 1                  ; one more frame drawn, then captured
      Running = #False
    EndIf
    ProfT = ElapsedMilliseconds()
    SetGadgetAttribute(Gl, #PB_OpenGL_FlipBuffers, #True)
    ProfFlip + ElapsedMilliseconds() - ProfT : ProfFrames + 1
    If Running = 0 : Delay(10) : EndIf
  Until Quit
  AudioClose()
EndProcedure
Main()
