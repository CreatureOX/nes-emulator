import numpy as np
cimport numpy as np

from nes.mapper.mapper_factory cimport MapperFactory
from nes.mapper.mirror cimport *


cdef class INesCart(Cartridge):
    """
    iNES format cartridge loader.
    
    Parses iNES 1.0 format ROM files and initializes the appropriate mapper.
    Handles PRG ROM, CHR ROM/RAM, trainer data, and PlayChoice10 ROMs.
    """
    def __init__(self, filename) -> None:
        with open(filename, 'rb') as ines:
            self.header = INesHeader(ines.read(16))
            if self.header.flags_6.present_trainer == 1:
                self.trainer = ines.read(512)
            self.PRG_ROM_bytes = 16384 * self.header.PRG_ROM_size
            if self.header.flags_6.present_persistent_memory == 1:
                self.PRG_RAM_bytes = 8192 * self.header.flags_8.PRG_RAM_size    
            self.CHR_ROM_bytes = 8192 * self.header.CHR_ROM_size
            if self.CHR_ROM_bytes == 0:
                self.CHR_RAM_bytes = 8192
            self.PRG_ROM_data = np.frombuffer(ines.read(self.PRG_ROM_bytes), dtype = np.uint8).copy()
            if self.PRG_RAM_bytes > 0:
                self.PRG_RAM_data = np.frombuffer(ines.read(self.PRG_RAM_bytes), dtype = np.uint8).copy()
                if len(self.PRG_RAM_data) == 0:
                    self.PRG_RAM_data = np.zeros(self.PRG_RAM_bytes, dtype = np.uint8)
            if self.CHR_ROM_bytes > 0:
                self.CHR_ROM_data = np.frombuffer(ines.read(self.CHR_ROM_bytes), dtype = np.uint8).copy()
                if len(self.CHR_ROM_data) == 0:
                    self.CHR_ROM_data = np.zeros(self.CHR_ROM_bytes, dtype = np.uint8)
            if self.CHR_RAM_bytes > 0:
                self.CHR_RAM_data = np.frombuffer(ines.read(self.CHR_RAM_bytes), dtype = np.uint8).copy()
                if len(self.CHR_RAM_data) == 0:
                    self.CHR_RAM_data = np.zeros(self.CHR_RAM_bytes, dtype = np.uint8)
            if self.header.flags_7.is_PlayChoice10 == 1:
                self.PlayChoice_INST_ROM = ines.read(8192)
                self.PlayChoice_PROM = ines.read(16)
            self.mapper = MapperFactory.of(self.mapper_no())(self.PRG_ROM_bytes / 16384, self.CHR_ROM_bytes / 8192)
            self.mirror_mode = VERTICAL if self.header.flags_6.nametable_arrangement == 1 else HORIZONTAL

    cdef uint8_t mapper_no(self):
        """Extract the mapper number from header flags 6 and 7."""
        cdef uint8_t lower_nybble = self.header.flags_6.mapper_no_lower_nybble
        cdef uint8_t upper_nybble = self.header.flags_7.mapper_no_upper_nybble
        return (upper_nybble << 4) | lower_nybble

cdef class INesHeader(Header):
    """Parsed iNES header structure (16 bytes)."""
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
    """iNES flags byte 6: mapper and hardware info (lower 4 bits)."""
    def __init__(self, uint8_t value) -> None:
        self.nametable_arrangement = value & 0b1
        self.present_persistent_memory = (value & 0b10) >> 1
        self.present_trainer = (value & 0b100) >> 2
        self.has_alternative_nametable_layout = (value & 0b1000) >> 3
        self.mapper_no_lower_nybble = (value & 0xF0) >> 4

cdef class Flags7:
    """iNES flags byte 7: mapper and hardware info (upper 4 bits)."""
    def __init__(self, uint8_t value) -> None:
        self.has_VS_Unisystem = value & 0b1
        self.is_PlayChoice10 = (value & 0b10) >> 1
        self.is_nes2 = (value & 0b1100) >> 2
        self.mapper_no_upper_nybble = (value & 0xF0) >> 4

cdef class Flags8:
    """iNES flags byte 8: PRG RAM size."""
    def __init__(self, uint8_t value) -> None:
        self.PRG_RAM_size = value

cdef class Flags9:
    """iNES flags byte 9: TV system info."""
    def __init__(self, uint8_t value) -> None:
        self.TV_system = value & 0b1
        self.reserved = 0

cdef class Flags10:
    """iNES flags byte 10: additional TV system and hardware info."""
    def __init__(self, uint8_t value) -> None:
        self.TV_system = value & 0b11
        self.present_PRG_RAM = (value & 0x10) >> 4
        self.has_bus_conflict = (value & 0x20) >> 5