from libc.stdint cimport uint8_t, uint16_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class MapperNROM(Mapper):
    """
    NROM mapper (mapper 0).
    
    Simple mapper with no bankswitching. PRG ROM is either 16KB (mirrored to 32KB)
    or 32KB, and CHR is either 8KB ROM or RAM.
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "000"

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        """
        Map CPU read to PRG ROM.
        
        For 16KB banks, address is mirrored. For 32KB banks, full range is used.
        """
        cdef CPUReadMapping mapping = CPUReadMapping()

        mapping.success = 0x8000 <= addr <= 0xFFFF
        mapping.addr = addr & (0x7FFF if self.PRG_banks > 1 else 0x3FFF)
        mapping.data = 0
        return mapping

    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        """NROM has no writable PRG ROM (writes ignored)."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()
        
        mapping.success = 0x8000 <= addr <= 0xFFFF
        mapping.addr = addr & (0x7FFF if self.PRG_banks > 1 else 0x3FFF)
        return mapping

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        """Map PPU read to CHR ROM/RAM."""
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = 0x0000 <= addr <= 0x1FFF
        mapping.addr = addr
        return mapping

    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
        """Map PPU write to CHR RAM (only if no CHR ROM present)."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = 0x0000 <= addr <= 0x1FFF and self.CHR_banks == 0
        mapping.addr = addr
        return mapping