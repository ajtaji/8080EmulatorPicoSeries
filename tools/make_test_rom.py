"""Build the Space Invaders machine test ROM (machine/invaders_test.rom).

A small two-pass 8080 assembler (only what this program needs) and the test
program itself. The ROM exercises the machine, not the CPU (the CPU has its
own diagnostics):
  - RST 1 and RST 2 each count into RAM ($2000 and $2001)
  - the shift register: four (data, amount) cases, results stored at $2010
  - video RAM: cleared, a border drawn, and an 8x8 sprite drawn through the
    shift register at a pixel position that the inputs move (IN 1 left/right)
  - the tone device: a rising scale on channel 0, one note per 16 frames
  - IN 1 / IN 2 are copied to $2004 / $2005 every frame
After 120 frames the RAM holds known values (tools and the desktop program
check them: see EXPECT below).

    py -3 tools/make_test_rom.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REG = {'B': 0, 'C': 1, 'D': 2, 'E': 3, 'H': 4, 'L': 5, 'M': 6, 'A': 7}
PAIR = {'B': 0, 'D': 1, 'H': 2, 'SP': 3, 'PSW': 3}
COND = {'NZ': 0, 'Z': 1, 'NC': 2, 'C': 3, 'PO': 4, 'PE': 5, 'P': 6, 'M': 7}


class Asm:
    def __init__(self):
        self.out = bytearray()
        self.labels = {}
        self.fix = []

    def org(self, a):
        self.out.extend(b'\0' * (a - len(self.out)))

    def label(self, n):
        self.labels[n] = len(self.out)

    def b(self, *v):
        self.out.extend(x & 255 for x in v)

    def w(self, v):
        if isinstance(v, str):
            self.fix.append((len(self.out), v))
            v = 0
        self.b(v, v >> 8)

    # instructions
    def mov(self, d, s): self.b(0x40 | REG[d] << 3 | REG[s])
    def mvi(self, d, v): self.b(0x06 | REG[d] << 3, v)
    def lxi(self, p, v): self.b(0x01 | PAIR[p] << 4); self.w(v)
    def lda(self, a): self.b(0x3A); self.w(a)
    def sta(self, a): self.b(0x32); self.w(a)
    def ldax(self, p): self.b(0x0A | PAIR[p] << 4)
    def stax(self, p): self.b(0x02 | PAIR[p] << 4)
    def inx(self, p): self.b(0x03 | PAIR[p] << 4)
    def dcx(self, p): self.b(0x0B | PAIR[p] << 4)
    def dad(self, p): self.b(0x09 | PAIR[p] << 4)
    def inr(self, r): self.b(0x04 | REG[r] << 3)
    def dcr(self, r): self.b(0x05 | REG[r] << 3)
    def alu(self, op, r): self.b(0x80 | ['ADD', 'ADC', 'SUB', 'SBB', 'ANA', 'XRA', 'ORA', 'CMP'].index(op) << 3 | REG[r])
    def alui(self, op, v): self.b(0xC6 | ['ADI', 'ACI', 'SUI', 'SBI', 'ANI', 'XRI', 'ORI', 'CPI'].index(op) << 3, v)
    def jmp(self, t): self.b(0xC3); self.w(t)
    def j(self, c, t): self.b(0xC2 | COND[c] << 3); self.w(t)
    def call(self, t): self.b(0xCD); self.w(t)
    def ret(self): self.b(0xC9)
    def push(self, p): self.b(0xC5 | PAIR[p] << 4)
    def pop(self, p): self.b(0xC1 | PAIR[p] << 4)
    def out_(self, p): self.b(0xD3, p)
    def in_(self, p): self.b(0xDB, p)
    def ei(self): self.b(0xFB)
    def di(self): self.b(0xF3)
    def xchg(self): self.b(0xEB)
    def rlc(self): self.b(0x07)
    def rrc(self): self.b(0x0F)
    def hlt(self): self.b(0x76)

    def finish(self, size):
        for at, n in self.fix:
            v = self.labels[n]
            self.out[at] = v & 255
            self.out[at + 1] = v >> 8
        assert len(self.out) <= size, len(self.out)
        return bytes(self.out) + b'\0' * (size - len(self.out))


# RAM layout
RST1, RST2, FRAME, SPRX, IN1, IN2, NOTE = 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006
SHIFTS = 0x2010
CASES = [(0x12, 0x34, 0), (0xAB, 0xCD, 3), (0xF0, 0x0F, 5), (0x80, 0x01, 7)]   # (first, second, amount)


def shift_expect(first, second, amount):
    reg = (second << 8) | first
    return (reg >> (8 - amount)) & 255


def build():
    a = Asm()
    a.jmp('start')
    a.org(0x0008); a.jmp('rst1')        # RST 1: mid-screen
    a.org(0x0010); a.jmp('rst2')        # RST 2: VBLANK
    a.org(0x0040)
    a.label('rst1')
    a.push('PSW'); a.lda(RST1); a.inr('A'); a.sta(RST1); a.pop('PSW'); a.ei(); a.ret()
    a.label('rst2')
    a.push('PSW'); a.lda(RST2); a.inr('A'); a.sta(RST2); a.lda(FRAME); a.inr('A'); a.sta(FRAME); a.pop('PSW'); a.ei(); a.ret()
    a.label('start')
    a.lxi('SP', 0x2400)
    # Clear RAM $2000-$3FFF.
    a.lxi('H', 0x2000); a.lxi('B', 0x2000)
    a.label('clr'); a.mvi('M', 0); a.inx('H'); a.dcx('B'); a.mov('A', 'B'); a.alu('ORA', 'C'); a.j('NZ', 'clr')
    # Shift register cases -> $2010...
    a.lxi('H', SHIFTS)
    for first, second, amount in CASES:
        a.mvi('A', first); a.out_(4); a.mvi('A', second); a.out_(4); a.mvi('A', amount); a.out_(2)
        a.in_(3); a.mov('M', 'A'); a.inx('H')
    # Border: column 0 and 223 all set; bottom and top rows of every column.
    a.lxi('H', 0x2400); a.mvi('C', 32)
    a.label('col0'); a.mvi('M', 0xFF); a.inx('H'); a.dcr('C'); a.j('NZ', 'col0')
    a.lxi('H', 0x2400 + 223 * 32); a.mvi('C', 32)
    a.label('col223'); a.mvi('M', 0xFF); a.inx('H'); a.dcr('C'); a.j('NZ', 'col223')
    a.lxi('H', 0x2400); a.lxi('D', 32); a.mvi('C', 224)
    a.label('rows'); a.mov('A', 'M'); a.alui('ORI', 0x01); a.mov('M', 'A')     # bottom pixel row
    a.push('H'); a.mvi('A', 31); a.alu('ADD', 'L'); a.mov('L', 'A'); a.mvi('A', 0); a.alu('ADC', 'H'); a.mov('H', 'A')
    a.mov('A', 'M'); a.alui('ORI', 0x80); a.mov('M', 'A'); a.pop('H')          # top pixel row
    a.dad('D'); a.dcr('C'); a.j('NZ', 'rows')
    a.mvi('A', 40); a.sta(SPRX)
    # Tone channel 0: square, volume 12.
    a.mvi('A', 0); a.out_(0x13); a.mvi('A', 12); a.out_(0x12)
    a.ei()
    # Main loop: once a frame, read the inputs, move and draw the sprite, play.
    a.label('main')
    a.lda(FRAME); a.mov('B', 'A')
    a.label('wait'); a.lda(FRAME); a.alu('CMP', 'B'); a.j('Z', 'wait')
    a.in_(1); a.sta(IN1); a.mov('C', 'A'); a.in_(2); a.sta(IN2)
    a.lda(SPRX); a.mov('D', 'A')
    a.mov('A', 'C'); a.alui('ANI', 0x20); a.j('Z', 'noleft'); a.dcr('D')
    a.label('noleft')
    a.mov('A', 'C'); a.alui('ANI', 0x40); a.j('Z', 'noright'); a.inr('D')
    a.label('noright')
    a.mov('A', 'D'); a.sta(SPRX)
    # The sprite: 8 columns at x = 100..107, an 8x8 block whose height
    # position y = SPRX (pixels up from the bottom) is placed through the
    # shift register: byte = SPRX >> 3 within the column, amount = SPRX & 7.
    a.lxi('H', 0x2400 + 100 * 32)
    a.mov('A', 'D'); a.rrc(); a.rrc(); a.rrc(); a.alui('ANI', 0x1F); a.mov('E', 'A'); a.mvi('A', 0); a.mov('D', 'A')
    a.dad('D')                                    # HL = column 100 + byte offset
    a.lda(SPRX); a.alui('ANI', 7); a.out_(2)
    a.mvi('C', 8)
    a.label('sprcol')
    a.mvi('A', 0); a.out_(4); a.mvi('A', 0xFF); a.out_(4)    # reg = $FF00
    a.in_(3); a.mov('M', 'A'); a.inx('H')                      # low part
    a.mvi('A', 0); a.out_(4)                                   # reg = $00FF
    a.in_(3); a.mov('M', 'A')                                  # high part
    a.lxi('D', 31); a.dad('D')
    a.dcr('C'); a.j('NZ', 'sprcol')
    # Tone: every 16 frames the next note of a rising scale.
    a.lda(FRAME); a.alui('ANI', 15); a.j('NZ', 'main')
    a.lda(NOTE); a.inr('A'); a.alui('ANI', 7); a.sta(NOTE)
    a.mov('E', 'A'); a.mvi('D', 0); a.lxi('H', 'notes'); a.dad('D'); a.mov('A', 'M'); a.out_(0x10)
    a.jmp('main')
    a.label('notes')
    for hz in (262, 294, 330, 349, 392, 440, 494, 523):
        a.b(round(62500 / hz) - 1)
    return a.finish(0x2000)


# What RAM holds after 120 frames from reset with no input. The interrupt
# counters are not a fixed number: the first frames pass with interrupts off
# while RAM is cleared, so the check is RST2 = FRAME >= 100 and RST1 - RST2
# is 0 or 1 (interrupts come on mid-frame, before VBLANK).
EXPECT = {SPRX: 40, **{SHIFTS + i: shift_expect(*c) for i, c in enumerate(CASES)}}
COUNTERS = (RST1, RST2, FRAME)

if __name__ == '__main__':
    rom = build()
    out = ROOT / 'machine'
    out.mkdir(exist_ok=True)
    (out / 'invaders_test.rom').write_bytes(rom)
    lines = ['; Generated by tools/make_test_rom.py: RAM after 120 frames with no input.', 'DataSection', '  InvTestExpect:']
    for adr, v in sorted(EXPECT.items()):
        lines.append(f'  Data.l ${adr:04X}, {v}')
    lines += ['  Data.l -1, -1', '  InvTestCounters:']
    lines += ['  Data.l ' + ', '.join(f'${c:04X}' for c in COUNTERS)]
    lines += ['EndDataSection']
    for ext in ('pbi', 'pmi'):       # the desktop (PureBasic) and the Pico (PureMetal)
        (out / f'invaders_test_expect.{ext}').write_text('\n'.join(lines) + '\n')
    print('machine/invaders_test.rom', len(rom), 'bytes;', {hex(k): v for k, v in EXPECT.items()})
