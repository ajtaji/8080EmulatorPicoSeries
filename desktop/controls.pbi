; The controls: every key the window answers to, in ONE table. The cabinet's
; inputs (MachineInputs), the window's shortcuts, the Controls tab and the key
; list beside the screen all read it, so what the window shows is what the
; input code does. Include after machine.pbi (the #INV_* bits) and the engine
; (GL_KeyHeld, its HOST SERVICES).
;
; There is no gamepad input: the keyboard only.

; The window's own shortcuts (rows with bit 0; action = the code).
#CTL_FULLSCREEN = 1
#CTL_LEAVEFULL  = 2

Structure CtlBinding
  bit.i         ; the cabinet input's bit in IN 1 (#INV_*), 0 for a window shortcut
  action.i      ; for a shortcut: #CTL_*
  key.i         ; the key, a #PB_Shortcut_* code (the engine's GL_KeyHeld reads it on Windows and Linux)
  key$          ; the key as the window shows it
  what$         ; what it does
EndStructure
Global NewList CtlKeys.CtlBinding()

Procedure CtlInit()
  Protected b.i, a.i, k.i, n$, w$
  ClearList(CtlKeys())
  Restore CtlKeyTable
  Repeat
    Read.i b : Read.i a : If b < 0 : Break : EndIf
    Read.i k : Read.s n$ : Read.s w$
    AddElement(CtlKeys()) : CtlKeys()\bit = b : CtlKeys()\action = a : CtlKeys()\key = k : CtlKeys()\key$ = n$ : CtlKeys()\what$ = w$
  ForEver
EndProcedure

; The cabinet inputs the keyboard holds now (IN 1's bits).
Procedure.i CtlInputsHeld()
  Protected m.i
  ForEach CtlKeys()
    If CtlKeys()\bit And GL_KeyHeld(CtlKeys()\key)
      m | CtlKeys()\bit
    EndIf
  Next
  ProcedureReturn m
EndProcedure

; The window action a key starts (0: none).
Procedure.i CtlAction(key.i)
  ForEach CtlKeys()
    If CtlKeys()\bit = 0 And CtlKeys()\key = key : ProcedureReturn CtlKeys()\action : EndIf
  Next
  ProcedureReturn 0
EndProcedure

; The key(s) for a window action, as shown ("F11").
Procedure.s CtlActionKeys(action.i)
  Protected t$
  ForEach CtlKeys()
    If CtlKeys()\bit = 0 And CtlKeys()\action = action
      If t$ <> "" : t$ + " / " : EndIf
      t$ + CtlKeys()\key$
    EndIf
  Next
  ProcedureReturn t$
EndProcedure

; The bit's number in IN 1 (for the Controls tab).
Procedure.i CtlBitNumber(bit.i)
  Protected n.i
  While bit > 1 : bit >> 1 : n + 1 : Wend
  ProcedureReturn n
EndProcedure

DataSection
  CtlKeyTable:
  ; bit, action, key, key as shown, what it does - the cabinet's controls first, then the window's shortcuts
  Data.i #INV_P1LEFT, 0, #PB_Shortcut_Left  : Data.s "Left arrow", "move left"
  Data.i #INV_P1RIGHT, 0, #PB_Shortcut_Right : Data.s "Right arrow", "move right"
  Data.i #INV_P1FIRE, 0, #PB_Shortcut_Space : Data.s "Space", "fire"
  Data.i #INV_COIN, 0, #PB_Shortcut_C : Data.s "C", "insert a coin"
  Data.i #INV_P1START, 0, #PB_Shortcut_1 : Data.s "1", "1-player start"
  Data.i #INV_P2START, 0, #PB_Shortcut_2 : Data.s "2", "2-player start"
  Data.i 0, #CTL_FULLSCREEN, #PB_Shortcut_F11 : Data.s "F11", "full screen on / off"
  Data.i 0, #CTL_LEAVEFULL, #PB_Shortcut_Escape : Data.s "Esc", "leave full screen"
  Data.i -1, -1
EndDataSection
