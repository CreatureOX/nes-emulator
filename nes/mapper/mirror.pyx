"""
NES nametable mirroring modes.

HARDWARE: Use hardware's default mirroring
HORIZONTAL: Horizontal mirroring (CVRAM A[11] = PPU A[11])
VERTICAL: Vertical mirroring (CVRAM A[10] = PPU A[11])
ONESCREEN_LO: Fixed to nametable 0
ONESCREEN_HI: Fixed to nametable 1
"""
HARDWARE = 0
HORIZONTAL = 1
VERTICAL = 2
ONESCREEN_LO = 3
ONESCREEN_HI = 4