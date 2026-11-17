from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping


cdef class MapperBNROM(Mapper):
    '''
    BNROM mapper (iNES 34, CHR RAM variant).

    Writes to $8000-$FFFF latch a 32 KB PRG bank. The original board wires
    only two bits, but an 8-bit latch also covers oversized BxROM images.
    CHR is a fixed 8 KB RAM window and mirroring is set by solder pads.
    The NINA-001 board sharing this mapper number uses CHR ROM and a
    different register set; it is not covered here.
    Ref: NESdev wiki "BNROM" (Bank select $8000-$FFFF).
    '''
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "034"
        self.prg_bank = 0x00

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        '''Map $8000-$FFFF to the selected 32 KB PRG ROM bank.'''
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x8000 <= addr <= 0xFFFF and prg_bytes > 0:
            mapping.success = True
            mapping.addr = (self.prg_bank * 0x8000
                            + (addr & 0x7FFF)) % prg_bytes
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        '''Latch the PRG bank on any $8000-$FFFF write.'''
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x8000 <= addr <= 0xFFFF:
            self.prg_bank = data
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        '''Map PPU pattern-table reads to the 8 KB CHR RAM window.'''
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        mapping.addr = addr
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        '''Map PPU pattern-table writes to the 8 KB CHR RAM window.'''
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = addr < 0x2000 and self.CHR_banks == 0
        mapping.addr = addr
        return mapping

    cdef void reset(self):
        '''Reset the latch to PRG bank 0.'''
        self.prg_bank = 0
