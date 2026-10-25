"""Thumb-2 (Cortex-M33) bodies for the hot 8080 handlers, RP2350 builds only.

generate.py puts each of these in place of the handler's PureMetal body when
the assembly tail is on (#CPU_ASM_TAIL = 1) and, for a handler that touches
guest memory, the page map is off (#CPU_MEMMAP = 0); every other build keeps
the PureMetal body. The semantics are the PureMetal ones exactly (the same
lazy flags: FR the result byte, FC with carry in bit 8, FA with AC in bit 4 of
FA ^ FR), so the same diagnostics prove both.

Registers (the RP2350 layout): PC r4, A r9, HL r8, FR r5, Left r11, the
dispatch table r6. BC, DE, SP, FC and FA are Globals. Scratch: r0-r3 only (r12 belongs to the
compiler's call veneers).
"""

REG = 'BCDEHLMA'
PAIRS = {'B': 'global_cpubc', 'C': 'global_cpubc', 'D': 'global_cpude', 'E': 'global_cpude'}
PAIR_NAME = ['global_cpubc', 'global_cpude', None, 'global_cpusp']   # HL lives in r8
RESERVED = [('r4', 'CpuPC'), ('r9', 'CpuA'), ('r8', 'CpuHL'), ('r5', 'FR'), ('r11', 'Left')]


def uses(lines):
    """The ASM Uses line naming exactly the reserved registers the block touches (the
    compiler refuses a name the block does not use)."""
    import re
    text = ' '.join(lines)
    names = [n for r, n in RESERVED if re.search(r'\b' + r + r'\b', text)]
    return 'ASM Uses ' + ', '.join(names) if names else 'ASM'


def get8(r, dst='r2'):
    """The 8-bit register r into dst. Leaves a pair's address in r0 and its value in r1."""
    if r in PAIRS:
        hi = r in 'BD'
        return [f'ldr r0, ={PAIRS[r]}', 'ldr r1, [r0]',
                f'ubfx {dst}, r1, #8, #8' if hi else f'uxtb {dst}, r1']
    if r == 'H':
        return [f'ubfx {dst}, r8, #8, #8']
    if r == 'L':
        return [f'uxtb {dst}, r8']
    if r == 'A':
        return [f'mov {dst}, r9']
    return ['ldr r3, =global_m', f'ldrb {dst}, [r3, r8]']                 # M


def set8(r, src='r2', loaded=None):
    """src (a byte) into register r. `loaded`: the pair whose address/value r0/r1 already hold."""
    if r in PAIRS:
        out = [] if loaded == PAIRS[r] else [f'ldr r0, ={PAIRS[r]}', 'ldr r1, [r0]']
        hi = r in 'BD'
        return out + [f'bfi r1, {src}, #{8 if hi else 0}, #8', 'str r1, [r0]']
    if r == 'H':
        return [f'bfi r8, {src}, #8, #8']
    if r == 'L':
        return [f'bfi r8, {src}, #0, #8']
    if r == 'A':
        return [f'mov r9, {src}']
    return ['ldr r3, =global_m', f'strb {src}, [r3, r8]']                 # M


FETCH8 = ['ldr r3, =global_m', 'ldrb r2, [r3, r4]', 'adds r4, #1', 'uxth r4, r4']


def fetch16(op, dst='r1', step=True):
    """The 16-bit operand at PC into dst (an unaligned ldrh; PC = $FFFF wraps
    to $0000 for the high byte, so that case takes the byte path)."""
    return ['ldr r3, =global_m', 'add r0, r4, #1', 'tst r0, #0x10000', f'bne t2_{op:02x}_w',
            f'ldrh {dst}, [r3, r4]', f'b t2_{op:02x}_f',
            f't2_{op:02x}_w:', f'ldrb {dst}, [r3, r4]', 'ldrb r0, [r3]', f'orr {dst}, {dst}, r0, lsl #8',
            f't2_{op:02x}_f:'] + (['adds r4, #2', 'uxth r4, r4'] if step else [])


def store_fa(reg):
    return ['ldr r3, =global_fa', f'str {reg}, [r3]']


def store_fc(reg):
    return ['ldr r3, =global_fc', f'str {reg}, [r3]']


def carry_in(dst='r0'):
    return ['ldr r3, =global_fc', f'ldr {dst}, [r3]', f'ubfx {dst}, {dst}, #8, #1']


