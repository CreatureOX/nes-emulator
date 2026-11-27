from libc.stdint cimport uint8_t, uint16_t, uint32_t, UINT32_MAX

import numpy as np
cimport numpy as np

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HORIZONTAL, VERTICAL


cdef class MapperMMC4(Mapper):
    """
    MMC4 mapper (iNES 10, FxROM), used by the Fire Emblem games.

    The CHR latches and the $B000-$FFFF registers follow MMC2; the PRG
    layout differs, with one switchable 16 KiB window at $8000-$BFFF and
    the last 16 KiB bank fixed from $C000 upward. Both pattern tables
    react to every row of tile $FD/$FE (unlike MMC2's top-row-only low
    table). The board's 8 KiB battery-backed PRG RAM lives at $6000-$7FFF.
    Ref: NESdev wiki "MMC4", Banks and Registers; "MMC2" for the latches.
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "010"
        self.RAM_static = np.zeros(0x2000, dtype=np.uint8)

    cdef object sram(self):
        '''Battery-backed 8 KB PRG RAM at $6000-$7FFF.'''
        return np.asarray(self.RAM_static)

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        """Map one switchable 16 KiB PRG window and a fixed tail bank."""
        cdef uint32_t pages = self.PRG_banks
        cdef uint32_t page
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x6000 <= addr <= 0x7FFF:
            mapping.success = True
            mapping.addr = UINT32_MAX
            mapping.data = self.RAM_static[addr - 0x6000]
            return mapping
        if pages == 0 or addr < 0x8000:
            return mapping
        if addr < 0xC000:
            page = self.prg_bank
        else:
            page = pages - 1
        mapping.success = True
        mapping.addr = (page % pages) * 0x4000 + (addr & 0x3FFF)
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        """Decode PRG bank, four CHR latch banks and mirroring."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x6000 <= addr <= 0x7FFF:
            self.RAM_static[addr - 0x6000] = data
            mapping.addr = UINT32_MAX
            mapping.success = True
        elif 0xA000 <= addr <= 0xAFFF:
            self.prg_bank = data & 0x0F
        elif 0xB000 <= addr <= 0xBFFF:
            self.chr_bank_fd_lo = data & 0x1F
        elif 0xC000 <= addr <= 0xCFFF:
            self.chr_bank_fe_lo = data & 0x1F
        elif 0xD000 <= addr <= 0xDFFF:
            self.chr_bank_fd_hi = data & 0x1F
        elif 0xE000 <= addr <= 0xEFFF:
            self.chr_bank_fe_hi = data & 0x1F
        elif 0xF000 <= addr <= 0xFFFF:
            self.mirroring = HORIZONTAL if (data & 1) else VERTICAL
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        """Resolve a pattern fetch through the current CHR latches."""
        cdef PPUReadMapping mapping = PPUReadMapping()
        cdef uint32_t chr_bytes = self.CHR_banks * 0x2000
        cdef uint8_t page

        if addr >= 0x2000:
            return mapping
        mapping.success = True

        if self.pending_lo != 0xFF:
            self.latch_lo = self.pending_lo
            self.pending_lo = 0xFF
        if self.pending_hi != 0xFF:
            self.latch_hi = self.pending_hi
            self.pending_hi = 0xFF

        if 0x0FD8 <= addr <= 0x0FDF:
            self.pending_lo = 0
        elif 0x0FE8 <= addr <= 0x0FEF:
            self.pending_lo = 1
        elif 0x1FD8 <= addr <= 0x1FDF:
            self.pending_hi = 0
        elif 0x1FE8 <= addr <= 0x1FEF:
            self.pending_hi = 1

        if chr_bytes == 0:
            mapping.addr = addr
        elif addr < 0x1000:
            page = self.chr_bank_fd_lo if self.latch_lo == 0 else self.chr_bank_fe_lo
            mapping.addr = (page * 0x1000 + (addr & 0x0FFF)) % chr_bytes
        else:
            page = self.chr_bank_fd_hi if self.latch_hi == 0 else self.chr_bank_fe_hi
            mapping.addr = (page * 0x1000 + (addr & 0x0FFF)) % chr_bytes
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        """FxROM boards carry CHR ROM, so pattern writes are rejected."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()
        return mapping

    cdef uint8_t mirror(self):
        """Return the $F000-controlled nametable arrangement."""
        return self.mirroring

    cdef void reset(self):
        """Power-on state: bank 0, $FE latches, vertical mirroring."""
        self.prg_bank = 0
        self.chr_bank_fd_lo = 0
        self.chr_bank_fe_lo = 0
        self.chr_bank_fd_hi = 0
        self.chr_bank_fe_hi = 0
        self.latch_lo = 1
        self.latch_hi = 1
        self.pending_lo = 0xFF
        self.pending_hi = 0xFF
        self.mirroring = VERTICAL
