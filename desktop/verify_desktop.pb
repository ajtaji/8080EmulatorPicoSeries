; Console verification and benchmark of the desktop 8080 core.
;   pbcompilerc verify_desktop.pb /CONSOLE /OPTIMIZER /EXE verify_desktop.exe [/CONSTANT CPU_DISPATCH=1]
; Prints every verdict; exit code 0 only when everything passed.
XIncludeFile "cpm.pbi"

Global Failures.i, Checks.i

Procedure Check(ok.i, what$, got.i = 0, want.i = 0)
  Checks + 1
  If ok = 0
    Failures + 1
    If Failures <= 20
      PrintN("  FAIL " + what$ + " got=$" + Hex(got) + " want=$" + Hex(want))
    EndIf
  EndIf
EndProcedure

Procedure Start(pc.i)
  CpuReset() : CpuPC = pc : CpuSP = $F000
EndProcedure

Procedure Poke8080(adr.i, bytes$)
  ; bytes$: hex pairs separated by spaces
  Protected i.i, n.i = CountString(bytes$, " ") + 1
  For i = 1 To n
    M(adr + i - 1) = Val("$" + StringField(bytes$, i, " "))
  Next
EndProcedure

Procedure ApiChecks()
  Protected r.i, p.i, j.i, want.i, got.i, taken.i, i.i
  For i = 0 To 65535 : M(i) = 0 : Next
  Start($100)
  Check(Bool(CpuRun(0) = 0 And CpuRun(-5) = 0 And CpuPC = $100), "budget 0 / negative")
  ; MVI B,10 / XRA A / ADD B / DCR B / JNZ / HLT: 33 instructions, 208 cycles.
  Poke8080($100, "06 0A AF 80 05 C2 03 01 76")
  Start($100)
  r = CpuRun(1000)
  Check(Bool(CpuA = 55 And CpuInstr = 33), "sum", CpuInstr, 33)
  Check(Bool(r = 1000 And CpuHalted = 1 And CpuPC = $109), "HLT spends the window", r, 1000)
  Check(Bool(CpuRun(10) = 10), "halted window")
  Check(Bool(CpuInterrupt($FF) = 0), "RST refused while DI")
  Start($100)
  r = 0
  While CpuHalted = 0 And r < 1000
    r + CpuRun(1)
  Wend
  Check(Bool(r = 208), "sum cycles one at a time", r, 208)
  ; EI / HLT, then RST 7.
  Poke8080($200, "FB 76")
  Start($200)
  CpuRun(100)
  Check(Bool(CpuHalted = 1 And CpuIE = 1 And CpuInterrupt($FF) = 11), "RST 7 accepted after EI;HLT")
  Check(Bool(CpuPC = $38 And CpuHalted = 0 And CpuIE = 0 And CpuSP = $EFFE And M($EFFE) = 2 And M($EFFF) = 2), "RST 7 state", CpuPC, $38)
  ; EI delay.
  Poke8080($300, "FB 00 00")
  Start($300)
  CpuRun(1)
  Check(Bool(CpuIE = 1 And CpuInterrupt($CF) = 0), "refused right after EI")
  CpuRun(1)
  Check(Bool(CpuInterrupt($CF) = 11 And CpuPC = 8), "accepted one instruction after EI", CpuPC, 8)
  Poke8080($340, "FB 00 76")
  Start($340)
  CpuRun(100)
  Check(Bool(CpuInterrupt($D7) = 11 And CpuPC = $10), "EI mid-window")
  Start($300) : CpuIE = 1
  Check(Bool(CpuInterrupt($C3) = 0 And CpuInterrupt($100) = 0 And CpuInterrupt($C7) = 11 And CpuPC = 0), "only RST accepted")
  Poke8080($310, "FB 00 F3 76")
  Start($310)
  CpuRun(100)
  Check(Bool(CpuIE = 0 And CpuInterrupt($FF) = 0), "DI")
  ; Every PSW, through CpuSetFlags/CpuFlags and POP PSW / PUSH PSW, and every
  ; condition of Jcc, Ccc and Rcc with its cycles.
  Poke8080($400, "F1 F5 76")
  For p = 0 To 255
    want = (p & $D5) | 2
    CpuSetFlags(p)
    Check(Bool(CpuFlags() = want), "flags round trip", CpuFlags(), want)
    Start($400)
    CpuSP = $0FFE : M($0FFE) = p : M($0FFF) = $77
    CpuRun(100)
    got = M($0FFE) | (M($0FFF) << 8)
    Check(Bool(got = (want | $7700) And CpuA = $77), "POP/PUSH PSW", got, want | $7700)
    For j = 0 To 7
      Select j
        Case 0 : taken = Bool((p & $40) = 0)
        Case 1 : taken = Bool((p & $40) <> 0)
        Case 2 : taken = Bool((p & 1) = 0)
        Case 3 : taken = Bool((p & 1) <> 0)
        Case 4 : taken = Bool((p & 4) = 0)
        Case 5 : taken = Bool((p & 4) <> 0)
        Case 6 : taken = Bool((p & $80) = 0)
        Default : taken = Bool((p & $80) <> 0)
      EndSelect
      M($500) = $C2 | (j << 3) : M($501) = 0 : M($502) = 6
      Start($500) : CpuSetFlags(p)
      r = CpuRun(1)
      If taken
        Check(Bool(r = 10 And CpuPC = $600), "Jcc taken", (j << 8) | p)
      Else
        Check(Bool(r = 10 And CpuPC = $503), "Jcc not taken", (j << 8) | p)
      EndIf
      M($500) = $C4 | (j << 3)
      Start($500) : CpuSetFlags(p)
      r = CpuRun(1)
      If taken
        Check(Bool(r = 17 And CpuPC = $600 And CpuSP = $EFFE And M($EFFE) = 3 And M($EFFF) = 5), "Ccc taken", (j << 8) | p)
      Else
        Check(Bool(r = 11 And CpuPC = $503 And CpuSP = $F000), "Ccc not taken", (j << 8) | p)
      EndIf
      M($500) = $C0 | (j << 3)
      Start($500) : CpuSetFlags(p)
      CpuSP = $0FFE : M($0FFE) = $34 : M($0FFF) = $12
      r = CpuRun(1)
      If taken
        Check(Bool(r = 11 And CpuPC = $1234 And CpuSP = $1000), "Rcc taken", (j << 8) | p)
      Else
        Check(Bool(r = 5 And CpuPC = $501 And CpuSP = $0FFE), "Rcc not taken", (j << 8) | p)
      EndIf
      Check(Bool(CpuFlags() = want), "flags kept by branch", CpuFlags(), want)
    Next
  Next
  ; Undocumented opcodes.
  Poke8080($800, "CB 10 08")
  Poke8080($810, "DD 20 08 08 ED 30 08 76")
  Poke8080($820, "D9")
  Poke8080($830, "FD 40 08 D9")
  Poke8080($840, "10 18 20 28 30 38 D9")
  Start($800)
  CpuRun(1000)
  Check(Bool(CpuHalted = 1 And CpuPC = $818 And CpuSP = $F000 And CpuInstr = 15), "undocumented opcodes", CpuPC, $818)
  ; Self-modifying code.
  Poke8080($700, "3E 3C 32 05 07 00 76")
  Start($700)
  CpuRun(1000)
  Check(Bool(CpuA = $3D And CpuPC = $707), "self-modifying code", CpuA, $3D)
  ; XTHL, XCHG, SHLD/LHLD wrapping at $FFFF, SPHL, PCHL.
  Poke8080($900, "21 CD AB 31 00 0A E3 11 66 55 EB 22 FF FF 21 00 00 2A FF FF F9 21 20 09 E9")
  M($920) = $76 : M($A00) = $11 : M($A01) = $22
  Start($900)
  CpuRun(1000)
  Check(Bool(CpuDE = $2211 And M($A00) = $CD And M($A01) = $AB), "XTHL/XCHG")
  Check(Bool(M($FFFF) = $66 And M(0) = $55 And CpuSP = $5566 And CpuHL = $0920 And CpuPC = $921), "SHLD/LHLD wrap, SPHL, PCHL")
  PrintN("API/interrupt/flag checks=" + Str(Checks) + " failures=" + Str(Failures) + " " + StringField("PASS FAIL", 1 + Bool(Failures), " "))
