import numpy as np
cimport numpy as np

from mapper_factory cimport MapperFactory
from mirror cimport *


cdef class INesCart(Cartridge):
    def __init__(self, filename) -> None:
        with open(filename, 'rb') as ines:
            self.header = INesHeader(ines.read(16))
            if self.header.flags_6.present_trainer == 1:
                self.trainer = ines.read(512)
            # ROM size
            self.PRG_ROM_bytes = 16384 * self.header.PRG_ROM_size    
            self.CHR_ROM_bytes = 8192 * self.header.CHR_ROM_size
            # ROM
            self.PRG_ROM_data = np.frombuffer(ines.read(self.PRG_ROM_bytes), dtype = np.uint8).copy()
            if self.CHR_ROM_bytes > 0:
                self.CHR_ROM_data = np.frombuffer(ines.read(self.CHR_ROM_bytes), dtype = np.uint8).copy()
            else:
                CHR_data = np.frombuffer(ines.read(8192), dtype = np.uint8).copy()
                if len(CHR_data) == 0:
                    self.CHR_ROM_data = np.array([0x00] * 8192, dtype = np.uint8)
                else:
                    self.CHR_ROM_data = CHR_data

            if self.header.flags_7.is_PlayChoice10 == 1:
                self.PlayChoice_INST_ROM = ines.read(8192)
                self.PlayChoice_PROM = ines.read(16)

            self.mapper = MapperFactory.of(self.mapper_no())(self.header.PRG_ROM_size, self.header.CHR_ROM_size)
            self.mirror_mode = VERTICAL if self.header.flags_6.nametable_arrangement == 1 else HORIZONTAL

    cdef uint8_t mapper_no(self):
        cdef uint8_t lower_nybble = self.header.flags_6.mapper_no_lower_nybble
        cdef uint8_t upper_nybble = self.header.flags_7.mapper_no_upper_nybble
        return (upper_nybble << 4) | lower_nybble

cdef class INesHeader(Header):
    def __init__(self, bytes header_bytes) -> None:
        self.constant = header_bytes[0:4]
        self.PRG_ROM_size = header_bytes[4]
        self.CHR_ROM_size = header_bytes[5]
        self.flags_6 = Flags6(header_bytes[6])
        self.flags_7 = Flags7(header_bytes[7])
        self.flags_8 = Flags8(header_bytes[8])
        self.flags_9 = Flags9(header_bytes[9])
        self.flags_10 = Flags10(header_bytes[10])

cdef class Flags6:
    def __init__(self, uint8_t value) -> None:
        self.nametable_arrangement = value & 0b1
        self.present_persistent_memory = (value & 0b10) >> 1
        self.present_trainer = (value & 0b100) >> 2
        self.has_alternative_nametable_layout = (value & 0b1000) >> 3
        self.mapper_no_lower_nybble = (value & 0xF0) >> 4

cdef class Flags7:
    def __init__(self, uint8_t value) -> None:
        self.has_VS_Unisystem = value & 0b1
        self.is_PlayChoice10 = (value & 0b10) >> 1
        self.is_nes2 = (value & 0b1100) >> 2
        self.mapper_no_upper_nybble = (value & 0xF0) >> 4

cdef class Flags8:
    def __init__(self, uint8_t value) -> None:
        self.PRG_RAM_size = value

cdef class Flags9:
    def __init__(self, uint8_t value) -> None:
        self.TV_system = value & 0b1
        self.reserved = 0

cdef class Flags10:
    def __init__(self, uint8_t value) -> None:
        self.TV_system = value & 0b11
        self.present_PRG_RAM = (value & 0x10) >> 4
        self.has_bus_conflict = (value & 0x20) >> 5
