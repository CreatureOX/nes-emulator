"""
Objective blargg result reader — dumps PPU nametable as ASCII text.

Blargg test ROMs render text using a font whose CHR tile index equals the
ASCII code, so the nametable bytes ARE the screen text. This avoids any
image/OCR ambiguity: we read the nametable through the real $2006/$2007
register interface (bus.read/write are cpdef → Python-callable).

Usage (from repo root):
    python test/read_screen_text.py <rom-name> [frames]

Prints the visible text rows of nametable $2000.
"""
import os
import sys
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return
    name = argv[1]
    if name.endswith(".nes"):
        name = name[:-4]
    frames = int(argv[2]) if len(argv) > 2 else 1200

    roms = [r for r in glob.glob(os.path.join(ROOT, "failed", "*.nes"))
            if os.path.basename(r)[:-4] == name]
    if not roms:
        print(f"No ROM matching '{name}'")
        return

    from nes.console import Console
    console = Console(roms[0])
    console.power_up()
    for f in range(frames):
        console.frame()
        if f % 60 == 0:
            console.bus.apu.drain_samples()

    bus = console.bus
    # Disable rendering so $2007 reads use the normal +1 increment path.
    bus.write(0x2001, 0x00)
    # Reset the $2005/$2006 write latch.
    bus.read(0x2002, False)
    # Point VRAM address at nametable 0 ($2000).
    bus.write(0x2006, 0x20)
    bus.write(0x2006, 0x00)
    bus.read(0x2007, False)  # prime the buffered read

    rows = []
    for row in range(30):
        chars = []
        for col in range(32):
            b = bus.read(0x2007, False)
            chars.append(chr(b) if 0x20 <= b < 0x7F else " ")
        rows.append("".join(chars).rstrip())

    print(f"--- nametable text: {name} after {frames} frames ---")
    for i, line in enumerate(rows):
        if line.strip():
            print(f"{i:2d}| {line}")
    print("--- end ---")


if __name__ == "__main__":
    main(sys.argv)
