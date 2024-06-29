import numpy as np
cimport numpy as np

from mapper_factory cimport MapperFactory
from mirror cimport *


cdef class Nes2Cart(Cartridge):
    def __init__(self, filename) -> None:
        with open(filename, 'rb') as nes2:
            self.header = Nes2Header(nes2.read(16))
            if self.header.flags_6.present_trainer == 1:
                self.trainer = nes2.read(512)
            # ROM size
            if self.flags_9.PRG_ROM_size_MSB == 0xF:
                multiplier = self.header.PRG_ROM_size_LSB & 0b11
                exponent = (self.header.PRG_ROM_size_LSB & 0xFC) >> 2
                self.PRG_ROM_bytes = (1 << exponent) * (multiplier * 2 + 1)
            else:
                self.PRG_ROM_bytes = 16384 * ((self.flags_9.PRG_ROM_size_MSB << 8) | self.header.PRG_ROM_size_LSB)
            if self.flags_9.CHR_ROM_size_MSB == 0xF:
                multiplier = self.header.CHR_ROM_size_LSB & 0b11
                exponent = (self.header.CHR_ROM_size_LSB & 0xFC) >> 2
                self.CHR_ROM_bytes = (1 << exponent) * (multiplier * 2 + 1)
            else:
                self.CHR_ROM_bytes = 8192 * ((self.flags_9.CHR_ROM_size_MSB << 8) | self.header.CHR_ROM_size_LSB)
            # ROM
            self.PRG_ROM_data = np.frombuffer(nes2.read(self.PRG_ROM_bytes), dtype = np.uint8).copy()
            if self.CHR_ROM_bytes > 0:
                self.CHR_ROM_data = np.frombuffer(nes2.read(self.CHR_ROM_bytes), dtype = np.uint8).copy()
            else:
                CHR_data = np.frombuffer(nes2.read(8192), dtype = np.uint8).copy()
                if len(CHR_data) == 0:
                    self.CHR_ROM_data = np.array([0x00] * 8192, dtype = np.uint8)
                else:
                    self.CHR_ROM_data = CHR_data

            self.mapper = MapperFactory.of(self.mapper_no())(self.PRG_ROM_bytes / 16384, self.CHR_ROM_bytes / 8192)
            self.mirror_mode = VERTICAL if self.header.flags_6.nametable_arrangement == 1 else HORIZONTAL 

    cdef uint8_t mapper_no(self):
        cdef uint8_t lower_part = self.flags_6.mapper_no_lower_part
        cdef uint8_t middle_part = self.flags_7.mapper_no_middle_part
        cdef uint8_t upper_part = self.flags_8.mapper_no_upper_part
        return (upper_part << 8) | (middle_part << 4) | lower_part  
        
cdef class Nes2Header(Header):
    def __init__(self, bytes header_bytes) -> None:
        self.constant = header_bytes[0:4]
        self.PRG_ROM_size_LSB = header_bytes[4]
        self.CHR_ROM_size_LSB = header_bytes[5]
        self.flags_6 = Flags6(header_bytes[6])
        self.flags_7 = Flags7(header_bytes[7])
        self.flags_8 = Flags8(header_bytes[8])
        self.flags_9 = Flags9(header_bytes[9])
        self.flags_10 = Flags10(header_bytes[10])
        self.flags_11 = Flags11(header_bytes[11])  
        self.flags_12 = Flags12(header_bytes[12])  
        self.flags_13 = Flags13(header_bytes[13])  
        self.flags_14 = Flags14(header_bytes[14])
        self.flags_15 = Flags15(header_bytes[15])     

cdef class Flags6:
    def __init__(self, uint8_t value) -> None:
        self.nametable_arrangement = value & 0b1
        self.present_persistent_memory = (value & 0b10) >> 1
        self.present_trainer = (value & 0b100) >> 2
        self.has_alternative_nametable_layout = (value & 0b1000) >> 3
        self.mapper_no_lower_part = (value & 0xF0) >> 4

cdef class Flags7:
    def __init__(self, uint8_t value) -> None:
        self.console_type = value & 0b11
        self.is_nes2 = (value & 0b1100) >> 2
        self.mapper_no_middle_part = (value & 0xF0) >> 4

cdef class Flags8:
    def __init__(self, uint8_t value) -> None:
        self.mapper_no_upper_part = value & 0x0F
        self.submapper_no = (value & 0xF0) >> 4

cdef class Flags9:
    def __init__(self, uint8_t value) -> None:
        self.PRG_ROM_size_MSB = value & 0x0F
        self.CHR_ROM_size_MSB = (value & 0xF0) >> 4

cdef class Flags10:
    def __init__(self, uint8_t value) -> None:
        self.PRG_RAM_shift_count = value & 0x0F
        self.PRG_NVRAM_or_EEPROM_shift_count = (value & 0xF0) >> 4

cdef class Flags11:
    def __init__(self, uint8_t value) -> None:
        self.CHR_RAM_size_shift_count = value & 0x0F
        self.CHR_NVRAM_size_shift_count = (value & 0xF0) >> 4

cdef class Flags12:
    def __init__(self, uint8_t value) -> None:
        self.timing_mode = value & 0b11

cdef class Flags13:
    def __init__(self, uint8_t value) -> None:
        self.VS_PPU_type = 0
        self.VS_hardware_type = 0

        # self.extended_console_type = 0

cdef class Flags14:
    def __init__(self, uint8_t value) -> None:
        self.misc_ROM_number = value & 0b11

cdef class Flags15:
    def __init__(self, uint8_t value) -> None:
        self.default_expansion_device = value & 0x3F
