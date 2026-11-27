from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping


cdef class MapperCPROM(Mapper):
    """
    CPROM mapper (iNES 13).

    The board carries 32 KiB of fixed PRG ROM and 16 KiB of CHR RAM split
    into four 4 KiB pages. PPU $0000-$0FFF is hardwired to page 0; any write
    to $8000-$FFFF selects the page at PPU $1000-$1FFF through bits 0-1.
    Videomation is the only known cartridge on this board, and its register
    writes are subject to bus conflicts.
    Ref: NESdev wiki "CPROM".
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "013"

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        """Map $8000-$FFFF to the fixed 32 KiB PRG ROM window."""
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x8000 <= addr <= 0xFFFF and prg_bytes > 0:
            mapping.success = True
            mapping.addr = (addr & 0x7FFF) % prg_bytes
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        """Latch the low two data bits as the $1000-$1FFF CHR RAM page."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x8000 <= addr <= 0xFFFF:
            self.chr_bank_select = data & 0x03
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        """Map the fixed and switchable 4 KiB CHR RAM pages."""
        cdef PPUReadMapping mapping = PPUReadMapping()

        if addr < 0x2000:
            mapping.success = True
            if addr < 0x1000:
                mapping.addr = addr
            else:
                mapping.addr = self.chr_bank_select * 0x1000 + (addr & 0x0FFF)
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        """CPROM ships only CHR RAM, so both pattern pages accept writes."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        if addr < 0x2000:
            mapping.success = True
            if addr < 0x1000:
                mapping.addr = addr
            else:
                mapping.addr = self.chr_bank_select * 0x1000 + (addr & 0x0FFF)
        return mapping

    cdef uint32_t chr_ram_size(self):
        """CPROM fits 16 KiB of CHR RAM regardless of the iNES header."""
        return 0x4000

    cdef void reset(self):
        """Power-on state: the switchable window shows CHR RAM page 0."""
        self.chr_bank_select = 0