EndProcedure

Procedure.i RunTest(i.i, folder$)
  Protected t.q, cycles.q, ok.i
  If CpmLoad(folder$ + CpmTests(i)\File$) = 0
    PrintN(CpmTests(i)\Name$ + " FAIL: cannot read " + folder$ + CpmTests(i)\File$ + " (run tools/fetch_tests.py)")
    ProcedureReturn 0
  EndIf
  PrintN("*** " + CpmTests(i)\Name$)
  t = ElapsedMilliseconds()
  While CpmFinished = 0 And cycles < CpmTests(i)\RefCycles * 2 + 1000000 And CpuHalted = 0
    cycles + CpuRun(10000000)
  Wend
  t = ElapsedMilliseconds() - t
  Print(CpmOut$)
  PrintN("")
  ok = Bool(CpmFinished And FindString(CpmOut$, CpmTests(i)\Pass$) And FindString(CpmOut$, "ERROR") = 0 And CpuInstr = CpmTests(i)\RefInstr And cycles = CpmTests(i)\RefCycles)
  PrintN(CpmTests(i)\Name$ + " " + StringField("FAIL PASS", 1 + ok, " ") + " instructions=" + Str(CpuInstr) + " (reference " + Str(CpmTests(i)\RefInstr) + ") cycles=" + Str(cycles) +
         " (reference " + Str(CpmTests(i)\RefCycles) + ") ms=" + Str(t) + " instructions/s=" + Str(CpuInstr * 1000 / (t + Bool(t = 0))))
  ProcedureReturn ok
