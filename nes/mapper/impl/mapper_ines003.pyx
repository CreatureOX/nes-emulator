from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class MapperINES003(Mapper):
    """
    CNROM-like mapper (mapper 3).
    
    Simple mapper with 2-bit CHR bankswitching. PRG is not bankswitched
    (16KB mirrored for 1 bank, 32KB for 2 banks).
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "003"
        
        self.CHR_bank_select = 0x00    

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        """Map CPU read to PRG ROM (no bankswitching)."""
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x8000 <= addr <= 0xFFFF:
            mapping.success = True
            if self.PRG_banks == 1:
                mapping.addr = addr & 0x3FFF
            if self.PRG_banks == 2:
                mapping.addr = addr & 0x7FFF
        return mapping

    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        """Write to switch CHR bank."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x8000 <= addr <= 0xFFFF:
            self.CHR_bank_select = data & 0x03
            mapping.addr = addr
        return mapping

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        """Map PPU read to CHR bank."""
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        if addr < 0x2000:
            mapping.addr = self.CHR_bank_select * 0x2000 + addr
        return mapping

    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
        """Mapper 3 has no writable CHR."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()
        return mapping

    cdef void reset(self):
        """Reset CHR bank selection to 0."""
        self.CHR_bank_select = 0