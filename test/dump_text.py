"""Dump the full decoded PPU nametable text for a single ROM (debug aid).

Usage:  python test/dump_text.py <name> [frames]
Reuses judge.py's read/decode helpers so output matches the judge path.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import judge
from judge import read_nametable, decode, FRAMES, PER_ROM


def main(argv):
    if len(argv) < 2:
        print("usage: python test/dump_text.py <name> [frames]")
        return
    tag = argv[1]
    frames = int(argv[2]) if len(argv) > 2 else PER_ROM.get(tag, FRAMES)
    from nes.console import Console
    rom = os.path.join(ROOT, "failed", f"{tag}.nes")
    console = Console(rom)
    console.power_up()
    for f in range(frames):
        console.run()
        if f % 60 == 0:
            console.bus.apu.drain_samples()
    nt = read_nametable(console.bus)
    raw, off = decode(nt)
    print(f"===== {tag}  (frames={frames}) raw decode =====")
    # print in 32-char rows for readability
    for i in range(0, len(raw), 32):
        row = raw[i:i + 32]
        if row.strip():
            print(f"{i // 32:2d}|{row}")
    print(f"===== {tag}  offset(+0x20) decode =====")
    for i in range(0, len(off), 32):
        row = off[i:i + 32]
        if row.strip():
            print(f"{i // 32:2d}|{row}")


if __name__ == "__main__":
    main(sys.argv)
