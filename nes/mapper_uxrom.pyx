from libc.stdint cimport uint8_t, uint16_t

from mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class MapperUxROM(Mapper):
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "002"

        self.PRG_bank_select_lo, self.PRG_bank_select_hi = 0x00, 0x00

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x8000 <= addr <= 0xBFFF:
            mapping.success = True
            mapping.addr = self.PRG_bank_select_lo * 0x4000 + (addr & 0x3FFF)
        if 0xC000 <= addr <= 0xFFFF:
            mapping.success = True
            mapping.addr = self.PRG_bank_select_hi * 0x4000 + (addr & 0x3FFF)
        return mapping

    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x8000 <= addr <= 0xFFFF:
            self.PRG_bank_select_lo = data & 0x0F
        return mapping

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        mapping.addr = addr
        return mapping

    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = addr < 0x2000 and self.CHR_banks == 0
        mapping.addr = addr
        return mapping

    cdef void reset(self):
        self.PRG_bank_select_lo, self.PRG_bank_select_hi = 0, self.PRG_banks - 1
