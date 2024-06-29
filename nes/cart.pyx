from libc.stdint cimport uint8_t, uint16_t, UINT32_MAX

from mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class Header:
    def __init__(self, bytes header_bytes) -> None:
        pass

cdef class Cartridge:
    def __init__(self, filename) -> None:
        pass

    cdef void connect_bus(self, CPUBus bus):
        self.bus = bus 

    cdef void reset(self):
        if self.mapper is None:
            return
        self.mapper.reset()

    cdef uint8_t mapper_no(self):
        pass

    @staticmethod
    def is_nes2(header_bytes: bytes) -> bool:
        word = header_bytes[0:3].decode("UTF-8")
        is_ines_format = word == 'NES' and header_bytes[3] == 0x1A
        is_nes2_format = is_ines_format and header_bytes[7] & 0x0C == 0x08
        return is_nes2_format

    cdef (bint, uint8_t) readByCPU(self, uint16_t addr):
        cdef CPUReadMapping mapping = self.mapper.mapReadByCPU(addr)

        if mapping.success:
            if mapping.addr == UINT32_MAX:
                return (True, mapping.data)
            else:
                return (True, self.PRG_ROM_data[mapping.addr])
        else:
            return (False, mapping.data)   

    cdef bint writeByCPU(self, uint16_t addr, uint8_t data):
        cdef CPUWriteMapping mapping = self.mapper.mapWriteByCPU(addr, data)

        if mapping.success:
            if mapping.addr == UINT32_MAX:
                return True
            else:
               self.PRG_ROM_data[mapping.addr] = data
               return True
        else:
            return False 

    cdef (bint, uint8_t) readByPPU(self, uint16_t addr):
        cdef PPUReadMapping mapping = self.mapper.mapReadByPPU(addr)
        return (mapping.success, self.CHR_ROM_data[mapping.addr] if mapping.success else 0x00)

    cdef bint writeByPPU(self, uint16_t addr, uint8_t data):
        cdef PPUWriteMapping mapping = self.mapper.mapWriteByPPU(addr)

        if mapping.success:
            self.CHR_ROM_data[mapping.addr] = data
        return mapping.success
