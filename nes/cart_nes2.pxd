from libc.stdint cimport uint8_t

from cart cimport Header, Cartridge


cdef class Nes2Cart(Cartridge):
    cdef Nes2Header header

cdef class Nes2Header(Header):
    cdef bytes constant
    cdef uint8_t PRG_ROM_size_LSB
    cdef uint8_t CHR_ROM_size_LSB
    cdef Flags6 flags_6
    cdef Flags7 flags_7
    cdef Flags8 flags_8
    cdef Flags9 flags_9
    cdef Flags10 flags_10
    cdef Flags11 flags_11
    cdef Flags12 flags_12
    cdef Flags13 flags_13
    cdef Flags14 flags_14
    cdef Flags15 flags_15

cdef class Flags6:
    '''
    D~7654 3210
      ---------
      NNNN FTBM
      |||| |||+-- Hard-wired nametable layout
      |||| |||     0: Vertical arrangement ("mirrored horizontally") or mapper-controlled
      |||| |||     1: Horizontal arrangement ("mirrored vertically")
      |||| ||+--- "Battery" and other non-volatile memory
      |||| ||      0: Not present
      |||| ||      1: Present
      |||| |+--- 512-byte Trainer
      |||| |      0: Not present
      |||| |      1: Present between Header and PRG-ROM data
      |||| +---- Alternative nametables
      ||||        0: No
      ||||        1: Yes
      ++++------ Mapper Number D3..D0
    '''
    cdef:
        uint8_t nametable_arrangement
        uint8_t present_persistent_memory
        uint8_t present_trainer
        uint8_t has_alternative_nametable_layout
        uint8_t mapper_no_lower_part

cdef class Flags7:
    '''
    D~7654 3210
      ---------
      NNNN 10TT
      |||| ||++- Console type
      |||| ||     0: Nintendo Entertainment System/Family Computer
      |||| ||     1: Nintendo Vs. System
      |||| ||     2: Nintendo Playchoice 10
      |||| ||     3: Extended Console Type
      |||| ++--- NES 2.0 identifier
      ++++------ Mapper Number D7..D4    
    '''
    cdef:
        uint8_t console_type
        uint8_t is_nes2
        uint8_t mapper_no_middle_part

cdef class Flags8:
    '''
    Mapper MSB/Submapper
    D~7654 3210
      ---------
      SSSS NNNN
      |||| ++++- Mapper number D11..D8
      ++++------ Submapper number
    '''
    cdef:
        uint8_t mapper_no_upper_part
        uint8_t submapper_no

cdef class Flags9:
    '''
    PRG-ROM/CHR-ROM size MSB
    D~7654 3210
      ---------
      CCCC PPPP
      |||| ++++- PRG-ROM size MSB
      ++++------ CHR-ROM size MSB
    '''
    cdef:
        uint8_t PRG_ROM_size_MSB
        uint8_t CHR_ROM_size_MSB

cdef class Flags10:
    '''
    PRG-RAM/EEPROM size
    D~7654 3210
      ---------
      pppp PPPP
      |||| ++++- PRG-RAM (volatile) shift count
      ++++------ PRG-NVRAM/EEPROM (non-volatile) shift count

    If the shift count is zero, there is no PRG-(NV)RAM.
    If the shift count is non-zero, the actual size is
    "64 << shift count" bytes, i.e. 8192 bytes for a shift count of 7.
    '''
    cdef:
        uint8_t PRG_RAM_shift_count
        uint8_t PRG_NVRAM_or_EEPROM_shift_count

cdef class Flags11:
    '''
    CHR-RAM size
    D~7654 3210
      ---------
      cccc CCCC
      |||| ++++- CHR-RAM size (volatile) shift count
      ++++------ CHR-NVRAM size (non-volatile) shift count
    
    If the shift count is zero, there is no CHR-(NV)RAM.
    If the shift count is non-zero, the actual size is
    "64 << shift count" bytes, i.e. 8192 bytes for a shift count of 7.
    '''
    cdef:
        uint8_t CHR_RAM_size_shift_count
        uint8_t CHR_NVRAM_size_shift_count

cdef class Flags12:
    '''
    CPU/PPU Timing
    D~7654 3210
      ---------
      .... ..VV
             ++- CPU/PPU timing mode
                  0: RP2C02 ("NTSC NES")
                  1: RP2C07 ("Licensed PAL NES")
                  2: Multiple-region
                  3: UA6538 ("Dendy")
    '''
    cdef:
        uint8_t timing_mode

cdef class Flags13:
    '''
    When Byte 7 AND 3 =1: Vs. System Type
    D~7654 3210
      ---------
      MMMM PPPP
      |||| ++++- Vs. PPU Type
      ++++------ Vs. Hardware Type

    When Byte 7 AND 3 =3: Extended Console Type
    D~7654 3210
      ---------
      .... CCCC
           ++++- Extended Console Type
    '''
    cdef:
        uint8_t VS_PPU_type
        uint8_t VS_hardware_type

        uint8_t extended_console_type

cdef class Flags14:
    '''
    Miscellaneous ROMs
    D~7654 3210
      ---------
      .... ..RR
             ++- Number of miscellaneous ROMs present
    '''
    cdef uint8_t misc_ROM_number

cdef class Flags15:
    '''
    Default Expansion Device
    D~7654 3210
      ---------
      ..DD DDDD
        ++-++++- Default Expansion Device
    '''
    cdef uint8_t default_expansion_device
