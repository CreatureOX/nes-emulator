from libc.stdint cimport uint8_t, uint16_t, UINT32_MAX
import numpy as np
cimport numpy as np

from mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class Cartridge:
    def __init__(self, filename: str) -> None:
        cdef uint8_t PRGBanks, CHRBanks
        cdef int INES = 1, NES2 = 2
        
        with open(filename, 'rb') as nes:
            self.header = Header(nes.read(16))

            if self.header.mapper1 & 0b100 != 0:
                self.trainer = nes.read(512)
            
            mapper_no = ((self.header.mapper2 >> 4)) << 4 | (self.header.mapper1 >> 4)
            self.mirror = VERTICAL if self.header.mapper1 & 0x01 else HORIZONTAL
            
            fileType = INES
            if self.header.mapper2 & 0x0C == 0x08:
                fileType = NES2
            
            if fileType == 0:
                pass
            if fileType == INES:
                PRGBanks = self.header.prg_rom_chunks
                self.PRGMemory = np.frombuffer(nes.read(16384 * PRGBanks), dtype=np.uint8).copy()
                
                CHRBanks = self.header.chr_rom_chunks
                if CHRBanks == 0:
                    chrMemory = np.frombuffer(nes.read(8192), dtype=np.uint8).copy()
                    self.CHRMemory = np.array([0x00] * 8192, dtype=np.uint8) if len(chrMemory) == 0 else chrMemory
                else:
                    self.CHRMemory = np.frombuffer(nes.read(8192 * CHRBanks), dtype=np.uint8).copy()
                
                if self.header.mapper2 & 0b10 != 0:
                    self.playChoiceINSTMemory = nes.read(8192)
                    self.playChoicePMemory = nes.read(16)
            if fileType == NES2:
                PRGBanks = (self.header.prg_ram_size & 0x07) << 8 | self.header.prg_rom_chunks
                self.PRGMemory = np.frombuffer(nes.read(16384 * PRGBanks), dtype=np.uint8).copy()

                CHRBanks = (self.header.prg_ram_size & 0x38) << 8 | self.header.chr_rom_chunks
                self.CHRMemory = np.frombuffer(nes.read(8192 * CHRBanks), dtype=np.uint8).copy()

            self.mapper = MapperFactory.of(mapper_no)(PRGBanks, CHRBanks)      

    cdef (bint, uint8_t) readByCPU(self, uint16_t addr):
        cdef CPUReadMapping mapping = self.mapper.mapReadByCPU(addr)

        if mapping.success:
            if mapping.addr == UINT32_MAX:
                return (True, mapping.data)
            else:
                return (True, self.PRGMemory[mapping.addr])
        else:
            return (False, mapping.data)

    cdef bint writeByCPU(self, uint16_t addr, uint8_t data):
        cdef CPUWriteMapping mapping = self.mapper.mapWriteByCPU(addr, data)

        if mapping.success:
            if mapping.addr == UINT32_MAX:
                return True
            else:
               self.PRGMemory[mapping.addr] = data
               return True
        else:
            return False 

    cdef (bint, uint8_t) readByPPU(self, uint16_t addr):
        cdef PPUReadMapping mapping = self.mapper.mapReadByPPU(addr)
        return (mapping.success, self.CHRMemory[mapping.addr] if mapping.success else 0x00)

    cdef bint writeByPPU(self, uint16_t addr, uint8_t data):
        cdef PPUWriteMapping mapping = self.mapper.mapWriteByPPU(addr)

        if mapping.success:
            self.CHRMemory[mapping.addr] = data
        return mapping.success

    cdef void connectBus(self, CPUBus bus):
        self.bus = bus 

    cdef void reset(self):
        if self.mapper is not None:
            self.mapper.reset()

    cdef uint8_t getMirror(self):
        cdef uint8_t m = self.mapper.mirror()
        if m == HARDWARE:
            return self.mirror
        else:
            return m

    cdef Mapper getMapper(self):
        return self.mapper
        