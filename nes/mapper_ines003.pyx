from libc.stdint cimport uint8_t, uint16_t, uint32_t

from mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class MapperINES003(Mapper):
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "003"
        
        self.CHR_bank_select = 0x00    

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x8000 <= addr <= 0xFFFF:
            mapping.success = True
            if self.PRG_banks == 1:
                mapping.addr = addr & 0x3FFF
            if self.PRG_banks == 2:
                mapping.addr = addr & 0x7FFF
        return mapping

    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x8000 <= addr <= 0xFFFF:
            self.CHR_bank_select = data & 0x03
            mapping.addr = addr
        return mapping

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        if addr < 0x2000:
            mapping.addr = self.CHR_bank_select * 0x2000 + addr
        return mapping

    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
        cdef PPUWriteMapping mapping = PPUWriteMapping()
        return mapping

    cdef void reset(self):
        self.CHR_bank_select = 0
