from libc.stdint cimport uint8_t, uint16_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class MapperNROM(Mapper):
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "000"

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        cdef CPUReadMapping mapping = CPUReadMapping()

        mapping.success = 0x8000 <= addr <= 0xFFFF
        mapping.addr = addr & (0x7FFF if self.PRG_banks > 1 else 0x3FFF)
        mapping.data = 0
        return mapping

    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef CPUWriteMapping mapping = CPUWriteMapping()
        
        mapping.success = 0x8000 <= addr <= 0xFFFF
        mapping.addr = addr & (0x7FFF if self.PRG_banks > 1 else 0x3FFF)
        return mapping

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = 0x0000 <= addr <= 0x1FFF
        mapping.addr = addr
        return mapping

    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = 0x0000 <= addr <= 0x1FFF and self.CHR_banks == 0
        mapping.addr = addr
        return mapping