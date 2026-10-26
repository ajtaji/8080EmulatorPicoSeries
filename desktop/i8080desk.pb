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
; With no argument (a double-click) it opens on the PureMetal demo. ROMs are
; found from the exe's folder or the current one, so it does not matter where
; it is started from; a ROM it cannot read gets an error box.
; --exit-after <frames>: start as usual, then save startup.png and startup.log
; (what was loaded) beside the exe and close - a check with no one watching.
; --tab <n>: open on tab n (0 Screen, 1 Console, 2 Memory, 3 Suite results, 4 Controls).
; --pointer-test <txt>: every control against synthetic pointer positions, then close.
; --fullscreen-test <txt> [--fullscreen-shot <png>]: F11 and Esc posted to the
; window itself: checks full screen and the way back, then closes.
; Keys: the cabinet's inputs and the window's shortcuts are one table, controls.pbi.

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
XIncludeFile "controls.pbi"          ; every key the window answers to, one table
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
Global Folder$, Root$, MachineLoadError$, ExitAfter.i, StartTab.i
Global *ScreenTex.GLSprite, *ScreenBuf, MachineAcc.f, MachineMs.q, MachineSelfTest.i, MachineFramesRun.i, MachineSelfTestFrames.i = 150
Declare MachineSlice()
Global ProfMarks$, ProfLast.q
Procedure ProfMark(name$)
  ProfMarks$ + " " + name$ + "=" + Str(ElapsedMilliseconds() - ProfLast)
  ProfLast = ElapsedMilliseconds()
EndProcedure
Global ProfT.q, ProfRun.q, ProfDraw.q, ProfFlip.q, ProfFrames.i, ProfEvents.q, ProfStartup.q, ProfBoot.q = ElapsedMilliseconds()   ; where the window's time goes (self-test log)

; Where each control was last drawn (canvas units), for --pointer-test.
Structure CtlRect
  x.f : y.f : w.f : h.f
EndStructure
Global NewMap Ctl.CtlRect()
Global SynthOn.i, SynthClicked$
Procedure CtlSet(name$, x.f, y.f, w.f, h.f)
  Ctl(name$)\x = x : Ctl()\y = y : Ctl()\w = w : Ctl()\h = h
