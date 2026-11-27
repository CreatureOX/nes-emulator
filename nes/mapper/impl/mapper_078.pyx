from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HORIZONTAL, VERTICAL, ONESCREEN_LO, ONESCREEN_HI


cdef class Mapper078(Mapper):
    """
    Irem 74HC161/32 (iNES 78), used by Holy Diver and Cosmo Carrier.

    A single latch at $8000-$FFFF selects a 16 KiB PRG bank at $8000-$BFFF
    (bits 0-2), an 8 KiB CHR bank (bits 4-7) and mirroring (bit 3). The top
    16 KiB of PRG is fixed to the last bank. Bit 3 means H/V on submapper 3
    (Holy Diver) and one-screen A/B on submapper 1 (Cosmo Carrier); iNES
    headers have no submapper, so the default is the one-screen variant.
    Ref: NESdev wiki "INES Mapper 078".
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "078"
        self.submapper = 1

    cdef void set_submapper(self, uint8_t submapper):
        """Record the NES 2.0 submapper; 3 selects the Holy Diver board."""
        self.submapper = submapper

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        """Map the switchable low PRG window and the fixed top 16 KiB."""
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000
        cdef uint32_t bank
        cdef CPUReadMapping mapping = CPUReadMapping()

        if addr < 0x8000 or prg_bytes == 0:
            return mapping
        if addr < 0xC000:
            bank = (self.bank_select & 0x07) * 0x4000
        else:
            bank = prg_bytes - 0x4000
        mapping.success = True
        mapping.addr = bank % prg_bytes + (addr & 0x3FFF)
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        """Latch the PRG bank, CHR bank and mirroring bit."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if addr >= 0x8000:
            self.bank_select = data
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        """Map the 8 KiB CHR bank selected by latch bits 4-7."""
        cdef uint32_t chr_bytes = self.CHR_banks * 0x2000
        cdef PPUReadMapping mapping = PPUReadMapping()

        if addr < 0x2000 and chr_bytes > 0:
            mapping.success = True
            mapping.addr = ((self.bank_select >> 4) * 0x2000
                            % chr_bytes) + addr
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        """Only CHR RAM boards accept pattern-table writes."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = addr < 0x2000 and self.CHR_banks == 0
        mapping.addr = addr
        return mapping

    cdef uint8_t mirror(self):
        """Return the nametable arrangement selected by latch bit 3."""
        cdef uint8_t bit3 = (self.bank_select >> 3) & 0x01

        if self.submapper == 3:
            return VERTICAL if bit3 else HORIZONTAL
        return ONESCREEN_HI if bit3 else ONESCREEN_LO

    cdef void reset(self):
        """Power-on latch is undefined; use bank 0 and nametable 0."""
        self.bank_select = 0
