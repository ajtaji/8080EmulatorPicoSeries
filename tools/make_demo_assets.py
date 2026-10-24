"""Generate the Space Invaders demo's data (demo/demo_assets.invaders).

All of it is original to this project: the 8x8 font, the logo, the aliens,
the UFO and the tune.

Video RAM on this hardware is column-major: byte $2400 + x*32 + (y>>3) holds
pixels y..y+7 of column x, bit 0 the lowest (y counts up from the bottom of
the upright screen). So every graphic here is stored as COLUMN bytes, bit 0 =
the bottom pixel: drawing an 8-pixel-tall glyph at a byte-aligned height is
eight byte writes.

    py -3 tools/make_demo_assets.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# 8x8 font, rows top to bottom, '#' = set. Characters 32..95 (space to '_').
FONT_ROWS = {
    ' ': ['........'] * 8,
    '!': ['...##...', '...##...', '...##...', '...##...', '...##...', '........', '...##...', '........'],
    '-': ['........', '........', '........', '.######.', '........', '........', '........', '........'],
    '.': ['........', '........', '........', '........', '........', '........', '...##...', '........'],
    ',': ['........', '........', '........', '........', '........', '...##...', '...##...', '..##....'],
    ':': ['........', '...##...', '...##...', '........', '...##...', '...##...', '........', '........'],
    "'": ['...##...', '...##...', '..##....', '........', '........', '........', '........', '........'],
    '/': ['......##', '.....##.', '....##..', '...##...', '..##....', '.##.....', '##......', '........'],
    '0': ['.#####..', '##...##.', '##..###.', '##.####.', '####.##.', '###..##.', '.#####..', '........'],
    '1': ['...##...', '..###...', '.####...', '...##...', '...##...', '...##...', '.######.', '........'],
    '2': ['.#####..', '##...##.', '.....##.', '...###..', '.###....', '##......', '#######.', '........'],
    '3': ['.#####..', '##...##.', '.....##.', '..####..', '.....##.', '##...##.', '.#####..', '........'],
    '4': ['....###.', '...####.', '..##.##.', '.##..##.', '#######.', '.....##.', '.....##.', '........'],
    '5': ['#######.', '##......', '######..', '.....##.', '.....##.', '##...##.', '.#####..', '........'],
    '6': ['..####..', '.##.....', '##......', '######..', '##...##.', '##...##.', '.#####..', '........'],
    '7': ['#######.', '.....##.', '....##..', '...##...', '..##....', '..##....', '..##....', '........'],
    '8': ['.#####..', '##...##.', '##...##.', '.#####..', '##...##.', '##...##.', '.#####..', '........'],
    '9': ['.#####..', '##...##.', '##...##.', '.######.', '.....##.', '....##..', '.####...', '........'],
    'A': ['..###...', '.##.##..', '##...##.', '##...##.', '#######.', '##...##.', '##...##.', '........'],
    'B': ['######..', '##...##.', '##...##.', '######..', '##...##.', '##...##.', '######..', '........'],
    'C': ['.#####..', '##...##.', '##......', '##......', '##......', '##...##.', '.#####..', '........'],
    'D': ['#####...', '##..##..', '##...##.', '##...##.', '##...##.', '##..##..', '#####...', '........'],
    'E': ['#######.', '##......', '##......', '######..', '##......', '##......', '#######.', '........'],
    'F': ['#######.', '##......', '##......', '######..', '##......', '##......', '##......', '........'],
    'G': ['.#####..', '##...##.', '##......', '##.####.', '##...##.', '##...##.', '.######.', '........'],
    'H': ['##...##.', '##...##.', '##...##.', '#######.', '##...##.', '##...##.', '##...##.', '........'],
    'I': ['.######.', '...##...', '...##...', '...##...', '...##...', '...##...', '.######.', '........'],
    'J': ['....###.', '.....##.', '.....##.', '.....##.', '##...##.', '##...##.', '.#####..', '........'],
    'K': ['##...##.', '##..##..', '##.##...', '####....', '##.##...', '##..##..', '##...##.', '........'],
    'L': ['##......', '##......', '##......', '##......', '##......', '##......', '#######.', '........'],
    'M': ['##...##.', '###.###.', '#######.', '##.#.##.', '##...##.', '##...##.', '##...##.', '........'],
    'N': ['##...##.', '###..##.', '####.##.', '##.####.', '##..###.', '##...##.', '##...##.', '........'],
    'O': ['.#####..', '##...##.', '##...##.', '##...##.', '##...##.', '##...##.', '.#####..', '........'],
    'P': ['######..', '##...##.', '##...##.', '######..', '##......', '##......', '##......', '........'],
    'Q': ['.#####..', '##...##.', '##...##.', '##...##.', '##.#.##.', '##..##..', '.###.##.', '........'],
    'R': ['######..', '##...##.', '##...##.', '######..', '##.##...', '##..##..', '##...##.', '........'],
    'S': ['.#####..', '##...##.', '##......', '.#####..', '.....##.', '##...##.', '.#####..', '........'],
    'T': ['.######.', '...##...', '...##...', '...##...', '...##...', '...##...', '...##...', '........'],
    'U': ['##...##.', '##...##.', '##...##.', '##...##.', '##...##.', '##...##.', '.#####..', '........'],
    'V': ['##...##.', '##...##.', '##...##.', '##...##.', '.##.##..', '..###...', '...#....', '........'],
    'W': ['##...##.', '##...##.', '##...##.', '##.#.##.', '#######.', '###.###.', '##...##.', '........'],
    'X': ['##...##.', '.##.##..', '..###...', '..###...', '..###...', '.##.##..', '##...##.', '........'],
    'Y': ['.##..##.', '.##..##.', '.##..##.', '..####..', '...##...', '...##...', '...##...', '........'],
    'Z': ['#######.', '.....##.', '....##..', '...##...', '..##....', '.##.....', '#######.', '........'],
}

# Two original aliens, two frames each (8 wide x 8 tall), and a 16-wide UFO.
ALIENS = [
    ['..#..#..', '...##...', '.######.', '##.##.##', '########', '.#.##.#.', '#......#', '.#....#.'],
    ['..#..#..', '#..##..#', '#.####.#', '###..###', '########', '..#..#..', '.#.##.#.', '#......#'],
    ['...##...', '..####..', '.#.##.#.', '########', '.######.', '..#..#..', '.#.##.#.', '#.#..#.#'],
    ['...##...', '..####..', '.#.##.#.', '########', '.######.', '.#.##.#.', '#......#', '.#....#.'],
]
UFO = ['................', '.....######.....', '...##########...', '..##.##.##.##.#.',
       '.##############.', '...###....###...', '....#......#....', '................']


def columns(rows, width=8):
    """Rows (top first) -> column bytes, bit 0 = the bottom pixel."""
    out = []
    for x in range(width):
        b = 0
        for r, row in enumerate(rows):
            if row[x] == '#':
                b |= 1 << (7 - r)
        out.append(b)
    return out


def glyph(c):
    return columns(FONT_ROWS.get(c, FONT_ROWS[' ']))


def logo_columns(text):
    """The text at twice the size: two bytes a column (low byte first)."""
    cols = []
    for c in text:
        rows = FONT_ROWS[c]
        for x in range(8):
            v = 0
            for r in range(8):
                if rows[r][x] == '#':
                    v |= 3 << (2 * (7 - r))     # row r -> two pixel rows
            cols += [v & 255, v >> 8] * 2         # each column twice as wide
    return cols


# The tune: A minor, Am - F - C - G, 64 eighth-note steps.
NOTE = {'G2': 98.00, 'A2': 110.00, 'C3': 130.81, 'D3': 146.83, 'E3': 164.81, 'F2': 87.31, 'F3': 174.61, 'G3': 196.00,
        'A3': 220.00, 'B3': 246.94, 'C4': 261.63, 'D4': 293.66, 'E4': 329.63, 'F4': 349.23, 'G4': 392.00,
        'A4': 440.00, 'B4': 493.88, 'C5': 523.25, 'D5': 587.33, 'E5': 659.26, 'F5': 698.46, 'G5': 783.99}


def period(n):
    return round(62500 / NOTE[n]) - 1


MELODY = ('A4 . C5 . E5 . D5 C5 B4 . C5 . A4 . . . '
          'A4 . C5 . F5 . E5 D5 C5 . D5 . A4 . . . '
          'G4 . C5 . E5 . G5 . F5 E5 D5 . C5 . . . '
          'B4 . D5 . G5 . F5 E5 D5 . B4 . G4 . . .').split()
ROOTS = ['A2', 'F2', 'C3', 'G2']
BASS = []
for root in ROOTS:
    up = {'A2': 'A3', 'F2': 'F3', 'C3': 'C4', 'G2': 'G3'}[root]
    BASS += [root, '.', up, '.', root, root, up, '.'] * 2
CHORDS = [['A3', 'C4', 'E4'], ['F3', 'A3', 'C4'], ['C4', 'E4', 'G4'], ['G3', 'B3', 'D4']]
DRUMS = [1, 0, 0, 0, 2, 0, 1, 0] * 8          # 1 kick, 2 snare
assert len(MELODY) == 64 and len(BASS) == 64

MARQUEE = 'PUREMETAL ON AN 8080, AN 8080 ON A PICO W.  HELLO 6502, Z80, 6809, 8086, 8051, 68000!  '


def words(values):
    """16-bit values as little-endian byte pairs (read with two PeekA)."""
    return [b for v in values for b in (v & 255, v >> 8)]


# The scene's moving objects, one record each (eight bytes): the left
# column drawn, the byte row, the column data (offset into SpriteCols), how
# many columns, the step, the left and right limits of that column, and the
# animation stride (the second frame's offset from the first, 0 for none). Row numbers: video byte
# rows counted up from the bottom.
ROW_ALIENS, ROW_UFO, ROW_CANNON = 18, 28, 7


def objects():
    objs = []
    for i in range(12):
        col, lower = i % 6, i >= 6
        kind = 2 if lower else 0                          # sprite pair: 0-1 upper aliens, 2-3 lower
        left = 8 + col * 16
        objs.append((left, ROW_ALIENS - 2 * lower, kind * 12, 12, 2, left - 6, left + 100, 12))
    objs.append((0, ROW_UFO, 48, 20, 2, 0, 202, 0))      # the UFO (SpriteCols 48..67)
    objs.append((96, ROW_CANNON, 68, 11, 1, 2, 211, 0))  # the cannon (68..78)
    return objs


# The opening's titles as one script: x, byte row, the characters, 0 - and
# 255 to end.
TITLES = [(36, 30, 'PUREMETAL 8080 DEMO'), (32, 23, 'SPACE INVADERS BOARD'), (24, 0, 'PICO W  60 HZ')]


def data_lines(label, values, kind='a', per=16):
    lines = [f'{label}:']
    for i in range(0, len(values), per):
        lines.append(f'  Data.{kind} ' + ', '.join(f'${v:0{2 if kind == "a" else 4}X}' for v in values[i:i + per]))
    return lines


def main():
    font = []
    for code in range(32, 91):          # space to 'Z': nothing else is drawn
        font += glyph(chr(code))
    logo = logo_columns('PUREMETAL')
    # Sprites with empty columns around them, so that a move of that many
    # columns leaves nothing behind: aliens and the UFO move two, the cannon one.
    aliens = sum(([0, 0] + columns(a) + [0, 0] for a in ALIENS), [])
    ufo = [0, 0] + columns(UFO, 16) + [0, 0]
    cannon = [0, 0x07, 0x0F, 0x0F, 0x0F, 0x7F, 0x0F, 0x0F, 0x0F, 0x07, 0]
    mel = [0 if n == '.' else period(n) for n in MELODY]
    bass = [0 if n == '.' else period(n) for n in BASS]
    arp = [period(n) for c in CHORDS for n in c]
    out = ['; Generated by tools/make_demo_assets.py - edit that, not this.',
           f'#LOGO_COLUMNS = {len(logo) // 2}', f'#MARQUEE_LEN = {len(MARQUEE)}', 'DataSection']
    out += data_lines('FontCols', font)
    out += data_lines('LogoCols', logo)
    out += data_lines('SpriteCols', aliens + ufo + cannon)
    objs = objects()
    out.insert(3, f'#OBJECTS = {len(objs)}')
    assert all(0 <= v < 256 for o in objs for v in o)
    out += data_lines('ObjectTable', [v for o in objs for v in o])     # eight bytes an object
    out += data_lines('DrumPitch', [0, 200, 12])                       # 1 kick (low noise), 2 snare
    out += data_lines('DrumLevel', [0, 14, 11])
    out += data_lines('MelodyPeriods', words(mel))
    out += data_lines('BassPeriods', words(bass))
    out += data_lines('ArpPeriods', words(arp))
    out += data_lines('DrumSteps', DRUMS)
    out += ['MarqueeText:'] + [f'  Data.a ' + ', '.join(str(ord(c)) for c in MARQUEE[i:i + 24]) for i in range(0, len(MARQUEE), 24)]
    out += ['  Data.a 0']
    script = []
    for x, row, text in TITLES:
        script += [x, row] + [ord(c) for c in text] + [0]
    out += data_lines('TitleScript', script + [255])
    out += ['EndDataSection']
    (ROOT / 'demo').mkdir(exist_ok=True)
    (ROOT / 'demo' / 'demo_assets.invaders').write_text('\n'.join(out) + '\n')
    print(f'demo/demo_assets.invaders: font {len(font)} B, logo {len(logo)} B, aliens {len(aliens)} B, '
          f'tune {2 * (len(mel) + len(bass) + len(arp))} B, marquee {len(MARQUEE)} chars')


if __name__ == '__main__':
    main()