EndProcedure

Procedure Bench(name$, bytes$)
  Protected t.q, i.i
  Poke8080($100, bytes$)
  Start($100)
  t = ElapsedMilliseconds()
  While ElapsedMilliseconds() - t < 1000
    CpuRun(10000000)
  Wend
  t = ElapsedMilliseconds() - t
  PrintN(LSet(name$, 38) + " instructions/s=" + Str(CpuInstr * 1000 / t))
EndProcedure

OpenConsole()
CpmInitTests()
PrintN("8080 desktop core, dispatch=" + StringField("computed-goto procedure-table", 1 + #CPU_DISPATCH, " "))
ApiChecks()
Define folder$ = CpmTestFolder(), passed.i, i.i
For i = 0 To 3
  passed + RunTest(i, folder$)
Next
PrintN("CP/M diagnostics passed " + Str(passed) + " of 4")
For i = $4000 To $40FF : M(i) = (i & 255) ! $A5 : Next
Bench("register/branch DCR/JNZ", "0D C2 00 01 C3 00 01")
Bench("arithmetic ADI/XRI/RLC/RAR/ADD/DAA", "C6 01 EE 55 07 1F 80 27 C3 00 01")
Bench("memory copy MOV/STAX/INX/DCR/JNZ", "21 00 40 11 00 50 0E 00 7E 12 23 13 0D C2 08 01 C3 00 01")
Bench("call/stack CALL/PUSH/POP/RET", "31 00 F0 CD 10 01 C3 03 01 00 00 00 00 00 00 00 C5 E5 E1 C1 C9")
If Failures = 0 And passed = 4
  PrintN("verification complete PASS")
  End 0
EndIf
PrintN("verification complete FAIL")
End 1
