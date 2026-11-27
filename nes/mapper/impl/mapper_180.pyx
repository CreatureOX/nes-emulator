from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HARDWARE


cdef class Mapper180(Mapper):
    """
    Crazy Climber (iNES 180), an inverted UxROM board.

    AND logic fixes the first 16 KiB PRG bank at $8000-$BFFF and puts the
    switchable bank at $C000-$FFFF, the reverse of UxROM. Bits 0-2 of any
    $8000-$FFFF write select that bank; CHR is a fixed 8 KiB RAM window and
    the nametable arrangement is set by solder pads.
    Ref: NESdev wiki "INES Mapper 180".
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "180"

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        """Map the fixed low window and the selected high PRG bank."""
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000
        cdef uint32_t bank
        cdef CPUReadMapping mapping = CPUReadMapping()

        if addr < 0x8000 or prg_bytes == 0:
            return mapping
        if addr < 0xC000:
            bank = 0
        else:
            bank = (self.prg_bank & 0x07) * 0x4000 % prg_bytes
        mapping.success = True
        mapping.addr = bank + (addr & 0x3FFF)
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        """Latch the switchable PRG bank from bits 0-2."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if addr >= 0x8000:
            self.prg_bank = data & 0x07
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        """Map the fixed 8 KiB CHR RAM window."""
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        mapping.addr = addr
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        """CHR RAM accepts pattern-table writes."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = addr < 0x2000 and self.CHR_banks == 0
        mapping.addr = addr
        return mapping

    cdef uint8_t mirror(self):
        """Solder pads own the arrangement; keep the header's default."""
        return HARDWARE

    cdef void reset(self):
        """Power-on bank is undocumented; use bank 0."""
        self.prg_bank = 0