def alu(k):
    """ALU operation k on the operand in r2."""
    if k == 0:   # ADD
        return ['eor r0, r9, r2'] + store_fa('r0') + ['add r1, r9, r2'] + store_fc('r1') + ['uxtb r9, r1', 'mov r5, r9']
    if k == 1:   # ADC
        return carry_in('r0') + ['add r1, r9, r2', 'add r1, r1, r0'] + store_fc('r1') + \
               ['eor r0, r9, r2'] + store_fa('r0') + ['uxtb r9, r1', 'mov r5, r9']
    if k in (2, 7):   # SUB, CMP: AC inverted
        out = ['eor r0, r9, r2', 'eor r0, r0, #16'] + store_fa('r0') + ['sub r1, r9, r2'] + store_fc('r1')
        return out + (['uxtb r5, r1'] if k == 7 else ['uxtb r9, r1', 'mov r5, r9'])
    if k == 3:   # SBB
        return carry_in('r0') + ['sub r1, r9, r2', 'sub r1, r1, r0'] + store_fc('r1') + \
               ['eor r0, r9, r2', 'eor r0, r0, #16'] + store_fa('r0') + ['uxtb r9, r1', 'mov r5, r9']
    if k == 4:   # ANA: AC is the OR of bit 3 of both operands
        return ['orr r0, r9, r2', 'lsl r0, r0, #1', 'and r1, r9, r2', 'eor r0, r0, r1'] + store_fa('r0') + \
               ['mov r9, r1', 'mov r5, r1', 'movs r0, #0'] + store_fc('r0')
    op = 'eor' if k == 5 else 'orr'   # XRA, ORA: AC and CY clear
    return [f'{op} r1, r9, r2', 'mov r9, r1', 'mov r5, r1'] + store_fa('r1') + ['movs r0, #0'] + store_fc('r0')


def cond(c, op, taken_label):
    """Branch to taken_label when condition c (NZ Z NC C PO PE P M) holds."""
    if c in (0, 1):
        return ['tst r5, #255', f'{"bne" if c == 0 else "beq"} {taken_label}']
    if c in (2, 3):
        return ['ldr r3, =global_fc', 'ldr r0, [r3]', 'tst r0, #256', f'{"beq" if c == 2 else "bne"} {taken_label}']
    if c in (4, 5):
        return ['ldr r3, =global_parity', 'eor r0, r5, r5, lsr #8', 'uxtb r0, r0', 'ldrb r0, [r3, r0]', 'cmp r0, #0',
                f'{"beq" if c == 4 else "bne"} {taken_label}']
    return ['movw r0, #0x8080', 'tst r5, r0', f'{"beq" if c == 6 else "bne"} {taken_label}']


def push(val):
    """Push the 16-bit value in register `val` (not r0, r2 or r3)."""
    return ['ldr r0, =global_cpusp', 'ldr r2, [r0]', 'sub r2, r2, #2', 'uxth r2, r2', 'str r2, [r0]',
            'ldr r3, =global_m', f'strb {val}, [r3, r2]', 'add r2, r2, #1', 'uxth r2, r2',
            f'lsr r0, {val}, #8', 'strb r0, [r3, r2]']


def pop():
    """Pop 16 bits into r1."""
    return ['ldr r0, =global_cpusp', 'ldr r2, [r0]', 'ldr r3, =global_m', 'ldrb r1, [r3, r2]',
            'add r2, r2, #1', 'uxth r2, r2', 'ldrb r3, [r3, r2]', 'orr r1, r1, r3, lsl #8',
            'add r2, r2, #1', 'uxth r2, r2', 'str r2, [r0]']


