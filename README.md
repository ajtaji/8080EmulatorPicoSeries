# Intel 8080 Emulator for the Raspberry Pi Pico Series — PureMetal

A fast, cycle-exact Intel 8080 CPU core for the Raspberry Pi Pico W (RP2040)
and Pico 2 W (RP2350), written in PureMetal, with a complete Space Invaders
(Taito 8080) machine built on it, an original music-and-graphics demo for that
board written in PureMetal, and a desktop version with a debugger window. The
core runs from SRAM and dispatches every opcode through a computed-jump
table; on the RP2350 the hot handlers are hand-written Thumb-2. It passes the
classic CP/M 8080 diagnostics (TST8080, 8080PRE, CPUTEST and the 8080
instruction exerciser) with exact instruction and cycle counts on real
silicon.

<p align="center">
  <img src="demo/demo-screen.png" alt="The PureMetal demo on the Space Invaders machine" width="224">
  &nbsp;&nbsp;
  <img src="desktop/demo-window.png" alt="The desktop debugger window running the demo" width="560">
</p>

## Features

- **All 256 opcodes**, including the twelve undocumented duplicates, with
  exact S, Z, P, CY and AC flags (the 8080's own AC rules, DAA included).
- **Cycle-exact timing** when wanted (`#CPU_TIMING = 1`), from the 8080 data
  sheet; the EI delay, HLT and RST interrupts as on the chip.
- **A small API** for building machines: port hooks, an optional 256-byte page
  map with read/write traps for ROM and I/O, run windows by instructions or
  cycles, interrupt requests.
- **Fast:** 4.4-7.9 M instructions/s on the four measured mixes, about
  22 times a 2 MHz 8080 on real code on the Pico 2 W (figures below).
- **Space Invaders machine** on a 480x320 ST7796 panel at 60 frames a second
  with both cores working: core 0 runs the 8080, core 1 draws the screen by
  DMA (and drives Bluetooth audio on the Pico W).
- **An original PureMetal demo** for the Space Invaders board (graphics, font,
  four-voice music), shipped as ready-to-run firmware.
- **Desktop version** (Windows, PureBasic) with registers, disassembly,
  memory view, breakpoints, the test suites and the machine's screen.

## Supported hardware

| Board | Chip | Status |
|---|---|---|
| Raspberry Pi Pico W | RP2040 at 200 MHz | Core, diagnostics and Space Invaders machine proven on the board |
| Raspberry Pi Pico 2 W | RP2350 (Cortex-M33) at 150 MHz | Core, diagnostics and Space Invaders machine proven on the board; Thumb-2 handlers |

The Space Invaders machine uses the **LAFVIN Pico kit's 3.5" ST7796 panel**
(480x320, SPI0: SCK GP2, MOSI GP3, CS GP5, DC GP6, RST GP7), its analogue
stick (GP26) and its two buttons (GP15, GP14). The same wiring is used on both
boards. Sound on the Pico W goes to a Bluetooth A2DP speaker (see
[Sound](#sound)); the Pico 2 W build is silent.

## Quick start

1. Hold **BOOTSEL** on the Pico while plugging it into USB; it appears as a
   drive (`RPI-RP2` or `RP2350`).
2. Copy one of the images from [`firmware/`](firmware) onto that drive. The
   board reboots into it.

| Image | Board | What it runs |
|---|---|---|
| `invaders-demo-picow.uf2` | Pico W + LAFVIN panel | The PureMetal demo on the Space Invaders machine |
| `invaders-demo-pico2w.uf2` | Pico 2 W + LAFVIN panel | The same on the Pico 2 W |
| `invaders-picow.uf2` | Pico W + LAFVIN panel | The machine test ROM, which checks itself after 120 frames |
| `invaders-pico2w.uf2` | Pico 2 W + LAFVIN panel | The same on the Pico 2 W |
| `8080-picow.uf2` | Pico W | The CPU benchmark: four instruction mixes, results over USB serial |
| `8080-pico2w.uf2` | Pico 2 W | The same on the Pico 2 W |

Open the board's USB serial port (any terminal, 115200 baud) to see the
status lines: `INVADERS_STATUS` once a second, with the frame rates and each
core's busy share, or the benchmark's instructions per second.

The images in `firmware/` were built with PureMetal Forge (signed compiler
`883c4ae12`) and are the ones measured on the boards.

### Controls (Space Invaders machine)

| Action | LAFVIN kit | USB serial key |
|---|---|---|
| Move left / right | Stick | `a` / `d` |
| Fire | Button A (GP15) | `f` |
| Coin + 1-player start | Button B (GP14) | `c`, then `1` (or `2`) |
| Mute | — | `m` |
| Reset the machine | — | `r` |

A serial key holds its control for 0.2 s.

## Running the original Space Invaders

**No Taito ROM is included in this repository or in any firmware image**, and
none was used to build or test it. The machine follows the documented Taito
8080 hardware and is verified with this project's own test ROM and demo.

The game's program is four 2 KB ROM chips, `invaders.h`, `invaders.g`,
`invaders.f` and `invaders.e` (MAME's `invaders` set, loaded in that order at
$0000-$1FFF). Get them legally:

- **Dump the EPROMs of a Space Invaders board you own** (H, G, F and E
  positions), or
- **use a commercially licensed release** that provides the ROM files for
  your personal use.

Do not download ROM sets from sites that distribute them without the rights
holder's permission.

**On the desktop:** start `desktop/i8080desk.exe`, choose **Open...** on the
Screen tab and pick the folder holding the four files (or one 8 KB image).
Headless: `desktop/invaders_cli.exe <folder> 600 --png screen.png`.

**On a Pico:** the ROM is built into the firmware image, so you build your
own image (see [Building from source](#building-from-source)); it stays on
your machine:

```powershell
py -3 tools/embed_rom.py C:\path\to\your\invaders src/inv_rom_user.pmi
.\tools\build.ps1 -Source src/invaders_rom.picow  -Output firmware/invaders-rom-picow.uf2
.\tools\build.ps1 -Source src/invaders_rom.pico2w -Output firmware/invaders-rom-pico2w.uf2
```

`src/inv_rom_user.pmi` and `firmware/invaders-rom-*.uf2` are ignored by git,
so they are never committed. Copy the image to the board as in the quick
start.

## Measured speed

Physical boards. Each sample runs exactly 1,000,000 guest instructions with
cycle accounting off (`#CPU_TIMING = 0`, assembly tail); USB and setup are
outside the timed interval. Raw logs are in `docs/`. Pico W 2026-10-23;
Pico 2 W 2026-10-25 with the Thumb-2 handlers and the `ldr pc` tail (signed
compiler 883c4ae12).

| Mix | Pico W, RP2040 at 200 MHz | Pico 2 W, RP2350 at 150 MHz |
|---|---:|---:|
| DCR C / JNZ | 4.88 M instructions/s | **6.25 M** |
| ADI / XRI / RLC / RAR / ADD / DAA | 4.43 M | **4.53 M** |
| MOV A,M / STAX D / INX H / INX D / DCR C / JNZ (copy) | 6.70 M | **7.88 M** |
| CALL / PUSH B / PUSH H / POP H / POP B / RET | 3.79 M | **5.47 M** |
| Real code: CPUTEST (34.0 M instructions) | 5.94 M | **7.10 M** |
| Real code: 8080EXM (2.92 G instructions) | 4.56 M | **5.31 M** |

For scale: 8080EXM averages 8.15 cycles per instruction, so a 2 MHz 8080
runs it at about 0.245 M instructions/s; the Pico W runs it about 18 times
faster and the Pico 2 W about 22 times (an 8080 at roughly 43 MHz). These are
instruction rates for these mixes, not a guaranteed clock.

**RP2040 tuning:** the first version ran the four mixes at 3.71 / 3.87 / 5.33 /
3.31 M (`docs/benchmark-baseline.log`); `docs/benchmark-layouts.log` has the
six register layouts measured on the way. The RP2040 is Thumb-1 (Cortex-M0+).

**RP2350 tuning (Thumb-2, 2026-10-25):** the Pico 2 W first ran the same
handlers as the Pico W through a 7-instruction tail: 3.62 / 3.58 / 5.59 /
3.15 M, 8080EXM in 769 s. The tail now loads the handler's address with one
scaled `ldr` (3.71 / 3.65 / 5.80 / 3.22 M on its own), and the hot handler
families - MOV, the ALU (register, memory, immediate), INR/DCR, INX/DCX, MVI,
LXI, DAD, LDAX/STAX, the jumps, calls and returns with their conditions,
PUSH/POP and RST - are hand-written Cortex-M33 code (`tools/t2_handlers.py`:
`ubfx`/`bfi` for the register halves, an unaligned `ldrh` for 16-bit
operands, no stack spills). The compiled handlers spilled to the stack
constantly (DCR C was 25 instructions, now 9). Result: 6.00 / 4.43 / 7.42 /
5.17 M, +66 / +24 / +33 / +64 %, 8080EXM in 570 s; the handler code shrank
from 22.7 KB to 18.8 KB. The Thumb-2 bodies are used only where the
assembly tail is on, and for handlers that touch guest memory only without
the page map; every other build keeps the PureMetal bodies (the plain-tail
build compiles to the same bytes as before). `docs/benchmark-pico2w-thumb2.log`.
Last, the tail's `ldr r1` + `bx r1` became one `ldr pc, [r6, r2, lsl #2]`
(load and branch; accepted by the compiler's RP2350 assembler since
signed compiler 883c4ae12): 6.25 / 4.53 / 7.88 / 5.47 M, a further +4 / +2 /
+6 / +6 %, 8080EXM in 549 s, the whole suite passing again in the fast,
timed and timed-with-page-map builds (`docs/verification-pico2w-ldrpc.log`,
`docs/benchmark-pico2w-ldrpc.log`). From the first Pico 2 W build that is
+73 / +26 / +41 / +74 %. The Pico W images are byte-identical under this
compiler, so the RP2040 figures stand.

**A second RP2350 layout, `src/i8080_lib.pico2`:** the fast layout reserves
both r5 and r6, and the compiler's RP2350 register allocator then has three
spill registers instead of five; a program that also includes library code
needing four (the ST7796 driver's `Tft796Fill`) is refused at compile time.
The library layout is the same core without `TableBase` - the tail loads the
table's address as a literal - and is what the Space Invaders machine on the
Pico 2 W uses. It runs the four mixes at 5.77 / 4.43 / 7.07 / 5.00 M
(`docs/benchmark-pico2w-lib.log`): 2-8 % behind the fast layout, still ahead
of the Pico W on every mix.

Configuration costs, measured: the plain PureMetal `Goto` tail is about 27%
slower than the assembly tail on real code (Pico W CPUTEST 7.84 s against
5.72 s); the page map (`#CPU_MEMMAP = 1`) costs about 1% on CPUTEST but about
50% on the memory-heavy 8080EXM (Pico 2 W: 1,160 s against 769 s), since
every data access becomes a procedure call; timing costs nothing measurable.

The Pico W demo uses 37 KB of flash, 21.5 KB of its code running from SRAM
(the Pico 2 W's: 18.8 KB). Guest memory is 64 KiB, the dispatch table 1 KiB.

## The Space Invaders machine and the PureMetal demo

The core also runs a whole machine: the Taito 8080 "Space Invaders" board,
on the desktop and on the Pico W's panel, and a demo for it written in
PureMetal and compiled for the compiler's Space Invaders board.

**The hardware** (the same contract in `desktop/invaders.pbi` and
`src/invaders.pmi`): 8 KB ROM at $0000 (writes ignored), RAM $2000-$23FF,
video RAM $2400-$3FFF (1 bpp, column-major, shown upright 224 x 256 with the
cabinet's red and green bands), mirrors above $4000; 2 MHz, 33,333 cycles a
60 Hz frame with RST 1 at mid-screen and RST 2 at the vertical blank; IN 1 /
IN 2 controls, the shift register (OUT 2, OUT 4, IN 3), the sound bits (OUT 3,
OUT 5, synthesized), the watchdog (OUT 6). For the demos it adds a 4-channel
tone device at OUT $10-$1F: channel c at $10 + 4c: period low, period high
(4 bits), volume 0-15, wave (square, 25% pulse, triangle, noise); frequency
62500 / (period + 1) Hz.

| | |
|---|---|
| `tools/make_test_rom.py` | assembles `machine/invaders_test.rom`: both interrupts counted, the shift register checked, a border and a sprite moved by the controls, a scale on the tone device |
| `desktop/invaders_cli.exe` | runs a ROM (file, or the compiler's folder of invaders.h/g/f/e) headless: counts, VRAM SHA-256 or checksum, every OUT, RAM bytes, a PNG of the screen |
| `desktop/i8080desk.exe` | the Screen tab: the machine at integer scale, arrows / Space / 1 / 2 / C, sound through waveOut |
| `src/invaders.picow` | the Pico W with the LAFVIN ST7796: core 0 runs the machine, core 1 draws the picture (RGB565 by DMA, SPI0 at 100 MHz) and drives the radio; built-in test ROM checked on the board |
| `src/invaders_demo.picow` | the same with the PureMetal demo built in |
| `src/invaders.pico2w`, `src/invaders_demo.pico2w` | the same two on the Pico 2 W, on the same LAFVIN kit (SPI0 at 75 MHz from clk_sys 150 MHz); no radio in this build |

### Sound

**Sound on the Pico W** goes to a Bluetooth speaker (A2DP, through the
compiler's `Shared/Bluetooth` libraries). The speaker's address is private:
a wrapper outside this repository calls `InvBluetoothSetPeer(?address)` and
includes `src/invaders_rp2040.pmi` (see `src/inv_audio.pmi`). Without one the
machine runs silent. Controls: see [Controls](#controls-space-invaders-machine).

Proven, 2026-10-23: the test ROM leaves exactly the same RAM on the desktop
and on the Pico W (RST1 110, RST2 109, shift results 52 / 109 / 254 / 192,
sprite 40 at frame 120). The Pico W keeps 60 machine frames and 60 panel
frames a second, 48,000 sound samples a second, using 2.6 ms of core 0 a
frame for the test ROM and about 3.7 ms for the demo. The demo's music (all
four voices) and effects play on the Bluetooth speaker with no underruns
(about 125 packets a second). The desktop sound path is
checked silently by `desktop/audio_check.exe`.

**Both cores, on both Picos (2026-10-25).** The board is a 60 Hz US machine,
so the machine and the panel both run at 60 frames a second. Core 0 runs the
8080 and the machine's sound, and after each frame copies the 7 KB of video
RAM into a snapshot; core 1 turns the snapshot's bits straight into RGB565
rows with the cabinet's colour bands and sends them by DMA from two buffers in
turn (`src/inv_video.pmi`), and drives the radio when there is one. A
snapshot is taken only when core 1 has finished the last, so no picture is
torn; `vid_dropped` counts frames that had to wait (none did). Each core's
share is printed once a second: core 0 is idle only while it waits for the
next 60 Hz tick, core 1 counts the passes in which it did work.

| Board | ROM | core 0 busy | core 1 busy | machine / panel frames a second | frame 1200 VRAM |
|---|---|---:|---:|---|---|
| Pico W (RP2040, 200 MHz) | test ROM | 17% | 74% | 61 / 61 | 264782938, PASS |
| Pico W | demo | 24% | 76% | 61 / 60-62 | -2054358275 |
| Pico 2 W (RP2350, 150 MHz) | test ROM | 17% | 78% | 61 / 60 | 264782938, PASS |
| Pico 2 W | demo | 25% | 79% | 61 / 61 | -2054358275 |

The checksums are the desktop's (`invaders_cli.exe --checksum`). Before the
split core 0 also built every row of the picture and waited for room in a ring
to core 1: 91% busy for the demo. Logs: `docs/invaders-picow-cores.log`,
`docs/invaders-pico2w-cores.log`.

### The demo

`demo/demo.invaders`, built with the compiler at b86f45bd7 or later
(`tools/build_demo.ps1` builds it and runs it headless): the screen wipes in
under a red PUREMETAL logo, the titles type themselves, then a formation of
original aliens marches in a wave to the board's four-note footsteps, a UFO
patrols the sky, a cannon the ground, a ticker types a message, and an
original tune in A minor (square lead, triangle bass, pulse arpeggio, noise
drums) plays on
the tone device. Graphics, font and music are this project's own
(`tools/make_demo_assets.py`).

It is shaped by two budgets. A frame is 33,333 cycles and a compiled loop
moving one byte costs about 600 of them, so work is spread over frames as the
original game does it (one alien a frame; the opening wipe one column a
frame). The ROM is 8 KB and compiled statements cost 20-80 bytes each, so the
scene is data - a table of moving objects run by one loop - and the music
writes only the registers that change. The tune is clocked by the
vertical-blank interrupt and the objects count main-loop passes, so neither
drifts if a pass runs late. With the compiler's 16-bit unsigned compares
(b86f45bd7) the program shrank by 766 bytes and its main loop
completes every frame (2,999 passes in 3,000 frames, against 92% before);
the room went to the arpeggio, leaving 136 bytes of the ROM free.

The demo runs identically on the desktop and the Pico W: video RAM's
checksum at frame 1200 is -2054358275 on both.

## Desktop version

`desktop/` is the same 8080 in PureBasic (C back end, x64), generated by
`tools/generate_desktop.py` from the same opcode table, with a debugger
window drawn by the [Neon Arcade Display Engine](https://github.com/ajtaji/Neon-Arcade-Dispay-Engine).

| File | What |
|---|---|
| `desktop/i8080core.pbi` | The core (generated). `#CPU_DISPATCH` 0: computed goto through the C back end's labels-as-values; 1: a table of procedure addresses. Budgets in cycles and counts instructions too |
| `desktop/cpm.pbi` | The CP/M test machine: BDOS stub, `.COM` loader, the reference counts |
| `desktop/verify_desktop.pb` | Console verification and benchmark |
| `desktop/i8080desk.pb` | The window: registers and flags, disassembly at PC, memory view, CP/M console, run / pause / step / step 100 / reset, a breakpoint, the four test programs and "Run all suites" with verdicts, the live speed |

### Building the desktop version

You need **PureBasic 6.41 (x64, C back end)** on Windows. Clone this
repository and the engine side by side:

```powershell
git clone https://github.com/ajtaji/8080EmulatorPicoSeries.git
git clone https://github.com/ajtaji/Neon-Arcade-Dispay-Engine.git
cd 8080EmulatorPicoSeries\desktop
& 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' i8080desk.pb /THREAD /DPIAWARE /OPTIMIZER /EXE i8080desk.exe
& 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' verify_desktop.pb /CONSOLE /OPTIMIZER /EXE verify_desktop.exe
& 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' invaders_cli.pb /CONSOLE /OPTIMIZER /EXE invaders_cli.exe
.\i8080desk.exe
```

`i8080desk.pb` finds the engine at `../../Neon-Arcade-Dispay-Engine/` (beside
this repository). With the engine somewhere else, add
`/CONSTANT 'GL_ENGINE_DIR$=C:/path/to/Neon-Arcade-Dispay-Engine/'` (forward
slashes, trailing slash).

### Running the desktop version

Start `desktop\i8080desk.exe` any way you like - double-click it, or run it
from the repository or from `desktop\`. With nothing on the command line it
opens on the **PureMetal demo** (Screen tab). The Screen tab's buttons switch
between **Machine test ROM** and **PureMetal demo**, and **Open...** loads any
other ROM (an 8 KB file, or a folder holding invaders.h/g/f/e). A ROM it
cannot read is reported in an error box and on the status line.

```powershell
.\desktop\i8080desk.exe                          # the PureMetal demo
.\desktop\i8080desk.exe C:\path\to\your\invaders # your own ROM folder
.\desktop\i8080desk.exe --mute                   # no sound
```

Keys on the Screen tab: arrows move, Space fires, 1 / 2 start, C coin. A
relative path on the command line is tried from the current folder, the exe's
folder and the repository. The window also takes a `.COM` file to load, or
`--selftest` (runs the four
programs in the window, writes `selftest.log` and `selftest.png`, closes).
The test programs come from `tools/fetch_tests.py` as for the boards.

Measured on this PC (one run each; desktop clocks vary): both dispatch forms
pass all 8,721 desktop directed checks and the four programs with instruction
and cycle counts exact. Computed goto runs 8080EXM in 5.5 s (about 525 M
instructions/s) against 8.3 s (351 M) for the procedure table, and is 1.3-1.4
times faster on every mix, so the window uses it. `desktop/selftest.png` is
the window's own capture of its suite results.

## Building from source

You need:

- **PureMetal Forge** (the PureMetal compiler) — the shipped images were
  built with signed compiler `883c4ae12`; any later version builds them.
  Point the scripts at it with `-Compiler <path>` or the environment variable
  `PUREMETAL_FORGE`, or put `PureMetalForge.exe` on the `PATH`.
- **Windows PowerShell** (the build scripts) and **Python 3** (`py -3`, the
  generators). Build x64.

```powershell
$env:PUREMETAL_FORGE = 'C:\path\to\PureMetalForge.exe'

# The CPU benchmark
.\tools\build.ps1 -Source src/demo.picow  -Output firmware/8080-picow.uf2
.\tools\build.ps1 -Source src/demo.pico2w -Output firmware/8080-pico2w.uf2

# The Space Invaders machine: test ROM, demo
.\tools\build.ps1 -Source src/invaders.picow       -Output firmware/invaders-picow.uf2
.\tools\build.ps1 -Source src/invaders_demo.picow  -Output firmware/invaders-demo-picow.uf2
.\tools\build.ps1 -Source src/invaders.pico2w      -Output firmware/invaders-pico2w.uf2
.\tools\build.ps1 -Source src/invaders_demo.pico2w -Output firmware/invaders-demo-pico2w.uf2
```

Add `-Port COMn -Seconds 30` to upload the image to a connected board that
is already running one of these images (by its 1200-baud reset, no BOOTSEL
button needed) and print its serial output.
`tools/board.ps1 -Jobs <file> -Port COMn` runs a list of such builds in a
row. On a bench where several people share boards, both scripts take the
board's lease through a lease script (`$env:BOARD_LEASE_SCRIPT`) when there
is one.

The cores are generated: after editing `tools/generate.py` (or
`tools/t2_handlers.py`), run `py -3 tools/generate.py` to rewrite
`src/i8080.pico`, `src/i8080.pico2` and `src/i8080_lib.pico2`.

**The demo** is compiled by PureMetal Forge for its Space Invaders board
(`demo/demo.invaders` → the four ROM chips in `demo/demo_roms/`), then
embedded for the Picos:

```powershell
.\tools\build_demo.ps1                 # compiles the demo and runs it headless on the desktop machine
py -3 tools/embed_rom.py demo/demo_roms src/inv_rom_demo.pmi
```

`py -3 tools/make_demo_assets.py` regenerates its graphics, font and music
tables; `py -3 tools/make_test_rom.py` reassembles the machine test ROM.

## Testing

**On the boards** (the CPU diagnostics need the test programs, which are
fetched, not shipped — see [Credits](#credits-and-licences)):

```powershell
py -3 tools/fetch_tests.py     # downloads the four .COM files, pinned by commit and SHA-256
py -3 tools/embed_tests.py     # embeds them for the diagnostics build
.\tools\build.ps1 -Source Diagnostics/verify-fast.picow -Output Diagnostics/verify-fast.uf2 -Port COM7 -Seconds 780
```

The other configurations are `verify-timed`, `verify-memmap`,
`verify-timed-memmap`, `verify-pure` and `verify-pure-full`, each as
`.picow` and `.pico2w`. A run prints `verification complete failures=0 PASS`
at the end.

**On the desktop** (see below): `verify_desktop.exe` runs the directed checks
and the four programs; `i8080desk.exe --selftest` runs them in the window and
saves `selftest.png`.

What passes on silicon is listed in [Verification on the board](#verification-on-the-board).

## Using the core

Declare the configuration, then include the core:

```text
#CPU_TIMING   = 1   ; 1: CpuRun's budget is in 8080 clock cycles; 0: in instructions
#CPU_ASM_TAIL = 1   ; 1: assembly dispatch tail; 0: plain PureMetal computed Goto
#CPU_MEMMAP   = 0   ; 1: data reads/writes go through the page map and traps
XIncludeFile "i8080.pico"        ; i8080.pico2 on the Pico 2 W
```

All three constants must be defined; a missing one is a compile error.

### The program supplies

| Procedure | Called for |
|---|---|
| `Procedure.i CpuPortIn(port.i)` | `IN port`; the low 8 bits of the result go to A |
| `Procedure CpuPortOut(port.i, value.i)` | `OUT port` |
| `Procedure.i CpuReadTrap(address.i)` | (`#CPU_MEMMAP = 1` only) a data read from a page whose map bit 0 is clear |
| `Procedure CpuWriteTrap(address.i, value.i)` | (`#CPU_MEMMAP = 1` only) a data write to a page whose map bit 1 is clear |

Any of these may set `CpuYield = 1`: the run window then ends after the
current instruction (a CP/M BDOS trap, a video frame boundary, ...).

### State and calls

| API | Meaning |
|---|---|
| `M(address)` | The 64 KiB of guest memory (bytes). Opcode and operand fetches always read it directly |
| `CpuMemMap(page)` | `#CPU_MEMMAP = 1`: per 256-byte page, bit 0 = reads come from `M`, bit 1 = writes go to `M`; a clear bit sends the access to the trap. **Every page starts trapped (0)**: map RAM as 3 and ROM as 1 |
| `CpuA`, `CpuBC`, `CpuDE`, `CpuHL`, `CpuSP`, `CpuPC` | Registers; pairs are 16-bit values (B = `CpuBC >> 8`, C = `CpuBC & 255`). Keep them in range when you write them |
| `CpuFlags()` / `CpuSetFlags(p)` | The PSW flag byte `S Z 0 AC 0 P 1 CY`; any value round-trips (bits 1, 3, 5 read as 1, 0, 0) |
| `CpuIE`, `CpuHalted` | Interrupt enable; set by HLT, cleared when an interrupt is taken |
| `CpuReset()` | PC = 0, SP = 0, A and pairs 0, flags $02, interrupts off, not halted (deterministic, not a model of the undefined power-on state) |
| `CpuRun(n)` | Run whole instructions until the budget is spent: `n` instructions, or with timing at least `n` cycles. Returns what was consumed (a timed run may overshoot by part of one instruction). `n <= 0` does nothing |
| `CpuInterrupt(opcode)` | Between run windows, a device puts `RST n` (`$C7`, `$CF`, ... `$FF`) on the bus. Refused (returns 0) when interrupts are disabled, during the one instruction after `EI`, or for an opcode that is not an RST. Taken: wakes HLT, disables interrupts, pushes PC, jumps to `n * 8`, returns 11 (the cycles it took) |

Load a program into `M`, call `CpuReset()`, set `CpuPC` (and `CpuSP`), then
call `CpuRun` in windows. Between windows pump USB, pet the watchdog, update
the machine and deliver interrupts. A machine with a cycle budget per video
line or frame uses `#CPU_TIMING = 1` and windows of that many cycles.

**HLT** ends the window. Untimed, a halted CPU runs nothing (`CpuRun` returns
0). Timed, HLT charges its 7 cycles and the rest of the window is spent
halted, and later windows return their whole budget, so a machine's clock
keeps running until an interrupt wakes the CPU.

**Timing** uses the 8080 data-sheet counts: 4-18 cycles per instruction,
conditional CALL 11/17 and conditional RET 5/11 (not taken / taken), MOV r,r
5, XCHG 4. The run budget is a signed 32-bit count; accumulate totals in the
machine.

**Reserved registers.** The core holds CpuPC, CpuA, Res, Left, CpuHL and FR in
host registers for the whole program — RP2040: r8, r9, r10, r11, r4, r5;
RP2350: r4, r9, r10, r11, r8, r5 and the dispatch table base in r6 (r6 is left free in `i8080_lib.pico2`). The
compiler proves every library and procedure leaves them alone (PM1126). A
procedure that calls into the core must not keep its own locals or
parameters live across that call (they would be placed in r4-r7): use
Globals there, as the demo and diagnostics do. One CPU instance, one core.

**Flags are lazy.** FR holds the last result byte (S, Z and P are derived
from it when needed), CY is bit 8 of FC and AC is bit 4 of FA; POP PSW encodes
any flag combination, even S and Z together. Read them with `CpuFlags()`.

## Compatibility

All 256 opcodes, including the twelve undocumented duplicates: `$08 $10 $18
$20 $28 $30 $38` NOP, `$CB` JMP, `$D9` RET, `$DD $ED $FD` CALL. Exact S, Z, P,
CY and AC for every instruction, including the 8080's AC rules for ANA/ANI
(OR of operand bit 3), SUB/SBB/CMP (inverted borrow), INR/DCR, and DAA. 16-bit
wrap of PC, SP and address arithmetic (LHLD/SHLD at $FFFF, PUSH at $0000).
Self-modifying code works.

Not modelled: bus cycles inside an instruction, the 8080's state during
power-on, interrupt opcodes other than RST, the 8085's extra instructions,
and anything outside the CPU.

## Verification on the board

Everything below ran on the physical boards; the expected values come from
the published reference, not from a model of this core.

**CP/M diagnostics** under a BDOS stub laid out exactly as the reference
harness (`OUT 0` at $0000 ends a program, `OUT 1` / `RET` at $0005 is the
BDOS), so every count must match the reference to the instruction or cycle:

| Program | Instructions | Cycles |
|---|---:|---:|
| TST8080 | 651 | 4,924 |
| 8080PRE | 1,061 | 7,817 |
| CPUTEST | 33,971,311 | 255,653,383 |
| 8080EXM (25 CRC groups against silicon) | 2,919,050,698 | 23,803,381,171 |

**Directed checks** (8,731 per run): run budgets of 0 and below, HLT in both
timing modes, RST injection and its stack frame, the one-instruction EI
delay, DI, non-RST opcodes refused, IN/OUT through the hooks, `CpuYield`,
every one of the 256 PSW values through `CpuSetFlags`/`CpuFlags` and through
POP PSW / PUSH PSW, all eight conditions of Jcc, Ccc and Rcc under every PSW
(taken and not, with their cycle counts in the timed builds), the twelve
undocumented opcodes, self-modifying code, XTHL/XCHG/SPHL/PCHL and
LHLD/SHLD wrapping at $FFFF, and with the page map: ROM pages, trapped pages
and INR M through both traps.

| Build | Pico W | Pico 2 W |
|---|---|---|
| fast: untimed, assembly tail | all checks, all four programs, instruction counts exact | all checks, all four programs, instruction counts exact |
| timed, assembly tail | all four programs, cycle counts exact (8080EXM 643 s); all checks | - |
| timed + page map, assembly tail | - | all four programs, cycle counts exact (8080EXM 1,160 s); all checks |
| untimed + page map, assembly tail | all checks; TST8080, 8080PRE, CPUTEST exact | - |
| timed, plain PureMetal `Goto` tail | all checks; TST8080, 8080PRE, CPUTEST, cycle counts exact | all four programs, cycle counts exact (8080EXM 943 s); all checks |

**Again on the Pico 2 W with the Thumb-2 handlers (2026-10-25):** the fast
build - all 8,731 checks, all four programs with exact instruction counts
(8080EXM 570 s); the timed build - all 14,875 checks, all four programs with
exact cycle counts (8080EXM 568.5 s); timed + page map - all 14,878 checks,
TST8080, 8080PRE and CPUTEST cycle-exact. The plain-tail build compiles to
the same bytes as the one proven above, and the Pico W's images are
unchanged (`docs/verification-pico2w-*-thumb2.log`).

The Pico W's test slot was limited to 15 minutes, so the
8080EXM runs of its page-map and plain-tail builds were done on the Pico 2 W,
whose builds run the same generated handlers. In the first timed runs two
directed checks failed because the test gave two HLT-terminated programs a
budget of 100, which a timed build counts in cycles and those programs need
126 and 121; the budgets were raised to 1000 and the directed checks
re-run on both boards (`docs/verification-*-timed*.log`). The cycle counts
of all four programs were exact in those runs.

Per-instruction test vectors: no published set exists for the 8080
(SingleStepTests covers the Z80 and 8088 but not the 8080); 8080EXM's CRCs
over every instruction group against real silicon take that role.

The desktop core (below) runs the same four programs with both instruction
and cycle counts exact.

## Files

| Path | What |
|---|---|
| `src/i8080.pico` / `src/i8080.pico2` / `src/i8080_lib.pico2` | The core for RP2040 / RP2350 / RP2350 with large libraries (generated) |
| `src/demo.picow` / `src/demo.pico2w` | Smoke test and four timed instruction mixes |
| `src/io.pico` / `src/io.pico2` | USB serial text helpers for the demo and diagnostics |
| `Diagnostics/verify_body.pico(2)` | The on-board verification program |
| `Diagnostics/verify-{fast,timed,pure}.picow(.pico2w)` | Its three configurations |
| `tools/generate.py`, `tools/t2_handlers.py` | Generate the cores (and the Thumb-2 handlers) and the Pico 2 W programs |
| `tools/fetch_tests.py`, `tools/embed_tests.py` | Fetch (pinned, hashed) and embed the CP/M diagnostics |
| `tools/build.ps1` | Compile; with `-Port` also upload and capture the serial output |
| `tools/board.ps1` | Run a file of `build.ps1` jobs on one board |
| `tools/generate_desktop.py` | Generates the desktop core from the same opcode table |
| `desktop/` | The PureBasic desktop version (see below) |
| `firmware/` | Ready-to-copy images (see [Quick start](#quick-start)) |
| `src/invaders*.picow`, `src/invaders*.pico2w` | The Space Invaders machine: test ROM, demo, your own ROM (`invaders_rom`) |
| `src/invaders.pmi`, `inv_video.pmi`, `inv_app.pmi`, `inv_audio*.pmi` | The machine, the two-core panel driver, the application, sound |
| `docs/` | Raw logs of every measurement and verification run quoted here |
| `demo/` | The PureMetal demo for the Space Invaders board, its assets and its ROMs |
| `machine/` | The machine test ROM and what it must leave in RAM |

## Known limits

- One 8080 per program, on one core: the core keeps its registers in host
  registers for the whole program.
- Not modelled: bus cycles inside an instruction, the power-on state, the
  8085's extra instructions, interrupt opcodes other than RST.
- The Space Invaders machine synthesizes the original's sound effects; it does
  not sample the discrete analogue circuits. It has been verified with this
  project's test ROM and demo, not with the original game's ROM.
- The Pico 2 W build has no sound (no Bluetooth in that build).
- The page map makes every data access a procedure call: about 1% slower on
  typical code, about 50% on memory-heavy code.
- Only boards listed above have been tested.

## Credits and licences

This project is licensed under the [MIT License](LICENSE), Copyright (c) 2026
ajtaji. Everything in the repository is original work: the cores and their
generators, the machine, the test ROM (`machine/invaders_test.rom`, assembled
by `tools/make_test_rom.py`), and the demo with its graphics, font and music
(`demo/`, generated by `tools/make_demo_assets.py`). The demo's ROM chips in
`demo/demo_roms/` are PureMetal Forge's output for `demo/demo.invaders`. The
firmware images contain only this code and PureMetal Forge's own libraries;
the public Pico W images include no radio firmware.

The dispatch design (label table, SRAM run loop, inlined computed-jump tails,
lazy flags, reserved registers) follows the PureMetal 6502 and PDP-11 cores.

**Test programs (not redistributed).** `tools/fetch_tests.py` downloads them
from [superzazu/8080](https://github.com/superzazu/8080) at commit
`274ffd700b81baabea99b0963bc1260b67132185` and checks each by SHA-256:
TST8080 (Microcosm Associates, 1980), CPUTEST (SuperSoft Associates
Diagnostics II, 1981; copyrighted), 8080PRE and 8080EXM (Ian Bartholomew's
8080 port of Frank Cringle's Z80 instruction exerciser, GPL). The reference
instruction and cycle counts are the ones published in that repository's
README. They are ignored by git and never embedded in a committed file.

*Space Invaders* is a trademark of Taito Corporation. This project is not
affiliated with or endorsed by Taito; the name describes the hardware the
machine emulates.
