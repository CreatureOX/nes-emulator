from libc.stdint cimport uint8_t

from nes.cart.cart cimport Header, Cartridge


cdef class INesCart(Cartridge):
    cdef INesHeader header
    cdef bytes PlayChoice_INST_ROM
    cdef bytes PlayChoice_PROM

cdef class INesHeader(Header):
    cdef bytes constant
    cdef uint8_t PRG_ROM_size
    cdef uint8_t CHR_ROM_size
    cdef Flags6 flags_6
    cdef Flags7 flags_7
    cdef Flags8 flags_8
    cdef Flags9 flags_9
    cdef Flags10 flags_10

cdef class Flags6:
    '''
    76543210
    ||||||||
    |||||||+- Nametable arrangement: 0: vertical arrangement ("horizontal mirrored") (CIRAM A10 = PPU A11)
    |||||||                          1: horizontal arrangement ("vertically mirrored") (CIRAM A10 = PPU A10)
    ||||||+-- 1: Cartridge contains battery-backed PRG RAM ($6000-7FFF) or other persistent memory
    |||||+--- 1: 512-byte trainer at $7000-$71FF (stored before PRG data)
    ||||+---- 1: Alternative nametable layout
    ++++----- Lower nybble of mapper number
    '''
    cdef:
        uint8_t nametable_arrangement
        uint8_t present_persistent_memory
        uint8_t present_trainer
        uint8_t has_alternative_nametable_layout
        uint8_t mapper_no_lower_nybble

cdef class Flags7:
    '''
    76543210
    ||||||||
    |||||||+- VS Unisystem
    ||||||+-- PlayChoice-10 (8 KB of Hint Screen data stored after CHR data)
    ||||++--- If equal to 2, flags 8-15 are in NES 2.0 format
    ++++----- Upper nybble of mapper number
    '''
    cdef:
        uint8_t has_VS_Unisystem
        uint8_t is_PlayChoice10
        uint8_t is_nes2
        uint8_t mapper_no_upper_nybble

cdef class Flags8:
    '''
    76543210
    ||||||||
    ++++++++- PRG RAM size
    '''
    cdef uint8_t PRG_RAM_size

cdef class Flags9:
    '''
    76543210
    ||||||||
    |||||||+- TV system (0: NTSC; 1: PAL)
    +++++++-- Reserved, set to zero
    '''
    cdef:
        uint8_t TV_system
        uint8_t reserved

cdef class Flags10:
    '''
    76543210
      ||  ||
      ||  ++- TV system (0: NTSC; 2: PAL; 1/3: dual compatible)
      |+----- PRG RAM ($6000-$7FFF) (0: present; 1: not present)
      +------ 0: Board has no bus conflicts; 1: Board has bus conflicts
    '''
    cdef:
        uint8_t TV_system
        uint8_t present_PRG_RAM
        uint8_t has_bus_conflict
