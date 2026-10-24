"""Generate the PureMetal Intel 8080 core for the Pico W (RP2040) and Pico 2 W (RP2350).

One table of opcode semantics, two register layouts and dispatch tails.
The generated files are checked in; edit this generator, then regenerate:

    py -3 tools/generate.py

Writes src/i8080.pico (RP2040) and src/i8080.pico2 (RP2350 Arm).
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# --- register layouts and dispatch tails -----------------------------------

LAYOUT = {
    # RP2040: the layout measured fastest (docs/benchmark-layouts.log): PC and
    # the budget in low registers so the tail and the countdown need no moves.
    'pico': dict(
        reserve='ReserveRegister CpuPC = r4, CpuA = r9, Res = r10, Left = r5, CpuHL = r8, FR = r11',
        table_global='',
        table_init='',
        dispatch='''    ASM Uses CpuPC
      ldr r1, =global_m
      ldrb r2, [r1, r4]
      adds r4, #1
      uxth r4, r4
      lsls r2, r2, #2
      ldr r1, =global_dispatch
      ldr r1, [r1, r2]
      bx r1
    EndASM''',
        charge='''    ASM Uses Left
      subs r5, #{c}
      {br} __ul_cpurun_done
    EndASM''',
    ),
    # The first layout, kept for comparison.
    'pico_first': dict(
        reserve='ReserveRegister CpuPC = r8, CpuA = r9, Res = r10, Left = r11, CpuHL = r4, FR = r5',
        table_global='',
        table_init='',
        dispatch='''    ASM Uses CpuPC
      mov r0, r8
      ldr r1, =global_m
      ldrb r2, [r1, r0]
      adds r0, #1
      lsls r0, r0, #16
      lsrs r0, r0, #16
      mov r8, r0
      lsls r2, r2, #2
      ldr r1, =global_dispatch
      ldr r1, [r1, r2]
      bx r1
    EndASM''',
        charge='''    ASM Uses Left
      mov r0, r11
      subs r0, #{c}
      mov r11, r0
      {br} __ul_cpurun_done
    EndASM''',
    ),
    # Measurement variants for the RP2040 (py -3 tools/generate.py --rp2040 <name>).
    'pico_pclow': dict(
        reserve='ReserveRegister CpuPC = r4, CpuA = r9, Res = r10, Left = r11, CpuHL = r8, FR = r5',
        table_global='',
        table_init='',
        dispatch='''    ASM Uses CpuPC
      ldr r1, =global_m
      ldrb r2, [r1, r4]
      adds r4, #1
      lsls r4, r4, #16
      lsrs r4, r4, #16
      lsls r2, r2, #2
      ldr r1, =global_dispatch
      ldr r1, [r1, r2]
      bx r1
    EndASM''',
        charge='''    ASM Uses Left
      mov r0, r11
      subs r0, #{c}
      mov r11, r0
      {br} __ul_cpurun_done
    EndASM''',
    ),
    'pico_pclow_leftlow': dict(
        reserve='ReserveRegister CpuPC = r4, CpuA = r9, Res = r10, Left = r5, CpuHL = r8, FR = r11',
        table_global='',
        table_init='',
        dispatch='''    ASM Uses CpuPC
      ldr r1, =global_m
      ldrb r2, [r1, r4]
      adds r4, #1
      lsls r4, r4, #16
      lsrs r4, r4, #16
      lsls r2, r2, #2
      ldr r1, =global_dispatch
      ldr r1, [r1, r2]
      bx r1
    EndASM''',
        charge='''    ASM Uses Left
      subs r5, #{c}
      {br} __ul_cpurun_done
    EndASM''',
    ),
    'pico_d': dict(
        reserve='ReserveRegister CpuPC = r4, CpuA = r9, Res = r10, Left = r5, CpuHL = r8, FR = r11',
        table_global='',
        table_init='',
        dispatch='''    ASM Uses CpuPC
      ldr r1, =global_m
      ldrb r2, [r1, r4]
      adds r4, #1
      uxth r4, r4
      lsls r2, r2, #2
      ldr r1, =global_dispatch
      ldr r1, [r1, r2]
      bx r1
    EndASM''',
        charge='''    ASM Uses Left
      subs r5, #{c}
      {br} __ul_cpurun_done
    EndASM''',
    ),
    'pico_e': dict(
        reserve='ReserveRegister CpuPC = r4, CpuA = r6, Res = r10, Left = r5, CpuHL = r8, FR = r11',
        table_global='',
        table_init='',
        dispatch='''    ASM Uses CpuPC
      ldr r1, =global_m
      ldrb r2, [r1, r4]
      adds r4, #1
      uxth r4, r4
      lsls r2, r2, #2
      ldr r1, =global_dispatch
      ldr r1, [r1, r2]
      bx r1
    EndASM''',
        charge='''    ASM Uses Left
      subs r5, #{c}
      {br} __ul_cpurun_done
    EndASM''',
    ),
    'pico_f': dict(
        reserve='ReserveRegister CpuPC = r4, CpuA = r9, Res = r6, Left = r5, CpuHL = r8, FR = r11',
        table_global='',
        table_init='',
        dispatch='''    ASM Uses CpuPC
      ldr r1, =global_m
      ldrb r2, [r1, r4]
      adds r4, #1
      uxth r4, r4
      lsls r2, r2, #2
      ldr r1, =global_dispatch
      ldr r1, [r1, r2]
      bx r1
    EndASM''',
        charge='''    ASM Uses Left
      subs r5, #{c}
      {br} __ul_cpurun_done
    EndASM''',
    ),
    'pico2': dict(
        reserve='ReserveRegister CpuPC = r4, CpuA = r9, Res = r10, Left = r11, CpuHL = r8, FR = r5, TableBase = r6',
        table_global='Global TableBase.i\n',
        table_init='    TableBase = @Dispatch(0)\n',
        dispatch='''    ASM Uses CpuPC, TableBase
      ldr r1, =global_m
      ldrb r2, [r1, r4]
      adds r4, #1
      uxth r4, r4
      lsls r2, r2, #2
      ldr r1, [r6, r2]
      bx r1
    EndASM''',
        charge='''    ASM Uses Left
      subs.w r11, r11, #{c}
      {br} __ul_cpurun_done
    EndASM''',
    ),
}

# --- 8080 cycle counts (Intel 8080 data sheet; Ccc and Rcc add 6 when taken) --

def cycles(op):
    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    p = y >> 1
    if x == 1:
        if op == 0x76:
            return 7
        return 7 if (y == 6 or z == 6) else 5
    if x == 2:
        return 7 if z == 6 else 4
    if x == 0:
        return [4, 10, [7, 7, 7, 7, 16, 16, 13, 13][y], 5,
                10 if y == 6 else 5, 10 if y == 6 else 5, 10 if y == 6 else 7, 4][z]
    return [5,                                         # Rcc (+6 taken)
            10 if y & 1 == 0 else [10, 10, 5, 5][p],   # POP / RET RET* PCHL SPHL
            10,                                        # Jcc
            [10, 10, 10, 10, 18, 4, 4, 4][y],          # JMP JMP* OUT IN XTHL XCHG DI EI
            11,                                        # Ccc (+6 taken)
            11 if y & 1 == 0 else 17,                  # PUSH / CALL CALL*
            7,                                         # ALU immediate
            11][z]                                     # RST

CYC = [cycles(op) for op in range(256)]

# Spot checks against the data sheet, so a slip in the table above is loud.
for op, c in {0x00: 4, 0x01: 10, 0x02: 7, 0x03: 5, 0x04: 5, 0x06: 7, 0x07: 4, 0x09: 10,
              0x0A: 7, 0x22: 16, 0x2A: 16, 0x32: 13, 0x3A: 13, 0x34: 10, 0x35: 10, 0x36: 10,
              0x40: 5, 0x46: 7, 0x70: 7, 0x76: 7, 0x80: 4, 0x86: 7, 0xC0: 5, 0xC1: 10,
              0xC2: 10, 0xC3: 10, 0xC4: 11, 0xC5: 11, 0xC6: 7, 0xC7: 11, 0xC9: 10, 0xCB: 10,
              0xCD: 17, 0xD3: 10, 0xD9: 10, 0xDB: 10, 0xDD: 17, 0xE3: 18, 0xE9: 5, 0xEB: 4,
              0xED: 17, 0xF1: 10, 0xF3: 4, 0xF5: 11, 0xF9: 5, 0xFB: 4, 0xFD: 17, 0xFE: 7}.items():
    assert CYC[op] == c, (hex(op), CYC[op], c)

# --- operand spelling -------------------------------------------------------

REG = 'BCDEHLMA'
PAIR = ['CpuBC', 'CpuDE', 'CpuHL', 'CpuSP']
PNAME = ['B', 'D', 'H', 'SP']

def get8(r):
    return {'B': '(CpuBC >> 8)', 'C': '(CpuBC & 255)', 'D': '(CpuDE >> 8)', 'E': '(CpuDE & 255)',
            'H': '(CpuHL >> 8)', 'L': '(CpuHL & 255)', 'M': 'Rd(CpuHL)', 'A': 'CpuA'}[r]

def set8(r, e):
    return {'B': f'CpuBC = (CpuBC & 255) | ({e} << 8)', 'C': f'CpuBC = (CpuBC & $FF00) | {e}',
            'D': f'CpuDE = (CpuDE & 255) | ({e} << 8)', 'E': f'CpuDE = (CpuDE & $FF00) | {e}',
            'H': f'CpuHL = (CpuHL & 255) | ({e} << 8)', 'L': f'CpuHL = (CpuHL & $FF00) | {e}',
            'M': f'Wr(CpuHL, {e})', 'A': f'CpuA = {e}'}[r]

COND = ['(FR & 255) <> 0', '(FR & 255) = 0', '(FC & $100) = 0', '(FC & $100) <> 0',
        'Parity((FR ! (FR >> 8)) & 255) = 0', 'Parity((FR ! (FR >> 8)) & 255) <> 0',
        '(FR & $8080) = 0', '(FR & $8080) <> 0']
CNAME = ['NZ', 'Z', 'NC', 'C', 'PO', 'PE', 'P', 'M']
HI16 = 'Res = M((CpuPC + 1) & $FFFF) << 8'
FETCH16 = 'Res | M(CpuPC)'
STEP2 = 'CpuPC = (CpuPC + 2) & $FFFF'
STEP1 = 'CpuPC = (CpuPC + 1) & $FFFF'

def alu(k, v):
    """ALU operation k (ADD ADC SUB SBB ANA XRA ORA CMP) on the 8-bit operand v.

    The operand is read once, into the scratch register Res (so a memory
    operand's trap fires once). AC is bit 4 of (FA ! FR): FA holds
    A ! operand, inverted for the subtractions."""
    out = [f'Res = {v}']
    if k in (5, 6):
        op = '!' if k == 5 else '|'
        return out + [f'CpuA = CpuA {op} Res', 'FR = CpuA', 'FC = 0', 'FA = CpuA']
    if k == 4:
        # 8080 ANA/ANI: AC is the OR of bit 3 of the two operands.
        return out + ['FA = ((CpuA | Res) << 1) ! (CpuA & Res)', 'CpuA = CpuA & Res', 'FR = CpuA', 'FC = 0']
    out.append('FA = CpuA ! Res' + (' ! $10' if k >= 2 else ''))
    out.append({0: 'Res = CpuA + Res', 1: 'Res = CpuA + Res + ((FC >> 8) & 1)',
                2: 'Res = CpuA - Res', 3: 'Res = CpuA - Res - ((FC >> 8) & 1)',
                7: 'Res = CpuA - Res'}[k])
    out.append('FC = Res')
    if k == 7:
        out.append('FR = Res & 255')
    else:
        out += ['CpuA = Res & 255', 'FR = CpuA']
    return out

ALU = ['ADD', 'ADC', 'SUB', 'SBB', 'ANA', 'XRA', 'ORA', 'CMP']
ALUI = ['ADI', 'ACI', 'SUI', 'SBI', 'ANI', 'XRI', 'ORI', 'CPI']

def body(op):
    """Return (mnemonic, lines, tail) where tail is 'next', 'ei', 'hlt' or 'io'."""
    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    p = y >> 1
    if x == 1:
        if op == 0x76:
            return 'HLT', [], 'hlt'
        d, s = REG[y], REG[z]
        same = {('B', 'C'): 'CpuBC', ('C', 'B'): 'CpuBC', ('D', 'E'): 'CpuDE', ('E', 'D'): 'CpuDE',
                ('H', 'L'): 'CpuHL', ('L', 'H'): 'CpuHL'}.get((d, s))
        if same:
            if d in 'BDH':
                return f'MOV {d},{s}', ['Res = ' + same, f'{same} = (Res & 255) | ((Res & 255) << 8)'], 'next'
            return f'MOV {d},{s}', ['Res = ' + same, f'{same} = (Res & $FF00) | (Res >> 8)'], 'next'
        return f'MOV {d},{s}', [set8(d, get8(s))], 'next'
    if x == 2:
        return f'{ALU[y]} {REG[z]}', alu(y, get8(REG[z])), 'next'
    if x == 0:
        if z == 0:
            return ('NOP' if y == 0 else 'NOP (undocumented)'), [], 'next'
        if z == 1:
            if y & 1 == 0:
                return f'LXI {PNAME[p]}', [HI16, f'{PAIR[p]} = {FETCH16}', STEP2], 'next'
            return f'DAD {PNAME[p]}', [f'Res = CpuHL + {PAIR[p]}', 'FC = Res >> 8', 'CpuHL = Res & $FFFF'], 'next'
        if z == 2:
            return [
                ('STAX B', ['Wr(CpuBC, CpuA)']), ('LDAX B', ['CpuA = Rd(CpuBC)']),
                ('STAX D', ['Wr(CpuDE, CpuA)']), ('LDAX D', ['CpuA = Rd(CpuDE)']),
                ('SHLD', [HI16, 'Ea = ' + FETCH16, STEP2, 'Wr(Ea, CpuHL & 255)', 'Wr((Ea + 1) & $FFFF, CpuHL >> 8)']),
                ('LHLD', [HI16, 'Ea = ' + FETCH16, STEP2, 'CpuHL = Rd(Ea) | (Rd((Ea + 1) & $FFFF) << 8)']),
                ('STA', [HI16, 'Wr(' + FETCH16 + ', CpuA)', STEP2]),
                ('LDA', [HI16, 'CpuA = Rd(' + FETCH16 + ')', STEP2]),
            ][y] + ('next',)
        if z == 3:
            sign = '+' if y & 1 == 0 else '-'
            return f'{"INX" if sign == "+" else "DCX"} {PNAME[p]}', [f'{PAIR[p]} = ({PAIR[p]} {sign} 1) & $FFFF'], 'next'
        if z in (4, 5):
            r = REG[y]
            inc = z == 4
            name = ('INR ' if inc else 'DCR ') + r
            sign, inv = ('+', '') if inc else ('-', ' ! $10')
            if r in 'BDH' or r in 'CEL':
                # The whole pair is read once into Res and written once.
                pair = {'B': 'CpuBC', 'C': 'CpuBC', 'D': 'CpuDE', 'E': 'CpuDE', 'H': 'CpuHL', 'L': 'CpuHL'}[r]
                if r in 'CEL':
                    lines = [f'Res = {pair}', f'FA = Res{inv}', f'FR = (Res {sign} 1) & 255',
                             f'{pair} = (Res & $FF00) | FR']
                else:
                    lines = [f'Res = {pair}', f'FA = (Res >> 8){inv}', f'FR = ((Res >> 8) {sign} 1) & 255',
                             f'{pair} = (Res & 255) | (FR << 8)']
            else:
                lines = ['Res = ' + get8(r), f'FA = Res{inv}', f'FR = (Res {sign} 1) & 255', set8(r, 'FR')]
            return name, lines, 'next'
        if z == 6:
            r = REG[y]
            return f'MVI {r}', [set8(r, 'M(CpuPC)'), STEP1], 'next'
        return [
            ('RLC', ['FC = CpuA << 1', 'CpuA = ((CpuA << 1) | (CpuA >> 7)) & 255']),
            ('RRC', ['FC = CpuA << 8', 'CpuA = (CpuA >> 1) | ((CpuA & 1) << 7)']),
            ('RAL', ['Res = (CpuA << 1) | ((FC >> 8) & 1)', 'FC = Res', 'CpuA = Res & 255']),
            ('RAR', ['Res = (CpuA >> 1) | ((FC >> 1) & $80)', 'FC = CpuA << 8', 'CpuA = Res']),
            ('DAA', ['Value = 0', 'Tmp = (FC >> 8) & 1',
                     'If ((FA ! FR) & $10) <> 0', '  Value = 6', 'ElseIf (CpuA & 15) > 9', '  Value = 6', 'EndIf',
                     'If CpuA > $99', '  Tmp = 1', 'EndIf',
                     'If Tmp', '  Value = Value | $60', 'EndIf',
                     'FA = CpuA ! Value', 'Res = CpuA + Value', 'CpuA = Res & 255', 'FR = CpuA',
                     'FC = Tmp << 8']),
            ('CMA', ['CpuA = CpuA ! 255']),
            ('STC', ['FC = $100']),
            ('CMC', ['FC = FC ! $100']),
        ][y] + ('next',)
    # x == 3
    if z == 0:
        return f'R{CNAME[y]}', [f'If {COND[y]}', '  Pop16(CpuPC)', '  Charge(6)', 'EndIf'], 'next'
    if z == 1:
        if y & 1 == 0:
            if p == 3:
                return 'POP PSW', ['Pop16(Tmp)', 'CpuA = Tmp >> 8', 'SetFlags(Tmp & 255)'], 'next'
            return f'POP {PNAME[p]}', [f'Pop16({PAIR[p]})'], 'next'
        return [('RET', ['Pop16(CpuPC)']), ('RET (undocumented)', ['Pop16(CpuPC)']),
                ('PCHL', ['CpuPC = CpuHL']), ('SPHL', ['CpuSP = CpuHL'])][p] + ('next',)
    if z == 2:
        return f'J{CNAME[y]}', [f'If {COND[y]}', f'  {HI16}', f'  CpuPC = {FETCH16}', 'Else', f'  {STEP2}', 'EndIf'], 'next'
    if z == 3:
        if y == 0: return 'JMP', [HI16, f'CpuPC = {FETCH16}'], 'next'
        if y == 1: return 'JMP (undocumented)', [HI16, f'CpuPC = {FETCH16}'], 'next'
        if y == 2: return 'OUT', ['Tmp = M(CpuPC)', STEP1, 'CpuPortOut(Tmp, CpuA)'], 'io'
        if y == 3: return 'IN', ['Tmp = M(CpuPC)', STEP1, 'CpuA = CpuPortIn(Tmp) & 255'], 'io'
        if y == 4: return 'XTHL', ['Tmp = Rd(CpuSP) | (Rd((CpuSP + 1) & $FFFF) << 8)',
                                   'Wr(CpuSP, CpuHL & 255)', 'Wr((CpuSP + 1) & $FFFF, CpuHL >> 8)', 'CpuHL = Tmp'], 'next'
        if y == 5: return 'XCHG', ['Tmp = CpuHL', 'CpuHL = CpuDE', 'CpuDE = Tmp'], 'next'
        if y == 6: return 'DI', ['CpuIE = 0'], 'next'
        return 'EI', ['CpuIE = 1'], 'ei'
    if z == 4:
        return f'C{CNAME[y]}', [f'If {COND[y]}', f'  {HI16}', f'  Ea = {FETCH16}', f'  {STEP2}', '  Push16(CpuPC)',
                                '  CpuPC = Ea', '  Charge(6)', 'Else', f'  {STEP2}', 'EndIf'], 'next'
    if z == 5:
        if y & 1 == 0:
            if p == 3:
                return 'PUSH PSW', ['PackFlags(Tmp)', 'Tmp = Tmp | (CpuA << 8)', 'Push16(Tmp)'], 'next'
            return f'PUSH {PNAME[p]}', [f'Push16({PAIR[p]})'], 'next'
        name = 'CALL' if y == 1 else 'CALL (undocumented)'
        return name, [HI16, f'Ea = {FETCH16}', STEP2, 'Push16(CpuPC)', 'CpuPC = Ea'], 'next'
    if z == 6:
        return ALUI[y], alu(y, 'M(CpuPC)') + [STEP1], 'next'
    return f'RST {y}', ['Push16(CpuPC)', f'CpuPC = ${y * 8:02X}'], 'next'


HEADER = '''; Generated by tools/generate.py. Edit the generator, then regenerate.
; Intel 8080, all 256 opcodes (the twelve undocumented ones behave as the
; NOP, JMP, RET and CALL they duplicate). One global CPU instance.
;
; Configuration, declared by the program before it includes this file:
;   #CPU_TIMING   1 = CpuRun's budget is in 8080 clock cycles (data-sheet
;                     counts, Ccc/Rcc +6 when taken); 0 = in instructions.
;   #CPU_ASM_TAIL 1 = assembly computed-jump tail; 0 = PureMetal Goto tail.
;   #CPU_MEMMAP   1 = data reads and writes go through the page map CpuMemMap
;                     (bit 0 = read M directly, bit 1 = write M directly;
;                     otherwise CpuReadTrap / CpuWriteTrap are called).
;                     Opcode and immediate fetches always read M.
; The program supplies CpuPortIn(port) and CpuPortOut(port, value), and with
; #CPU_MEMMAP = 1 also CpuReadTrap(address) and CpuWriteTrap(address, value).
; A port or trap procedure may set CpuYield = 1 to end the run window after
; the current instruction.
;
; Flags are lazy. FR holds the last result byte: S is (FR & $8080), Z is
; (FR & 255) = 0, P is the parity of (FR ! (FR >> 8)) & 255; the high byte is
; used only by SetFlags so that any PSW, even S and Z together, survives.
; CY is bit 8 of FC; AC is bit 4 of (FA ! FR). CpuFlags() / CpuSetFlags() pack them.
EnableExplicit
Global Dim M.a(65536)
Global Dim Dispatch.Label(256)
Global Dim Parity.a(256)
Global Dim CpuMemMap.a(256)
Global CpuPC.i, CpuA.i, CpuBC.i, CpuDE.i, CpuHL.i, CpuSP.i
Global FR.i, FC.i, FA.i
Global CpuIE.i, CpuHalted.i, CpuEiDelay.i, CpuYield.i
Global Res.i, Left.i, Budget.i, Ready.i, ParityReady.i
Global Ea.i, Value.i, Tmp.i, InitIndex.i, MemAdr.i, MemVal.i
{table_global}{reserve}

CompilerIf #CPU_MEMMAP = 1
Macro Rd(adr)
  CpuRead(adr)
EndMacro
Macro Wr(adr, v)
  CpuWrite(adr, v)
EndMacro
ProcedureRAM.i CpuRead(adr.i)
  If CpuMemMap(adr >> 8) & 1
    ProcedureReturn M(adr)
  EndIf
  ProcedureReturn CpuReadTrap(adr) & 255
EndProcedure
ProcedureRAM CpuWrite(adr.i, v.i)
  If CpuMemMap(adr >> 8) & 2
    M(adr) = v
  Else
    CpuWriteTrap(adr, v)
  EndIf
EndProcedure
CompilerElse
Macro Rd(adr)
  M(adr)
EndMacro
Macro Wr(adr, v)
  M(adr) = v
EndMacro
CompilerEndIf

; Res is the core's scratch register: the stack address and the 16-bit
; operand are built in it rather than in an expression that spills.
Macro Push16(v)
  Res = (CpuSP - 2) & $FFFF
  CpuSP = Res
  Wr((Res + 1) & $FFFF, (v) >> 8)
  Wr(Res, (v) & 255)
EndMacro
Macro Pop16(v)
  Res = Rd((CpuSP + 1) & $FFFF) << 8
  v = Res | Rd(CpuSP)
  CpuSP = (CpuSP + 2) & $FFFF
EndMacro
Macro Charge(c)
  CompilerIf #CPU_TIMING = 1
    Left = Left - c
  CompilerEndIf
EndMacro
; PSW low byte: S Z 0 AC 0 P 1 CY.
Macro PackFlags(v)
  v = 2 | ((FA ! FR) & $10) | ((FC >> 8) & 1) | Parity((FR ! (FR >> 8)) & 255)
  If FR & $8080
    v = v | $80
  EndIf
  If (FR & 255) = 0
    v = v | $40
  EndIf
EndMacro
Macro SetFlags(p)
  MemVal = p
  FC = (MemVal & 1) << 8
  If MemVal & $40
    FR = (MemVal & $80) << 8
  Else
    FR = (MemVal & $80) | 1
  EndIf
  If Parity((FR ! (FR >> 8)) & 255) <> (MemVal & 4)
    FR = FR | $100
  EndIf
  FA = (MemVal & $10) ! FR
EndMacro

Procedure CpuInitTables()
  Protected i.i, b.i, n.i
  For i = 0 To 255
    n = 0
    For b = 0 To 7
      n = n + ((i >> b) & 1)
    Next
    If n & 1
      Parity(i) = 0
    Else
      Parity(i) = 4
    EndIf
  Next
  ParityReady = 1
EndProcedure
Procedure.i CpuFlags()
  Protected v.i
  PackFlags(v)
  ProcedureReturn v
EndProcedure
Procedure CpuSetFlags(p.i)
  SetFlags(p)
EndProcedure
; Deterministic start: PC = 0, interrupts off, registers 0, PSW flags = $02.
Procedure CpuReset()
  If ParityReady = 0
    CpuInitTables()
  EndIf
  CpuPC = 0 : CpuA = 0 : CpuBC = 0 : CpuDE = 0 : CpuHL = 0 : CpuSP = 0
  CpuSetFlags(2)
  CpuIE = 0 : CpuHalted = 0 : CpuEiDelay = 0 : CpuYield = 0
EndProcedure
; Delivers an interrupt between run windows: the device places RST n
; ($C7, $CF ... $FF) on the bus. Refused (returns 0) while interrupts are
; disabled, in the one instruction after EI, or for an opcode that is not
; an RST. Accepted: wakes HLT, disables interrupts, pushes PC, jumps to
; n * 8 and returns the 11 cycles the RST takes.
Procedure.i CpuInterrupt(opcode.i)
  If opcode < 0 Or opcode > 255
    ProcedureReturn 0
  EndIf
  If (opcode & $C7) <> $C7
    ProcedureReturn 0
  EndIf
  If CpuIE = 0 Or CpuEiDelay <> 0
    ProcedureReturn 0
  EndIf
  CpuIE = 0
  CpuHalted = 0
  Push16(CpuPC)
  CpuPC = opcode & $38
  ProcedureReturn 11
EndProcedure

; Runs whole instructions until the budget is spent: n instructions, or with
; #CPU_TIMING = 1 at least n cycles. Returns what was consumed (the timed
; budget may be overshot by part of one instruction). Ends early after HLT
; (timed: the rest of the window, at least HLT's 7 cycles, is spent
; halted) and when a hook sets
; CpuYield. A halted CPU consumes no instructions, or the whole window of
; cycles, until CpuInterrupt wakes it.
ProcedureRAM.i CpuRun(n.i)
Macro DispatchNext()
  CompilerIf #CPU_ASM_TAIL = 1
{dispatch}
  CompilerElse
    Tmp = M(CpuPC)
    CpuPC = (CpuPC + 1) & $FFFF
    Goto Dispatch(Tmp)
  CompilerEndIf
EndMacro
; The run ends after this instruction when the budget is spent or a hook asked.
Macro NextOpChecked(c)
  CompilerIf #CPU_TIMING = 1
    Left = Left - c
  CompilerElse
    Left = Left - 1
  CompilerEndIf
  If Left <= 0
    Goto Done
  EndIf
  If CpuYield
    Goto Done
  EndIf
  DispatchNext()
EndMacro
  If n <= 0
    ProcedureReturn 0
  EndIf
  If CpuHalted
    CompilerIf #CPU_TIMING = 1
      ProcedureReturn n
    CompilerElse
      ProcedureReturn 0
    CompilerEndIf
  EndIf
  If Ready = 0
{table_init}'''

def generate(target):
    L = LAYOUT[target]
    out = []
    head = HEADER.format(
        table_global=L['table_global'], reserve=L['reserve'], dispatch=L['dispatch'],
        table_init=L['table_init'])
    lines = head.splitlines()
    at = lines.index('  If n <= 0')
    lines[at:at] = tail_macros(L)
    out.extend(lines)
    for op in range(256):
        out.append(f'    Dispatch(${op:02X}) = ?Op{op:02X}')
    out += ['    Ready = 1', '  EndIf',
            '  CpuEiDelay = 0', '  CpuYield = 0',
            '  Budget = n', '  Left = n', '  DispatchNext()']
    for op in range(256):
        name, lines, tail = body(op)
        c = CYC[op]
        out.append(f'Op{op:02X}: ; ${op:02X} {name}, {c} cycles')
        out += ['  ' + s for s in lines]
        if tail == 'next':
            out += ['  ' + s for s in next_op(L, c)]
        elif tail == 'io':
            out.append(f'  NextOpChecked({c})')
        elif tail == 'ei':
            # The instruction after EI runs before an interrupt is accepted:
            # if EI ends the window, CpuInterrupt refuses until the next run.
            out += ['  CompilerIf #CPU_TIMING = 1', f'    Left = Left - {c}', '  CompilerElse',
                    '    Left = Left - 1', '  CompilerEndIf', '  If Left <= 0', '    CpuEiDelay = 1',
                    '    Goto Done', '  EndIf', '  DispatchNext()']
        elif tail == 'hlt':
            out += ['  CpuHalted = 1', '  CompilerIf #CPU_TIMING = 1', f'    Left = Left - {c}',
                    '    If Left > 0', '      Left = 0', '    EndIf', '  CompilerElse',
                    '    Left = Left - 1', '  CompilerEndIf', '  Goto Done']
        out.append('')
    out += ['Done:', '  ProcedureReturn Budget - Left', 'EndProcedure', '']
    text = '\n'.join(out) + '\n'
    assert '{' not in text, 'unformatted template field'
    return text


def next_op(L, c):
    return [f'NextOp{c}()']


def tail_macros(L):
    """One tail macro per distinct cycle count: charge the budget, end the
    window when it is spent, else dispatch the next opcode."""
    out = []
    for c in sorted(set(CYC)):
        timed = L['charge'].format(c=c, br='ble')
        untimed = L['charge'].format(c=1, br='beq')
        out += [f'Macro NextOp{c}()', '  CompilerIf #CPU_ASM_TAIL = 1', '    CompilerIf #CPU_TIMING = 1']
        out += ['  ' + t for t in timed.splitlines()]
        out += ['    CompilerElse']
        out += ['  ' + t for t in untimed.splitlines()]
        out += ['    CompilerEndIf', '  CompilerElse', '    CompilerIf #CPU_TIMING = 1',
                f'      Left = Left - {c}', '      If Left <= 0', '        Goto Done', '      EndIf',
                '    CompilerElse', '      Left = Left - 1', '      If Left = 0', '        Goto Done',
                '      EndIf', '    CompilerEndIf', '  CompilerEndIf', '  DispatchNext()', 'EndMacro']
    return out


if __name__ == '__main__':
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--rp2040', default='pico', choices=[k for k in LAYOUT if k.startswith('pico') and k != 'pico2'])
    args = ap.parse_args()
    for target, name in ((args.rp2040, 'i8080.pico'), ('pico2', 'i8080.pico2')):
        text = generate(target)
        (ROOT / 'src' / name).write_text(text, encoding='utf-8')
        print(f'{name}: {text.count(chr(10))} lines')


def port_programs():
    """Derive the Pico 2 W programs from the Pico W ones (library paths, clock)."""
    def port(text):
        text = text.replace('RP2040/', 'RP2350/').replace('Pico W', 'Pico 2 W')
        text = text.replace('#CLOCK_KHZ = 200000', '#CLOCK_KHZ = 150000')
        for lib in ('clocks', 'timer', 'uart', 'usb_serial', 'safety'):
            text = text.replace(f'Lib/{lib}.pico"', f'Lib/{lib}.pico2"')
        for name in ('i8080', 'io', 'test_data', 'verify_body'):
            text = text.replace(f'{name}.pico"', f'{name}.pico2"')
        return text
    banner = '; Generated by tools/generate.py from the Pico W file of the same name.\n'
    (ROOT / 'src/io.pico2').write_text(banner + (ROOT / 'src/io.pico').read_text())
    (ROOT / 'src/demo.pico2w').write_text(banner + port((ROOT / 'src/demo.picow').read_text()))
    diag = ROOT / 'Diagnostics'
    (diag / 'verify_body.pico2').write_text(banner + port((diag / 'verify_body.pico').read_text()))
    for name in ('verify-fast', 'verify-timed', 'verify-pure'):
        (diag / f'{name}.pico2w').write_text(banner + port((diag / f'{name}.picow').read_text()))
    print('Pico 2 W programs derived')


if __name__ == '__main__':
    port_programs()
