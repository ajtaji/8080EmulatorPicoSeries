# Intel 8080 on the Pico series — PureMetal

A fast Intel 8080 CPU core for the Raspberry Pi Pico W (RP2040) and Pico 2 W
(RP2350), written in PureMetal. The run loop executes from SRAM
(`ProcedureRAM`) and dispatches through a 256-entry `.Label` table; every
opcode handler ends in its own computed-jump tail, so there is no procedure
call per guest instruction. It is a core for a machine to sit on (Space
Invaders, a CP/M system, ...): memory, ports, interrupts and timing are all
reachable through the API below.

<!-- MEASURED -->

## Files

| Path | What |
|---|---|
| `src/i8080.pico` / `src/i8080.pico2` | The core for RP2040 / RP2350 (generated) |
| `src/demo.picow` / `src/demo.pico2w` | Smoke test and four timed instruction mixes |
| `src/io.pico` / `src/io.pico2` | USB serial text helpers for the demo and diagnostics |
| `Diagnostics/verify_body.pico(2)` | The on-board verification program |
| `Diagnostics/verify-{fast,timed,pure}.picow(.pico2w)` | Its three configurations |
| `tools/generate.py` | Generates both cores and the Pico 2 W programs |
| `tools/fetch_tests.py`, `tools/embed_tests.py` | Fetch (pinned, hashed) and embed the CP/M diagnostics |
| `tools/build.ps1` | Compile; with `-Port` take the bench's board lease, upload and capture |
| `tools/board.ps1` | Hold one board lease across a file of `build.ps1` jobs |
| `tools/generate_desktop.py` | Generates the desktop core from the same opcode table |
| `desktop/` | The PureBasic desktop version (see below) |
| `firmware/8080-picow.uf2` | The demo, ready to copy to a Pico W in BOOTSEL |

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
RP2350: r4, r9, r10, r11, r8, r5 and the dispatch table base in r6. The
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

<!-- VERIFIED -->

## Build

```powershell
.\tools\build.ps1                                   # the demo, compile only
.\tools\build.ps1 -Source src/demo.pico2w -Output firmware/8080-pico2w.uf2
```

With `-Port`, `build.ps1` takes the shared bench's lease
(`C:\PMFBuild\board-leases\lease.ps1`) for the upload and capture:

```powershell
.\tools\build.ps1 -Source src/demo.picow -Output firmware/8080-picow.uf2 -Port COM7 -Seconds 20
```

Diagnostics need the test programs first:

```powershell
py -3 tools/fetch_tests.py
py -3 tools/embed_tests.py
.\tools\build.ps1 -Source Diagnostics/verify-fast.picow -Output Diagnostics/verify-fast.uf2 -Port COM7 -Seconds 780
```

Regenerate the cores after editing `tools/generate.py`: `py -3 tools/generate.py`.

## Credits

The dispatch design (label table, SRAM run loop, inlined computed-jump tails,
lazy flags, reserved registers) follows the PureMetal 6502 and PDP-11 cores.
The 8080 semantics and generator are new.

Test programs, fetched from
[superzazu/8080](https://github.com/superzazu/8080) at commit
`274ffd700b81baabea99b0963bc1260b67132185` and checked by SHA-256 (not
redistributed here): TST8080 (Microcosm Associates, 1980), CPUTEST (SuperSoft
Associates Diagnostics II, 1981), 8080PRE and 8080EXM (Ian Bartholomew's 8080
port of Frank Cringle's Z80 exerciser, GPL). The reference instruction and
cycle counts are the ones published in that repository's README.