EndProcedure
; Neon_Button, remembering where it was drawn. Under --pointer-test a press is
; recorded and its action is not taken (no dialog, no run).
Procedure.b Btn(x.f, y.f, w.f, h.f, label.s, lit.b = #False, enabled.b = #True)
  CtlSet(label, x, y, w, h)
  If Neon_Button(x, y, w, h, label, lit, enabled)
    If SynthOn : SynthClicked$ = label : ProcedureReturn #False : EndIf
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

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

; The repository: the first folder, walking up from the exe's folder and then
; from the current folder, that holds the demo's ROM chips or the machine test
; ROM. So the window finds them however it is started (double-click, from the
; repository, from desktop\). "" when there is none.
Procedure.s RepoRoot()
  Protected d$, i.i, pass.i
  For pass = 0 To 1
    If pass = 0 : d$ = GetPathPart(ProgramFilename()) : Else : d$ = GetCurrentDirectory() : EndIf
    For i = 0 To 4
      If FileSize(d$ + "demo\demo_roms\invaders.h") = $800 Or FileSize(d$ + "machine\invaders_test.rom") > 0
        ProcedureReturn d$
      EndIf
      If Len(d$) <= 3 : Break : EndIf
      d$ = GetPathPart(Left(d$, Len(d$) - 1))
    Next
  Next
  ProcedureReturn ""
EndProcedure

Procedure.s MachineTestRom()
  ProcedureReturn Root$ + "machine\invaders_test.rom"
EndProcedure

Procedure.s DemoRom()
  ProcedureReturn Root$ + "demo\demo_roms"
EndProcedure

; A ROM or program named on the command line: as given (from the current
; folder), else from the exe's folder, else from the repository.
Procedure.s ResolvePath(p$)
  Protected q$ = RTrim(p$, "\")
  If FileSize(q$) <> -1 Or q$ = "" : ProcedureReturn q$ : EndIf
  If FileSize(GetPathPart(ProgramFilename()) + q$) <> -1 : ProcedureReturn GetPathPart(ProgramFilename()) + q$ : EndIf
  If Root$ <> "" And FileSize(Root$ + q$) <> -1 : ProcedureReturn Root$ + q$ : EndIf
  ProcedureReturn q$
EndProcedure

Procedure LoadMachine(path$, name$)
  If InvLoadRom(path$)
    LoadedName$ = name$ : RunCycles = 0 : SuiteIndex = -1 : RightTab = 0
    MachineAcc = 0 : MachineMs = ElapsedMilliseconds() : MachineFramesRun = 0
    Running = #True : MachineLoadError$ = ""
    Status$ = "Space Invaders hardware: " + name$ + " - the keys are on the Controls tab"
  Else
    MachineLoadError$ = "Cannot read the ROM " + path$ + " (one file up to 8 KB, or a folder with invaders.h/g/f/e)"
    Status$ = MachineLoadError$
    If MachineSelfTest = 0 And ExitAfter = 0
      MessageRequester("Intel 8080", MachineLoadError$, #PB_MessageRequester_Error)
    EndIf
  EndIf
EndProcedure

; The cabinet's controls, read while the window has the focus.
Procedure MachineInputs()
  Protected v.i
  If GetActiveWindow() = Win
    v = CtlInputsHeld()                                  ; controls.pbi
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
  *Neon_FontUI    = Neon_CreateFontPx("Segoe UI", Round(Neon_S(14), #PB_Round_Nearest))
  *Neon_FontSmall = Neon_CreateFontPx("Segoe UI", Round(Neon_S(12), #PB_Round_Nearest))
  *Neon_FontBold  = Neon_CreateFontPx("Segoe UI", Round(Neon_S(15), #PB_Round_Nearest), #PB_Font_Bold)
  *Neon_FontMono  = Neon_CreateFontPx("Consolas", Round(Neon_S(14), #PB_Round_Nearest))
  GLFontSetSnapToPixel(*Neon_FontUI, #True) : GLFontSetSnapToPixel(*Neon_FontSmall, #True)
  GLFontSetSnapToPixel(*Neon_FontBold, #True) : GLFontSetSnapToPixel(*Neon_FontMono, #True)
EndProcedure

; The window moved to a monitor with another scale: new Neon_UIScale, fonts
; rebuilt at the new size (the engine's hosting notes, section 5a).
Procedure CheckScale()
  Protected s.f = DisplayScale()
  If Abs(s - Neon_UIScale) < 0.001 : ProcedureReturn : EndIf
  Scale = s : Neon_UIScale = s
  SetGadgetAttribute(Gl, #PB_OpenGL_SetContext, #True)
  FreeGLFont(*Neon_FontUI) : FreeGLFont(*Neon_FontSmall) : FreeGLFont(*Neon_FontBold) : FreeGLFont(*Neon_FontMono)
  BuildFonts()
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
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(2), ty.f, fl.i = CpuFlags(), i.i
  Protected names$ = "S Z - A - P - C", bit.i
  Neon_Panel(x, y, w, h, "Registers", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB, Neon_S(26))
  ty = y + Neon_S(34)
  Neon_Text(*Neon_FontMono, x + Neon_S(12), ty, "A  " + H2(CpuA) + "     PSW " + H4((CpuA << 8) | fl), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, x + Neon_S(12), ty, "BC " + H4(CpuBC) + "   DE  " + H4(CpuDE), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, x + Neon_S(12), ty, "HL " + H4(CpuHL) + "   SP  " + H4(CpuSP), Neon_C_TextR, Neon_C_TextG, Neon_C_TextB) : ty + lh
  Neon_Text(*Neon_FontMono, x + Neon_S(12), ty, "PC " + H4(CpuPC) + "   (HL) " + H2(M(CpuHL)), Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB) : ty + lh * 1.4
  ; Flags, each lit when set.
  Protected fx.f = x + Neon_S(12), label$
  For i = 0 To 4
    label$ = StringField("S|Z|AC|P|CY", i + 1, "|")
    bit = Val(StringField("128|64|16|4|1", i + 1, "|"))
    If fl & bit
      Neon_Box(fx, ty, Neon_S(34), lh, 0.157, 0.365, 0.408)
      Neon_Text(*Neon_FontMono, fx + Neon_S(6), ty + Neon_S(1), label$, Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
    Else
      Neon_Frame(fx, ty, Neon_S(34), lh, Neon_C_LineR, Neon_C_LineG, Neon_C_LineB)
      Neon_Text(*Neon_FontMono, fx + Neon_S(6), ty + Neon_S(1), label$, Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
    EndIf
    fx + Neon_S(40)
  Next
  ty + lh * 1.5
  Neon_Text(*Neon_FontMono, x + Neon_S(12), ty, "INTE " + Str(CpuIE) + "   HALT " + Str(CpuHalted), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Neon_Text(*Neon_FontMono, x + Neon_S(12), ty, "instructions " + Str(CpuInstr), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Neon_Text(*Neon_FontMono, x + Neon_S(12), ty, "cycles       " + Str(RunCycles), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Neon_Text(*Neon_FontMono, x + Neon_S(12), ty, "at 2 MHz     " + StrF(RunCycles / 2000000.0, 2) + " s", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
EndProcedure

Procedure DisasmPane(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(2), ty.f = y + Neon_S(32), adr.i = CpuPC, i.i, bytes$, k.i
  Neon_Panel(x, y, w, h, "Disassembly", Neon_C_VioR, Neon_C_VioG, Neon_C_VioB, Neon_S(26))
  While ty + lh < y + h - Neon_S(6)
    bytes$ = ""
    For k = 0 To OpLen(M(adr)) - 1 : bytes$ + H2(M((adr + k) & $FFFF)) + " " : Next
    If adr = CpuPC
      Neon_Box(x + 2, ty - Neon_S(1), w - 4, lh, 0.20, 0.22, 0.26)
    EndIf
    If adr = Breakpoint
      Neon_Box(x + Neon_S(4), ty + Neon_S(3), Neon_S(6), lh - Neon_S(6), Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
    EndIf
    Neon_Text(*Neon_FontMono, x + Neon_S(14), ty, H4(adr) + "  " + LSet(bytes$, 10) + Disasm(adr),
              Bool(adr = CpuPC) * (Neon_C_AmbR - Neon_C_TextR) + Neon_C_TextR, Bool(adr = CpuPC) * (Neon_C_AmbG - Neon_C_TextG) + Neon_C_TextG,
              Bool(adr = CpuPC) * (Neon_C_AmbB - Neon_C_TextB) + Neon_C_TextB)
    adr = (adr + OpLen(M(adr))) & $FFFF
    ty + lh
  Wend
EndProcedure

Procedure MemoryPane(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(2), ty.f, rows.i, r.i, c.i, line$, asc$, adr.i, v.i
  Neon_Text(*Neon_FontUI, x + Neon_S(10), y + Neon_S(9), "Go to", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  CtlSet("Go to field", x + Neon_S(60), y + Neon_S(4), Neon_S(90), Neon_S(26))
  If Neon_TextInput(201, x + Neon_S(60), y + Neon_S(4), Neon_S(90), Neon_S(26), @MemText, "hex")
    MemTop = (Val("$" + MemText\s) & $FFF0) / 16
  EndIf
  If Btn(x + Neon_S(160), y + Neon_S(4), Neon_S(70), Neon_S(26), "PC") : MemTop = (CpuPC & $FFF0) / 16 : EndIf
  If Btn(x + Neon_S(236), y + Neon_S(4), Neon_S(70), Neon_S(26), "SP") : MemTop = (CpuSP & $FFF0) / 16 : EndIf
  If Btn(x + Neon_S(312), y + Neon_S(4), Neon_S(70), Neon_S(26), "HL") : MemTop = (CpuHL & $FFF0) / 16 : EndIf
  ty = y + Neon_S(40)
  rows = (h - Neon_S(46)) / lh
  If Neon_Hit(x, ty, w, h - Neon_S(40)) And Neon_Wheel : MemTop - Neon_Wheel * 3 : EndIf
  If MemTop > 4096 - rows : MemTop = 4096 - rows : EndIf
  If MemTop < 0 : MemTop = 0 : EndIf
  CtlSet("memory scroll bar", x + w - Neon_S(14), ty, Neon_S(12), h - Neon_S(46))
  Neon_ScrollBarV(202, x + w - Neon_S(14), ty, Neon_S(12), h - Neon_S(46), 4096, rows, @MemTop)
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
    Neon_Text(*Neon_FontMono, x + Neon_S(10), ty, line$ + " " + asc$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB)
    ty + lh
  Next
EndProcedure

Procedure ConsolePane(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(2), n.i = CountString(CpmOut$, #LF$) + 1
  Protected rows.i = (h - Neon_S(12)) / lh, i.i, ty.f = y + Neon_S(6), first.i
  first = n - rows
  If first < 0 : first = 0 : EndIf
  For i = first To n - 1
    Neon_Text(*Neon_FontMono, x + Neon_S(10), ty, StringField(CpmOut$, i + 1, #LF$), Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    ty + lh
  Next
EndProcedure

Procedure ResultsPane(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontMono) + Neon_S(6), ty.f = y + Neon_S(8)
  Neon_Text(*Neon_FontSmall, x + Neon_S(10), ty, "Instruction and cycle counts must equal the published reference (superzazu/8080).",
            Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  ty + lh * 1.3
  ForEach Results$()
    If FindString(Results$(), "PASS")
      Neon_Text(*Neon_FontMono, x + Neon_S(10), ty, Results$(), Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    Else
      Neon_Text(*Neon_FontMono, x + Neon_S(10), ty, Results$(), Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
    EndIf
    ty + lh
  Next
  If SuiteIndex >= 0
    Neon_Text(*Neon_FontMono, x + Neon_S(10), ty, CpmTests(SuiteIndex)\Name$ + "  running...  " + Str(CpuInstr) + " instructions",
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

; ---------------------------------------------------------------- full screen
; A borderless window over the monitor the window is on (no display-mode
; change); the windowed placement and style are kept and put back exactly on
; leaving. F11 or the Full screen button toggles it, Esc leaves it (neither the
; Space Invaders cabinet nor the CP/M console has an Esc key, so nothing is
; taken from the machine). Only the machine's screen is drawn: upright, at the
; cabinet monitor's 3:4 shape, centred on black. Emulation, 60 frames a second
; and sound run on; the pointer hides after two idle seconds.
Global FullScreen.i, FsStyle.i, FsCursorHidden.i, FsMouseX.i, FsMouseY.i, FsMouseMs.q
Global FsGameX.f, FsGameY.f, FsGameW.f, FsGameH.f, FsPlacement.WINDOWPLACEMENT, FsTex.GLSprite

Procedure FsShowCursor(show.i)
  If show And FsCursorHidden : ShowCursor_(#True) : FsCursorHidden = 0 : EndIf
  If show = 0 And FsCursorHidden = 0 : ShowCursor_(#False) : FsCursorHidden = 1 : EndIf
EndProcedure

Procedure EnterFullScreen()
  Protected hwnd.i = WindowID(Win), mi.MONITORINFO
  If FullScreen : ProcedureReturn : EndIf
  FsPlacement\length = SizeOf(WINDOWPLACEMENT) : GetWindowPlacement_(hwnd, @FsPlacement)
  FsStyle = GetWindowLongPtr_(hwnd, #GWL_STYLE)
  mi\cbSize = SizeOf(MONITORINFO) : GetMonitorInfo_(MonitorFromWindow_(hwnd, 2), @mi)   ; 2: the nearest monitor
  SetWindowLongPtr_(hwnd, #GWL_STYLE, FsStyle & ~(#WS_CAPTION | #WS_THICKFRAME | #WS_MINIMIZEBOX | #WS_MAXIMIZEBOX | #WS_SYSMENU))
  SetWindowPos_(hwnd, #HWND_TOP, mi\rcMonitor\left, mi\rcMonitor\top, mi\rcMonitor\right - mi\rcMonitor\left,
                mi\rcMonitor\bottom - mi\rcMonitor\top, #SWP_FRAMECHANGED | #SWP_NOOWNERZORDER | #SWP_SHOWWINDOW)
  FullScreen = 1 : FsMouseMs = ElapsedMilliseconds()
EndProcedure

Procedure LeaveFullScreen()
  Protected hwnd.i = WindowID(Win)
  If FullScreen = 0 : ProcedureReturn : EndIf
  SetWindowLongPtr_(hwnd, #GWL_STYLE, FsStyle)
  SetWindowPlacement_(hwnd, @FsPlacement)
  SetWindowPos_(hwnd, 0, 0, 0, 0, 0, #SWP_FRAMECHANGED | #SWP_NOMOVE | #SWP_NOSIZE | #SWP_NOZORDER | #SWP_NOOWNERZORDER)
  FullScreen = 0 : FsShowCursor(1)
EndProcedure

; The window's actions, from the key table.
Procedure DoAction(action.i)
  Select action
    Case #CTL_FULLSCREEN : If FullScreen : LeaveFullScreen() : Else : EnterFullScreen() : EndIf
    Case #CTL_LEAVEFULL : LeaveFullScreen()
  EndSelect
EndProcedure

; The screen's rectangle on a pw x ph canvas: the 224x256 picture upright at
; the cabinet monitor's 3:4 shape (a 4:3 tube turned on its side), the height a
; whole number of 256 lines when that loses less than a tenth of it, centred.
Procedure FsLayout(pw.i, ph.i)
  Protected hh.f, i.i
  hh = ph : If hh * 3.0 / 4.0 > pw : hh = pw * 4.0 / 3.0 : EndIf
  i = Int(hh / 256) : If i >= 1 And i * 256 >= hh * 0.9 : hh = i * 256 : EndIf
  FsGameH = hh : FsGameW = hh * 3.0 / 4.0
  FsGameX = (pw - FsGameW) / 2 : FsGameY = (ph - FsGameH) / 2
EndProcedure

; Full screen's frame: the machine's screen only.
Procedure FsDraw()
  glClearColor_(0.0, 0.0, 0.0, 1.0) : glClear_(#GL_COLOR_BUFFER_BIT)
  FsLayout(CanvasW, CanvasH)
  If Machine <> #MACHINE_INVADERS
    Neon_Text(*Neon_FontUI, Neon_S(24), Neon_S(24), "No machine ROM loaded - Esc leaves full screen", Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
    ProcedureReturn
  EndIf
  InvRender(*ScreenBuf)
  glBindTexture_(#GL_TEXTURE_2D, *ScreenTex\TextureID)
  glTexSubImage2D_(#GL_TEXTURE_2D, 0, 0, 0, 224, 256, #GL_BGRA_EXT, #GL_UNSIGNED_BYTE, *ScreenBuf)
  ; the same texture through a header of the shown size, so the quad takes the 3:4 shape
  FsTex\TextureID = *ScreenTex\TextureID : FsTex\Width = FsGameW : FsTex\Height = FsGameH
  DrawGLSprite(@FsTex, FsGameX, FsGameY, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, #True, -1.0, -1.0, -1.0, -1.0, #True)
EndProcedure

; The Controls tab: every key the window answers to, read from controls.pbi.
Procedure ControlsPane(x.f, y.f, w.f, h.f)
  Protected lh.f = GLFontLineHeight(*Neon_FontUI) + Neon_S(6), yy.f = y + Neon_S(10), c1.f = x + Neon_S(14), c2.f = x + Neon_S(200), c3.f = x + Neon_S(380)
  Neon_Text(*Neon_FontBold, c1, yy, "Space Invaders cabinet", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  Neon_Text(*Neon_FontBold, c2, yy, "Key", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  Neon_Text(*Neon_FontBold, c3, yy, "Port", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  yy + lh
  ForEach CtlKeys()
    If CtlKeys()\bit
      Neon_Text(*Neon_FontUI, c1, yy, CtlKeys()\what$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB)
      Neon_Text(*Neon_FontMono, c2, yy, CtlKeys()\key$, Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
      Neon_Text(*Neon_FontMono, c3, yy, "IN 1 bit " + Str(CtlBitNumber(CtlKeys()\bit)), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
      yy + lh
    EndIf
  Next
  Neon_Text(*Neon_FontUI, c1, yy, "Gamepad: none - the keyboard only. Keys work while the window has the focus.", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  yy + lh * 2
  Neon_Text(*Neon_FontBold, c1, yy, "Window", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  Neon_Text(*Neon_FontBold, c2, yy, "Key", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  yy + lh
  ForEach CtlKeys()
    If CtlKeys()\bit = 0
      Neon_Text(*Neon_FontUI, c1, yy, CtlKeys()\what$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB)
      Neon_Text(*Neon_FontMono, c2, yy, CtlKeys()\key$, Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
      yy + lh
    EndIf
  Next
  Neon_Text(*Neon_FontUI, c1, yy, "Full screen is also the button on the Screen tab. The machine has no Esc key of its own, so Esc is the window's.",
            Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
EndProcedure

Procedure ScreenPane(x.f, y.f, w.f, h.f)
  Protected k.i, sx.f, sy.f, lh.f = GLFontLineHeight(*Neon_FontSmall) + Neon_S(4), ty.f
  If Btn(x + Neon_S(10), y + Neon_S(6), Neon_S(150), Neon_S(28), "Machine test ROM", Bool(InvLoaded$ = MachineTestRom() And Machine = #MACHINE_INVADERS))
    LoadMachine(MachineTestRom(), "invaders_test.rom")
  EndIf
  If Btn(x + Neon_S(168), y + Neon_S(6), Neon_S(150), Neon_S(28), "PureMetal demo", Bool(InvLoaded$ = DemoRom() And Machine = #MACHINE_INVADERS))
    LoadMachine(DemoRom(), "PureMetal demo")
  EndIf
  If Btn(x + Neon_S(326), y + Neon_S(6), Neon_S(150), Neon_S(28), "Full screen  " + CtlActionKeys(#CTL_FULLSCREEN))
    EnterFullScreen()
  EndIf
  Neon_Text(*Neon_FontSmall, x + Neon_S(488), y + Neon_S(12), "Space Invaders (Taito 8080) hardware. Open... loads a ROM: 8 KB, or a folder of invaders.h/g/f/e",
            Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  If Machine <> #MACHINE_INVADERS
    Neon_Text(*Neon_FontUI, x + Neon_S(14), y + Neon_S(60), "No machine ROM loaded.", Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
    ProcedureReturn
  EndIf
  InvRender(*ScreenBuf)
  glBindTexture_(#GL_TEXTURE_2D, *ScreenTex\TextureID)
  glTexSubImage2D_(#GL_TEXTURE_2D, 0, 0, 0, 224, 256, #GL_BGRA_EXT, #GL_UNSIGNED_BYTE, *ScreenBuf)
  k = Int((h - Neon_S(60)) / 256)
  If Int((w - Neon_S(280)) / 224) < k : k = Int((w - Neon_S(280)) / 224) : EndIf
  If k < 1 : k = 1 : EndIf
  sx = x + Neon_S(14) : sy = y + Neon_S(44)
  Neon_Box(sx - 2, sy - 2, 224 * k + 4, 256 * k + 4, 0.0, 0.0, 0.0)
  DrawGLSprite(*ScreenTex, sx, sy, 0.0, k, 1.0, 1.0, 1.0, 1.0, #True, -1.0, -1.0, -1.0, -1.0, #True)
  ; Beside the screen: the machine's state.
  ty = sy
  sx + 224 * k + Neon_S(24)
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
  ForEach CtlKeys()                                    ; the keys, from controls.pbi
    Neon_Text(*Neon_FontSmall, sx, ty, CtlKeys()\key$ + "  " + CtlKeys()\what$, Neon_C_DimR, Neon_C_DimG, Neon_C_DimB) : ty + lh
  Next
  If AudioOk = 0
    Neon_Text(*Neon_FontSmall, sx, ty, "sound off", Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
  EndIf
EndProcedure

Procedure DrawFrame()
  Protected bx.f, by.f, bw.f = Neon_S(96), bh.f = Neon_S(30), i.i, colW.f, top.f, half.f, sel.i
  Protected f$
  ; Toolbar.
  Neon_Box(0, 0, CanvasW, Neon_S(48), Neon_C_HeadR, Neon_C_HeadG, Neon_C_HeadB)
  Neon_Text(*Neon_FontBold, Neon_S(14), Neon_S(14), "INTEL 8080", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  bx = Neon_S(120) : by = Neon_S(9)
  If Btn(bx, by, bw, bh, "Open...")
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
  bx + bw + Neon_S(6)
  For i = 0 To 3
    If Btn(bx, by, Neon_S(84), bh, CpmTests(i)\Name$, Bool(LoadedName$ = CpmTests(i)\Name$))
      SuiteIndex = -1 : LoadProgram(Folder$ + CpmTests(i)\File$, CpmTests(i)\Name$) : RightTab = 1
    EndIf
    bx + Neon_S(90)
  Next
  If Btn(bx, by, Neon_S(120), bh, "Run all suites", Bool(SuiteIndex >= 0))
    ClearList(Results$()) : StartSuite(0)
  EndIf
  bx + Neon_S(136)
  If Btn(bx, by, Neon_S(70), bh, "Run", Running, Bool(Running = 0)) : Running = #True : Status$ = "Running" : EndIf
  bx + Neon_S(76)
  If Btn(bx, by, Neon_S(70), bh, "Pause", #False, Running) : Running = #False : Status$ = "Paused at $" + H4(CpuPC) : EndIf
  bx + Neon_S(76)
  If Btn(bx, by, Neon_S(70), bh, "Step", #False, Bool(Running = 0))
    RunCycles + CpuRun(1) : Status$ = "Stepped to $" + H4(CpuPC)
  EndIf
  bx + Neon_S(76)
  If Btn(bx, by, Neon_S(80), bh, "Step 100", #False, Bool(Running = 0))
    For i = 1 To 100
      RunCycles + CpuRun(1)
      If CpmFinished Or CpuHalted Or CpuPC = Breakpoint : Break : EndIf
    Next
    Status$ = "Stepped to $" + H4(CpuPC)
  EndIf
  bx + Neon_S(86)
  If Btn(bx, by, Neon_S(70), bh, "Reset", #False, Bool(LoadedName$ <> ""))
    SuiteIndex = -1
    If Machine = #MACHINE_INVADERS
      LoadMachine(InvLoaded$, LoadedName$)
    ElseIf LoadedName$ <> "" And FindString(CpmLoaded$, ".")
      LoadProgram(CpmLoaded$, LoadedName$)
    EndIf
  EndIf
  bx + Neon_S(84)
  Neon_Text(*Neon_FontUI, bx, by + Neon_S(6), "Break at", Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  CtlSet("Break at field", bx + Neon_S(64), by, Neon_S(80), bh)
  If Neon_TextInput(101, bx + Neon_S(64), by, Neon_S(80), bh, @BpText, "none")
    If Trim(BpText\s) = "" : Breakpoint = -1 : Else : Breakpoint = Val("$" + Trim(BpText\s)) & $FFFF : EndIf
  EndIf
  Neon_TextRight(*Neon_FontUI, CanvasW - Neon_S(14), by + Neon_S(6), SpeedShown$, Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)

  ; Panes: registers and disassembly on the left; console, memory, results on the right.
  top = Neon_S(56)
  colW = Neon_S(440)
  RegistersPane(Neon_S(8), top, colW, Neon_S(300))
  DisasmPane(Neon_S(8), top + Neon_S(308), colW, CanvasH - top - Neon_S(308) - Neon_S(40))
  Neon_Panel(colW + Neon_S(16), top, CanvasW - colW - Neon_S(24), CanvasH - top - Neon_S(40), "", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  sel = Neon_TabStrip(300, colW + Neon_S(17), top + 1, CanvasW - colW - Neon_S(26), Neon_S(30), "Screen|Console|Memory|Suite results|Controls", RightTab)
  If sel <> RightTab : RightTab = sel : EndIf
  Select RightTab
    Case 0 : ScreenPane(colW + Neon_S(16), top + Neon_S(34), CanvasW - colW - Neon_S(24), CanvasH - top - Neon_S(78))
    Case 1 : ConsolePane(colW + Neon_S(16), top + Neon_S(34), CanvasW - colW - Neon_S(24), CanvasH - top - Neon_S(78))
    Case 2 : MemoryPane(colW + Neon_S(16), top + Neon_S(34), CanvasW - colW - Neon_S(24), CanvasH - top - Neon_S(78))
    Case 4 : ControlsPane(colW + Neon_S(16), top + Neon_S(34), CanvasW - colW - Neon_S(24), CanvasH - top - Neon_S(78))
    Default : ResultsPane(colW + Neon_S(16), top + Neon_S(34), CanvasW - colW - Neon_S(24), CanvasH - top - Neon_S(78))
  EndSelect
  ; Status line.
  Neon_Box(0, CanvasH - Neon_S(30), CanvasW, Neon_S(30), Neon_C_HeadR, Neon_C_HeadG, Neon_C_HeadB)
  Neon_Text(*Neon_FontSmall, Neon_S(12), CanvasH - Neon_S(23), Status$, Neon_C_TextR, Neon_C_TextG, Neon_C_TextB)
  Neon_TextRight(*Neon_FontSmall, CanvasW - Neon_S(12), CanvasH - Neon_S(23),
                 "core: generated from the Pico core's opcode table - dispatch: computed goto", Neon_C_FaintR, Neon_C_FaintG, Neon_C_FaintB)
EndProcedure

; ---------------------------------------------------------------- --pointer-test
; The mouse and the controls at the desktop's scale, without the real pointer
; (it is shared): the chrome is driven with synthetic positions in the units
; WindowMouseX/Y give a DPI-aware window - physical pixels (GlUIChrome.pbi 5a).
; For every control, four points: just inside its top-left and bottom-right
; corners (the press must land), just right of it and just below it (it must
; not - right of a tab is the next tab). Every frame Neon_MX/Neon_MY must read
; the point back unbent. Controls at the top (toolbar, tabs) and at the bottom
; (the memory view's scroll bar) are both covered.
Global SynthFile$, SynthX.f, SynthY.f, SynthDown.i, SynthCase.i, SynthPoint.i, SynthFrame.i
Global SynthFails.i, SynthPoints.i, SynthLog$, SynthWorst.f, SynthMemTop.i, SynthRunning.i
Global Dim SynthName$(40), Dim SynthTab.i(40), Dim SynthRun.i(40), SynthCount.i
#SYNTH_TABS = 5                     ; Screen, Console, Memory, Suite results, Controls

Procedure SynthAdd(name$, tab.i, run.i)
  SynthName$(SynthCount) = name$ : SynthTab(SynthCount) = tab : SynthRun(SynthCount) = run : SynthCount + 1
EndProcedure

Procedure SynthInit()
  Protected i.i
  ; the toolbar (top of the window); run = the Running state that enables the button (-1: either)
  SynthAdd("Open...", -1, -1)
  For i = 0 To 3 : SynthAdd(CpmTests(i)\Name$, -1, -1) : Next
  SynthAdd("Run all suites", -1, -1) : SynthAdd("Run", -1, 0) : SynthAdd("Pause", -1, 1)
  SynthAdd("Step", -1, 0) : SynthAdd("Step 100", -1, 0) : SynthAdd("Reset", -1, -1) : SynthAdd("Break at field", -1, -1)
  ; the tabs
  For i = 0 To #SYNTH_TABS - 1 : SynthAdd("tab " + Str(i), -1, -1) : Next
  ; the Screen tab's buttons
  SynthAdd("Machine test ROM", 0, -1) : SynthAdd("PureMetal demo", 0, -1) : SynthAdd("Full screen  " + CtlActionKeys(#CTL_FULLSCREEN), 0, -1)
  ; the Memory tab: field, buttons, and the scroll bar reaching the bottom of the window
  SynthAdd("Go to field", 2, -1) : SynthAdd("PC", 2, -1) : SynthAdd("SP", 2, -1) : SynthAdd("HL", 2, -1)
  SynthAdd("memory scroll bar", 2, -1)
EndProcedure

; The control's rectangle as last drawn; 0 when it was not.
Procedure.i SynthRect(name$, *r.CtlRect)
  Protected *row.Neon_TabRowLayout, i.i
  If Left(name$, 4) = "tab "
    If FindMapElement(Neon_TabLayout(), "300") = 0 : ProcedureReturn 0 : EndIf
    *row = @Neon_TabLayout() : i = Val(Mid(name$, 5))
    ; the row's last pixel belongs to the strip's underline, not to a tab
    *r\x = *row\X(i) : *r\w = *row\W(i) : *r\y = *row\Y : *r\h = *row\H - 1
    ProcedureReturn 1
  EndIf
  If FindMapElement(Ctl(), name$) = 0 : ProcedureReturn 0 : EndIf
  *r\x = Ctl()\x : *r\y = Ctl()\y : *r\w = Ctl()\w : *r\h = Ctl()\h
  ProcedureReturn 1
EndProcedure

Procedure SynthFinish()
  Protected f.i
  SynthLog$ + "pointer-test: " + Str(SynthPoints) + " points on " + Str(SynthCount) + " controls, " + Str(SynthFails) +
              " failures, scale " + StrF(Neon_UIScale, 2) + ", canvas " + Str(CanvasW) + "x" + Str(CanvasH) +
              ", worst pointer read-back error " + StrF(SynthWorst, 2) + " px" + #LF$
  f = CreateFile(#PB_Any, SynthFile$)
  If f : WriteString(f, SynthLog$) : CloseFile(f) : EndIf
  Quit = #True
EndProcedure

; One frame of the test (called after the frame is drawn).
Procedure SynthStep()
  Protected r.CtlRect, name$ = SynthName$(SynthCase), x.f, y.f, inside.i, hit.i, expect$, got$, i.i
  If SynthCase >= SynthCount : SynthFinish() : ProcedureReturn : EndIf
  If Abs(Neon_MX - SynthX) > SynthWorst : SynthWorst = Abs(Neon_MX - SynthX) : EndIf
  If Abs(Neon_MY - SynthY) > SynthWorst : SynthWorst = Abs(Neon_MY - SynthY) : EndIf
  SynthFrame + 1
  Select SynthFrame
    Case 1                                              ; the state that shows and enables the control
      If SynthTab(SynthCase) >= 0 : RightTab = SynthTab(SynthCase) : EndIf
      SynthRunning = Running
      If SynthRun(SynthCase) >= 0 : Running = SynthRun(SynthCase) : EndIf
      If name$ = "memory scroll bar" : MemTop = 1000 : EndIf   ; thumb mid-way: a press above or below it pages
      SynthX = 1 : SynthY = CanvasH - 2 : SynthDown = 0
    Case 2                                              ; drawn: go to the point
      If SynthRect(name$, @r) = 0
        SynthLog$ + "FAIL " + name$ + ": not drawn" + #LF$ : SynthFails + 1
        Running = SynthRunning : RightTab = 0 : SynthFrame = 0 : SynthPoint = 0 : SynthCase + 1 : ProcedureReturn
      EndIf
      Select SynthPoint
        Case 0 : SynthX = r\x + 2 : SynthY = r\y + 2
        Case 1 : SynthX = r\x + r\w - 2 : SynthY = r\y + r\h - 2
        Case 2 : SynthX = r\x + r\w + 2 : SynthY = r\y + r\h - 2
        Case 3 : SynthX = r\x + r\w - 2 : SynthY = r\y + r\h + 2
      EndSelect
      SynthClicked$ = "" : Neon_FocusID = 0 : SynthMemTop = MemTop
      If Left(name$, 4) = "tab " : RightTab = 99 : EndIf  ; no tab selected, so any selection shows
    Case 3 : SynthDown = 1
    Case 4 : SynthDown = 0
    Case 5                                              ; what the press did
      inside = Bool(SynthPoint <= 1)
      If Left(name$, 4) = "tab "
        i = Val(Mid(name$, 5))
        If inside : expect$ = "tab " + Str(i) : ElseIf SynthPoint = 2 And i < #SYNTH_TABS - 1 : expect$ = "tab " + Str(i + 1) : Else : expect$ = "" : EndIf
        If RightTab >= 0 And RightTab < #SYNTH_TABS : got$ = "tab " + Str(RightTab) : EndIf
      ElseIf name$ = "Break at field" Or name$ = "Go to field"
        If inside : expect$ = name$ : EndIf
        If (name$ = "Break at field" And Neon_FocusID = 101) Or (name$ = "Go to field" And Neon_FocusID = 201) : got$ = name$ : EndIf
      ElseIf name$ = "memory scroll bar"
        If inside : expect$ = name$ : EndIf
        If MemTop <> SynthMemTop : got$ = name$ : EndIf
      Else
        If inside : expect$ = name$ : EndIf
        got$ = SynthClicked$
      EndIf
      SynthPoints + 1
      hit = Bool(got$ = expect$)
      If hit = 0 : SynthFails + 1 : EndIf
      SynthLog$ + StringField("FAIL|ok  ", hit + 1, "|") + " " + LSet(name$, 18) + " " + StringField("top-left in|bottom-right in|right of it|below it", SynthPoint + 1, "|") +
                  " (" + StrF(SynthX, 1) + ", " + StrF(SynthY, 1) + "): expected '" + expect$ + "', got '" + got$ + "'" + #LF$
      ; put things back
      MemTop = SynthMemTop : Neon_FocusID = 0 : Running = SynthRunning
      If SynthTab(SynthCase) >= 0 Or Left(name$, 4) = "tab " : RightTab = 0 : EndIf
      SynthFrame = 0 : SynthPoint + 1
      If SynthPoint > 3 : SynthPoint = 0 : SynthCase + 1 : EndIf
  EndSelect
EndProcedure

; ---------------------------------------------------------------- --fullscreen-test
; Full screen by its own keys, without the real pointer: F11 is posted to the
; window's GL gadget and Esc to the window (the engine's Esc shortcut). Checked:
; the window covers its monitor, the screen is upright at 3:4 and centred, Esc
; leaves, and the windowed rectangle and style come back exactly.
Global FsTestOn.i, FsTestFile$, FsTestShot$, FsTestStep.i, FsTestWait.i, FsTestFails.i, FsTestLog$
Global FsTestRect.RECT, FsTestStyle.i

Procedure FsTestCheck(ok.i, what$)
  If ok = 0 : FsTestFails + 1 : FsTestLog$ + "FAIL " : Else : FsTestLog$ + "ok   " : EndIf
  FsTestLog$ + what$ + #LF$
EndProcedure

Procedure FsTestTick()
  Protected r.RECT, mi.MONITORINFO, hwnd.i = WindowID(Win), f.i, aspect.f
  If FsTestStep = 0 And Machine = #MACHINE_INVADERS And InvFrames < 420 : ProcedureReturn : EndIf   ; windowed until the demo's titles are up
  FsTestWait + 1 : If FsTestWait < 30 : ProcedureReturn : EndIf
  FsTestWait = 0 : FsTestStep + 1
  Select FsTestStep
    Case 1
      GetWindowRect_(hwnd, @FsTestRect) : FsTestStyle = GetWindowLongPtr_(hwnd, #GWL_STYLE)
      FsTestLog$ + "windowed: " + Str(FsTestRect\left) + "," + Str(FsTestRect\top) + " " + Str(FsTestRect\right - FsTestRect\left) + "x" +
                   Str(FsTestRect\bottom - FsTestRect\top) + ", scale " + StrF(Neon_UIScale, 2) + ", machine " + LoadedName$ + #LF$
      PostMessage_(GadgetID(Gl), #WM_KEYDOWN, #VK_F11, 0) : PostMessage_(GadgetID(Gl), #WM_KEYUP, #VK_F11, 0)
    Case 2
      GetWindowRect_(hwnd, @r) : mi\cbSize = SizeOf(MONITORINFO) : GetMonitorInfo_(MonitorFromWindow_(hwnd, 2), @mi)
      FsTestCheck(FullScreen, "F11 entered full screen")
      FsTestCheck(Bool(r\left = mi\rcMonitor\left And r\top = mi\rcMonitor\top And r\right = mi\rcMonitor\right And r\bottom = mi\rcMonitor\bottom),
                  "the window covers its monitor " + Str(mi\rcMonitor\right - mi\rcMonitor\left) + "x" + Str(mi\rcMonitor\bottom - mi\rcMonitor\top))
      FsTestCheck(Bool(CanvasW = mi\rcMonitor\right - mi\rcMonitor\left And CanvasH = mi\rcMonitor\bottom - mi\rcMonitor\top),
                  "the canvas is the whole monitor (" + Str(CanvasW) + "x" + Str(CanvasH) + ")")
      aspect = FsGameW / FsGameH
      FsTestCheck(Bool(Abs(aspect - 0.75) < 0.002), "the screen " + StrF(FsGameW, 1) + "x" + StrF(FsGameH, 1) + " is upright at the cabinet's 3:4 (" + StrF(aspect, 4) + ")")
      FsTestCheck(Bool(Abs(FsGameX * 2 + FsGameW - CanvasW) <= 1 And Abs(FsGameY * 2 + FsGameH - CanvasH) <= 1), "it is centred at " + StrF(FsGameX, 1) + "," + StrF(FsGameY, 1))
      FsTestCheck(Bool(Machine = #MACHINE_INVADERS And InvFrames > 0), "the machine runs on (frame " + Str(InvFrames) + ")")
      If FsTestShot$ <> "" : SaveScreenshot(FsTestShot$) : EndIf
    Case 3
      PostMessage_(hwnd, #WM_KEYDOWN, #VK_ESCAPE, 0) : PostMessage_(hwnd, #WM_KEYUP, #VK_ESCAPE, 0)
    Case 4
      GetWindowRect_(hwnd, @r)
      FsTestCheck(Bool(FullScreen = 0), "Esc left full screen")
      FsTestCheck(Bool(r\left = FsTestRect\left And r\top = FsTestRect\top And r\right = FsTestRect\right And r\bottom = FsTestRect\bottom),
                  "the windowed rectangle came back: " + Str(r\left) + "," + Str(r\top) + " " + Str(r\right - r\left) + "x" + Str(r\bottom - r\top))
      FsTestCheck(Bool(GetWindowLongPtr_(hwnd, #GWL_STYLE) = FsTestStyle), "the window's frame and style came back")
      FsTestLog$ + "fullscreen-test: " + Str(FsTestFails) + " failures" + #LF$
      f = CreateFile(#PB_Any, FsTestFile$) : If f : WriteString(f, FsTestLog$) : CloseFile(f) : EndIf
      Quit = #True
  EndSelect
EndProcedure

; ---------------------------------------------------------------- main
Procedure Main()
  Protected ev.i, now.q, dt.f, arg$, lib.i, fn.i, w.i = 1400, h.i = 880, down.b, log.i, k.i, mute.i
  ; --mute and --exit-after <frames> may stand anywhere; the first other word is what to load.
  For k = 0 To CountProgramParameters() - 1
    If LCase(ProgramParameter(k)) = "--mute"
      mute = #True
    ElseIf LCase(ProgramParameter(k)) = "--tab"
      k + 1 : StartTab = Val(ProgramParameter(k)) + 1            ; 0 Screen ... 4 Controls
    ElseIf LCase(ProgramParameter(k)) = "--fullscreen-test"
      k + 1 : FsTestOn = #True : FsTestFile$ = ProgramParameter(k) : mute = #True
    ElseIf LCase(ProgramParameter(k)) = "--fullscreen-shot"
      k + 1 : FsTestShot$ = ProgramParameter(k)
    ElseIf LCase(ProgramParameter(k)) = "--pointer-test"
      k + 1 : SynthOn = #True : SynthFile$ = ProgramParameter(k) : mute = #True
    ElseIf LCase(ProgramParameter(k)) = "--exit-after"
      k + 1 : ExitAfter = Val(ProgramParameter(k))
    ElseIf arg$ = ""
      arg$ = ProgramParameter(k)
    EndIf
  Next
  ; Per-monitor DPI awareness before any window exists.
  lib = OpenLibrary(#PB_Any, "user32.dll")
  If lib
    fn = GetFunction(lib, "SetProcessDpiAwarenessContext")
    If fn : CallFunctionFast(fn, -4) : EndIf
    CloseLibrary(lib)
  EndIf
  ProfMark("dpi")
  CpmInitTests()
  CtlInit()
  If SynthOn : SynthInit() : EndIf
  InitDisasm()
  Root$ = RepoRoot()
  Folder$ = CpmTestFolder()
  If FileSize(Folder$ + CpmTests(0)\File$) <= 0 And Root$ <> ""
    Folder$ = Root$ + "Diagnostics\upstream\"      ; where tools/fetch_tests.py puts them
  EndIf
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
  ; The frame is drawn 1:1 and never goes out through DrawRetroCRT: with the
  ; engine's default (on) every pointer position is bent by the CRT curve,
  ; worst near the top and bottom (GlUIChrome.pbi 5a).
  UI_UseCRT = #False
  ProfMark("canvas")
  ScreenInit()
  If LCase(arg$) = "--selftest"
    SelfTest = #True
    StartSuite(0)
  ElseIf LCase(arg$) = "--machine-selftest"
    ; optionally: a ROM (file or folder) and how many frames to run first
    MachineSelfTest = #True
    If ProgramParameter(1) <> "" And LCase(ProgramParameter(1)) <> "--mute"
      LoadMachine(ResolvePath(ProgramParameter(1)), GetFilePart(RTrim(ProgramParameter(1), "\")))
      If Val(ProgramParameter(2)) > 0 : MachineSelfTestFrames = Val(ProgramParameter(2)) : EndIf
    Else
      LoadMachine(MachineTestRom(), "invaders_test.rom")
    EndIf
    If MachineLoadError$ <> ""
      ; No window left waiting: say so in the log and the exit code.
      log = CreateFile(#PB_Any, GetPathPart(ProgramFilename()) + "machine-selftest.log")
      If log : WriteStringN(log, "FAIL " + MachineLoadError$) : CloseFile(log) : EndIf
      End 1
    EndIf
  ElseIf arg$ <> ""
    If mute = 0 : AudioOpen() : EndIf
    arg$ = ResolvePath(arg$)
    If LCase(GetExtensionPart(arg$)) = "com"
      LoadProgram(arg$, GetFilePart(arg$)) : RightTab = 1
    Else
      LoadMachine(arg$, GetFilePart(arg$))
    EndIf
  Else
    ; No argument (a double-click): the PureMetal demo on the Screen tab.
    If mute = 0 : AudioOpen() : EndIf
    LoadMachine(DemoRom(), "PureMetal demo")
  EndIf
  If StartTab : RightTab = StartTab - 1 : EndIf
  ProfMark("loaded")
  LastMs = ElapsedMilliseconds()
  ProfStartup = ElapsedMilliseconds() - ProfBoot
  Repeat
    ProfT = ElapsedMilliseconds()
    Repeat
      ev = WindowEvent()
      Select ev
        Case #PB_Event_CloseWindow : Quit = #True
        Case #PB_Event_SizeWindow : CheckScale() : SizeCanvas()
        Case #PB_Event_MoveWindow : CheckScale() : SizeCanvas()
        Case #PB_Event_Menu
          ; the engine maps Esc to menu event 1001 on the window: Esc leaves full screen
          If EventMenu() = 1001 : DoAction(CtlAction(#VK_ESCAPE)) : EndIf
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
    If KeyCode And CtlAction(KeyCode) : DoAction(CtlAction(KeyCode)) : EndIf   ; F11 (controls.pbi)
    ProfEvents + ElapsedMilliseconds() - ProfT
    ProfT = ElapsedMilliseconds()
    If Running : RunSlice(14) : EndIf
    ProfRun + ElapsedMilliseconds() - ProfT
    now = ElapsedMilliseconds() : dt = (now - LastMs) / 1000.0 : LastMs = now
    down = Bool(MouseDown Or (GetActiveWindow() = Win And (GetAsyncKeyState_(#VK_LBUTTON) & $8000)))
    SetGadgetAttribute(Gl, #PB_OpenGL_SetContext, #True)
    If SynthOn
      Neon_ChromeBeginFrame(SynthX, SynthY, SynthDown, 0, 0, 0, dt)   ; --pointer-test: the real pointer is not read
    Else
      Neon_ChromeBeginFrame(WindowMouseX(Win), WindowMouseY(Win), down, Wheel, KeyCode, KeyChar, dt)
    EndIf
    Wheel = 0 : KeyCode = 0 : KeyChar = 0
    glBindFramebuffer(#GL_FRAMEBUFFER, 0)
    glDisable_(#GL_SCISSOR_TEST)
    glViewport_(0, 0, CanvasW, CanvasH)
    glClearColor_(Neon_C_BgR, Neon_C_BgG, Neon_C_BgB, 1.0)
    glClear_(#GL_COLOR_BUFFER_BIT)
    ProfT = ElapsedMilliseconds()
    If FullScreen
      FsDraw()
      ; the pointer hides after two idle seconds and comes back when it moves
      If WindowMouseX(Win) <> FsMouseX Or WindowMouseY(Win) <> FsMouseY
        FsMouseX = WindowMouseX(Win) : FsMouseY = WindowMouseY(Win) : FsMouseMs = now : FsShowCursor(1)
      ElseIf now - FsMouseMs > 2000
        FsShowCursor(0)
      EndIf
    Else
      DrawFrame()
    EndIf
    ProfDraw + ElapsedMilliseconds() - ProfT
    Neon_ChromeEndFrame()
    If SynthOn : SynthStep() : EndIf
    If FsTestOn : FsTestTick() : EndIf
    If SelfTest And SuiteIndex = -1 And SelfTestDone = 0
      SelfTestDone = 1
      RightTab = 3                      ; draw the results tab once more, then capture it
    ElseIf SelfTestDone = 1 And MachineSelfTest
      SaveScreenshot(GetPathPart(ProgramFilename()) + "machine-selftest.png")
      log = CreateFile(#PB_Any, GetPathPart(ProgramFilename()) + "machine-selftest.log")
      If log
        WriteStringN(log, "rom=" + InvLoaded$)
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
    If ExitAfter > 0 And ProfFrames >= ExitAfter
      ; --exit-after: what this start loaded, for a check with no one watching
      SaveScreenshot(GetPathPart(ProgramFilename()) + "startup.png")
      log = CreateFile(#PB_Any, GetPathPart(ProgramFilename()) + "startup.log")
      If log
        WriteStringN(log, "cwd=" + GetCurrentDirectory())
        WriteStringN(log, "root=" + Root$)
        WriteStringN(log, "loaded=" + LoadedName$ + " rom=" + InvLoaded$ + " machine_frames=" + Str(InvFrames))
        WriteStringN(log, "status=" + Status$)
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
  FsShowCursor(1)
  AudioClose()
EndProcedure
Main()
