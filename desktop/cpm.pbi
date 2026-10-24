; The machine the desktop program puts around the core: 64 KiB of RAM and the
; CP/M stub the 8080 diagnostics need, laid out as the reference harness does
; (OUT 0 at $0000 ends the program; OUT 1 / RET at $0005 is the BDOS: C = 2
; prints E, C = 9 prints from DE up to '$').
;
; Included by machine.pbi, which owns the core's hooks and calls these.

Global CpmOut$, CpmFinished.i, CpmLoaded$, CpmPortLog.i

; The four diagnostics and their published reference counts
; (github.com/superzazu/8080, the same layout as here).
Structure CpmTest
  Name$
  File$
  Pass$
  RefInstr.q
  RefCycles.q
EndStructure
Global Dim CpmTests.CpmTest(3)
Procedure CpmInitTests()
  CpmTests(0)\Name$ = "TST8080" : CpmTests(0)\File$ = "TST8080.COM" : CpmTests(0)\Pass$ = "CPU IS OPERATIONAL"
  CpmTests(0)\RefInstr = 651 : CpmTests(0)\RefCycles = 4924
  CpmTests(1)\Name$ = "8080PRE" : CpmTests(1)\File$ = "8080PRE.COM" : CpmTests(1)\Pass$ = "8080 Preliminary tests complete"
  CpmTests(1)\RefInstr = 1061 : CpmTests(1)\RefCycles = 7817
  CpmTests(2)\Name$ = "CPUTEST" : CpmTests(2)\File$ = "CPUTEST.COM" : CpmTests(2)\Pass$ = "CPU TESTS OK"
  CpmTests(2)\RefInstr = 33971311 : CpmTests(2)\RefCycles = 255653383
  CpmTests(3)\Name$ = "8080EXM" : CpmTests(3)\File$ = "8080EXM.COM" : CpmTests(3)\Pass$ = "Tests complete"
  CpmTests(3)\RefInstr = 2919050698 : CpmTests(3)\RefCycles = 23803381171
EndProcedure

; Control characters other than line feed are dropped: CPUTEST prints NUL
; and BEL, and a NUL would end a PureBasic string.
Procedure CpmEmit(c.i)
  If c < 32 And c <> 10
    ProcedureReturn
  EndIf
  CpmOut$ + Chr(c)
EndProcedure

Procedure.i CpmPortIn(port.i)
  ProcedureReturn 0
EndProcedure
Procedure CpmPortOut(port.i, value.i)
  Protected adr.i
  If port = 0
    CpmFinished = 1
    CpuYield = 1
  ElseIf port = 1
    If (CpuBC & 255) = 2
      CpmEmit(CpuDE & 255)
    ElseIf (CpuBC & 255) = 9
      adr = CpuDE
      Repeat
        CpmEmit(M(adr))
        adr = (adr + 1) & $FFFF
      Until M(adr) = '$'
    EndIf
  EndIf
EndProcedure

; Loads a .COM file at $0100 with the stubs. Returns its size, 0 on failure.
Procedure.i CpmLoad(file$)
  Protected f.i, size.i, i.i
  For i = 0 To 65535
    M(i) = 0
  Next
  f = ReadFile(#PB_Any, file$)
  If f = 0
    ProcedureReturn 0
  EndIf
  size = Lof(f)
  If size > $FE00
    CloseFile(f)
    ProcedureReturn 0
  EndIf
  ReadData(f, @M($100), size)
  CloseFile(f)
  M(0) = $D3 : M(1) = 0
  M(5) = $D3 : M(6) = 1 : M(7) = $C9
  MachineSelect(#MACHINE_CPM)
  CpuReset()
  CpuPC = $100
  CpmOut$ = "" : CpmFinished = 0 : CpmLoaded$ = file$
  ProcedureReturn size
EndProcedure

; The folder the diagnostics are fetched into (tools/fetch_tests.py).
Procedure.s CpmTestFolder()
  Protected d$ = GetPathPart(ProgramFilename())
  Protected i.i
  For i = 0 To 3
    If FileSize(d$ + "Diagnostics\upstream\TST8080.COM") > 0
      ProcedureReturn d$ + "Diagnostics\upstream\"
    EndIf
    d$ = GetPathPart(Left(d$, Len(d$) - 1))
  Next
  ProcedureReturn GetCurrentDirectory() + "Diagnostics\upstream\"
EndProcedure