def body(op):
    """(lines, touches_memory, timed_lines or None) for opcode op, or None to keep PureMetal."""
    x, y, z = op >> 6, (op >> 3) & 7, op & 7
    p = y >> 1
    if x == 1 and op != 0x76:                                             # MOV d,s
        d, s = REG[y], REG[z]
        g = get8(s)
        loaded = PAIRS.get(s)
        return g + set8(d, 'r2', loaded), 'M' in (d, s), None
    if x == 2:                                                            # ALU r
        return get8(REG[z]) + alu(y), REG[z] == 'M', None
    if x == 3 and z == 6:                                                 # ALU immediate
        return FETCH8 + alu(y), False, None
    if x == 0:
        if z == 1 and y & 1 == 0:                                         # LXI
            if p == 2:
                return fetch16(op, 'r1') + ['mov r8, r1'], False, None
            return fetch16(op, 'r1') + [f'ldr r0, ={PAIR_NAME[p]}', 'str r1, [r0]'], False, None
        if z == 1:                                                        # DAD
            src = 'r8' if p == 2 else 'r1'
            pre = [] if p == 2 else [f'ldr r0, ={PAIR_NAME[p]}', 'ldr r1, [r0]']
            return pre + ['add r1, r8, ' + src, 'lsr r0, r1, #8'] + store_fc('r0') + ['uxth r8, r1'], False, None
        if z == 2 and y < 4:                                              # STAX / LDAX B, D
            pre = [f'ldr r0, ={PAIR_NAME[y >> 1]}', 'ldr r1, [r0]', 'ldr r3, =global_m']
            return pre + (['ldrb r2, [r3, r1]', 'mov r9, r2'] if y & 1 else ['mov r2, r9', 'strb r2, [r3, r1]']), True, None
        if z == 3:                                                        # INX / DCX
            sign = 'add' if y & 1 == 0 else 'sub'
            if p == 2:
                return [f'{sign} r8, r8, #1', 'uxth r8, r8'], False, None
            return [f'ldr r0, ={PAIR_NAME[p]}', 'ldr r1, [r0]', f'{sign} r1, r1, #1', 'uxth r1, r1', 'str r1, [r0]'], False, None
        if z in (4, 5):                                                   # INR / DCR
            r = REG[y]
            g = get8(r)
            if z == 4:
                f = store_fa('r2') + ['add r2, r2, #1']
            else:
                f = ['eor r2, r2, #16'] + store_fa('r2') + ['eor r2, r2, #16', 'sub r2, r2, #1']
            return g + f + ['uxtb r5, r2'] + set8(r, 'r5', PAIRS.get(r)), r == 'M', None
        if z == 6:                                                        # MVI
            return FETCH8 + set8(REG[y], 'r2'), REG[y] == 'M', None
        return None
    # x == 3
    if z == 2:                                                            # Jcc
        t = f't2_{op:02x}_t'
        return cond(y, op, t) + ['adds r4, #2', 'uxth r4, r4', f'b t2_{op:02x}_e', f'{t}:'] + \
            fetch16(op, 'r1', step=False) + ['mov r4, r1', f't2_{op:02x}_e:'], False, None
    if z == 3 and y in (0, 1):                                            # JMP (and its duplicate)
        return fetch16(op, 'r1', step=False) + ['mov r4, r1'], False, None
    if z == 5 and y & 1:                                                  # CALL (and duplicates)
        return fetch16(op, 'r1') + push('r4') + ['mov r4, r1'], True, None
    if z == 4:                                                            # Ccc: +6 cycles taken
        t = f't2_{op:02x}_t'
        head = cond(y, op, t) + ['adds r4, #2', 'uxth r4, r4', f'b t2_{op:02x}_e', f'{t}:'] + fetch16(op, 'r1') + push('r4') + ['mov r4, r1']
        return head + [f't2_{op:02x}_e:'], True, head + ['sub r11, r11, #6', f't2_{op:02x}_e:']
    if z == 1 and y & 1 and p < 2:                                        # RET (and duplicate)
        return pop() + ['mov r4, r1'], True, None
    if z == 0:                                                            # Rcc: +6 cycles taken
        t = f't2_{op:02x}_t'
        head = cond(y, op, t) + [f'b t2_{op:02x}_e', f'{t}:'] + pop() + ['mov r4, r1']
        return head + [f't2_{op:02x}_e:'], True, head + ['sub r11, r11, #6', f't2_{op:02x}_e:']
    if z == 5 and y & 1 == 0 and p < 3:                                   # PUSH B, D, H
        src = ['mov r1, r8'] if p == 2 else [f'ldr r1, ={PAIR_NAME[p]}', 'ldr r1, [r1]']
        return src + push('r1'), True, None
    if z == 1 and y & 1 == 0 and p < 3:                                   # POP B, D, H
        if p == 2:
            return pop() + ['mov r8, r1'], True, None
        return pop() + [f'ldr r0, ={PAIR_NAME[p]}', 'str r1, [r0]'], True, None
    if z == 7:                                                            # RST n
        return push('r4') + [f'movs r4, #{y * 8}'], True, None
    return None
