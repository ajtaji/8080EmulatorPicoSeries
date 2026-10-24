; The machines the desktop program puts around the core, and the core's
; hooks, which hand each port or trapped access to the selected machine:
;   #MACHINE_CPM       64 KiB of RAM and the CP/M stub the diagnostics need
;   #MACHINE_INVADERS  Space Invaders (Taito 8080) hardware, invaders.pbi
; Include this file, not the core: PureBasic needs the hooks declared first.

CompilerIf Defined(CPU_DISPATCH, #PB_Constant) = 0
  #CPU_DISPATCH = 0
CompilerEndIf
#CPU_MEMMAP = 1

Declare.i CpuPortIn(port.i)
Declare CpuPortOut(port.i, value.i)
Declare.i CpuReadTrap(adr.i)
Declare CpuWriteTrap(adr.i, value.i)
XIncludeFile "i8080core.pbi"

Enumeration
  #MACHINE_CPM
  #MACHINE_INVADERS
EndEnumeration
Global Machine.i = #MACHINE_CPM

; Every page plain RAM, as CP/M has it. invaders.pbi sets its own map.
Procedure MachineSelect(which.i)
  Protected i.i
  Machine = which
  If which = #MACHINE_CPM
    For i = 0 To 255 : CpuMemMap(i) = 3 : Next
  EndIf
EndProcedure

XIncludeFile "cpm.pbi"
XIncludeFile "invaders.pbi"

Procedure.i CpuPortIn(port.i)
  If Machine = #MACHINE_INVADERS
    ProcedureReturn InvPortIn(port)
  EndIf
  ProcedureReturn CpmPortIn(port)
EndProcedure
Procedure CpuPortOut(port.i, value.i)
  If Machine = #MACHINE_INVADERS
    InvPortOut(port, value)
  Else
    CpmPortOut(port, value)
  EndIf
EndProcedure
Procedure.i CpuReadTrap(adr.i)
  ProcedureReturn InvReadTrap(adr)
EndProcedure
Procedure CpuWriteTrap(adr.i, value.i)
  InvWriteTrap(adr, value)
EndProcedure
