from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping


cdef class MapperColorDreams(Mapper):
    '''
    Color Dreams mapper (iNES 11).

    One latch at $8000-$FFFF selects a 32 KB PRG bank with bits 0-1 and an
    8 KB CHR bank with bits 4-7. Bits 2-3 drive the CIC lockout defeat and
    are ignored. Mirroring is fixed by solder pads.
    Ref: NESdev wiki "Color Dreams" (Bank select $8000-$FFFF).
    '''
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "011"
        self.bank_register = 0x00

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        '''Map $8000-$FFFF to the selected 32 KB PRG ROM bank.'''
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x8000 <= addr <= 0xFFFF and prg_bytes > 0:
            mapping.success = True
            mapping.addr = ((self.bank_register & 0x03) * 0x8000
                            + (addr & 0x7FFF)) % prg_bytes
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        '''Latch PRG and CHR banks on any $8000-$FFFF write.'''
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x8000 <= addr <= 0xFFFF:
            self.bank_register = data
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        '''Map pattern-table reads to the selected 8 KB CHR ROM bank.'''
        cdef uint32_t chr_bytes = self.CHR_banks * 0x2000
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        if mapping.success:
            if chr_bytes > 0:
                mapping.addr = ((self.bank_register >> 4) * 0x2000
                                + addr) % chr_bytes
            else:
                mapping.addr = addr
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        '''Map pattern-table writes to CHR RAM when no CHR ROM is fitted.'''
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = addr < 0x2000 and self.CHR_banks == 0
        mapping.addr = addr
        return mapping

    cdef void reset(self):
        '''Reset the latch to PRG bank 0 and CHR bank 0.'''
        self.bank_register = 0
