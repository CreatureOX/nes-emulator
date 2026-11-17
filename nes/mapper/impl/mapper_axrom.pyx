from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport ONESCREEN_LO, ONESCREEN_HI


cdef class MapperAxROM(Mapper):
    '''
    AxROM mapper (iNES 7 / AOROM).

    One latch at $8000-$FFFF selects a 32 KB PRG bank with bits 0-2 and one
    of the two nametable pages with bit 4. CHR is a fixed 8 KB RAM window.
    Ref: NESdev wiki "AxROM" (Bank select $8000-$FFFF).
    '''
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "007"
        self.bank_register = 0x00

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        '''Map $8000-$FFFF to the selected 32 KB PRG ROM bank.'''
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x8000 <= addr <= 0xFFFF and prg_bytes > 0:
            mapping.success = True
            mapping.addr = ((self.bank_register & 0x07) * 0x8000
                            + (addr & 0x7FFF)) % prg_bytes
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        '''Latch the PRG bank and nametable page on any $8000-$FFFF write.'''
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x8000 <= addr <= 0xFFFF:
            self.bank_register = data
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        '''Map PPU pattern-table reads to the 8 KB CHR RAM window.'''
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        mapping.addr = addr
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        '''Map PPU pattern-table writes to CHR RAM when no CHR ROM is fitted.'''
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = addr < 0x2000 and self.CHR_banks == 0
        mapping.addr = addr
        return mapping

    cdef uint8_t mirror(self):
        '''Return the single-screen page selected by latch bit 4.'''
        return ONESCREEN_LO if (self.bank_register & 0x10) == 0 else ONESCREEN_HI

    cdef void reset(self):
        '''Reset the latch to PRG bank 0 and nametable page 0.'''
        self.bank_register = 0
