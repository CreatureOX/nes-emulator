from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HARDWARE, HORIZONTAL, VERTICAL


cdef class MapperVRC2a(Mapper):
    '''
    Konami VRC2a mapper (iNES 22, PCB 351618).

    Two 8 KB switchable PRG banks sit at $8000 and $A000; $C000-$FFFF is
    fixed to the last 16 KB. Eight 1 KB CHR banks are selected by nibble
    pairs at $B000-$EFFF. On this PCB the register-select lines are A1/A0,
    so low/high nibble registers appear at $x001/$x003, and the assembled
    CHR bank value is shifted right one bit.
    Ref: NESdev wiki "VRC2 and VRC4" (VRC2a variations, CHR Select 0/1).
    '''
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "022"
        self.reset()

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        '''Map the two 8 KB switchable PRG banks and the fixed last 16 KB.'''
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000
        cdef CPUReadMapping mapping = CPUReadMapping()

        if prg_bytes < 0x4000:
            return mapping
        if 0x8000 <= addr <= 0x9FFF:
            mapping.success = True
            mapping.addr = (self.prg_bank_0 * 0x2000
                            + (addr & 0x1FFF)) % prg_bytes
        elif 0xA000 <= addr <= 0xBFFF:
            mapping.success = True
            mapping.addr = (self.prg_bank_1 * 0x2000
                            + (addr & 0x1FFF)) % prg_bytes
        elif 0xC000 <= addr <= 0xFFFF:
            mapping.success = True
            mapping.addr = prg_bytes - 0x4000 + (addr & 0x3FFF)
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        '''Decode PRG, mirroring and nibble-pair CHR bank registers.'''
        cdef int group
        cdef int reg
        cdef int index
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x8000 <= addr <= 0x8FFF:
            self.prg_bank_0 = data & 0x1F
        elif 0x9000 <= addr <= 0x9FFF:
            self.mirror_control = data
            self.mirror_written = True
        elif 0xA000 <= addr <= 0xAFFF:
            self.prg_bank_1 = data & 0x1F
        elif 0xB000 <= addr <= 0xEFFF:
            # CPU A0 drives the ASIC A1 select line and CPU A1 drives A0.
            reg = ((addr & 1) << 1) | ((addr >> 1) & 1)
            group = (addr >> 12) - 0xB
            index = group * 2 + (reg >> 1)
            if (reg & 1) == 0:
                self.chr_select[index] = (
                    (self.chr_select[index] & 0xF0) | (data & 0x0F))
            else:
                self.chr_select[index] = (
                    (self.chr_select[index] & 0x0F) | ((data & 0x0F) << 4))
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        '''Map each 1 KB PPU window through its shifted CHR bank value.'''
        cdef uint32_t chr_bytes = self.CHR_banks * 0x2000
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        if mapping.success:
            if chr_bytes > 0:
                mapping.addr = ((self.chr_select[addr >> 10] >> 1) * 0x400
                                + (addr & 0x3FF)) % chr_bytes
            else:
                mapping.addr = addr
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        '''Map PPU pattern-table writes to CHR RAM when no CHR ROM is fitted.'''
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = addr < 0x2000 and self.CHR_banks == 0
        mapping.addr = addr
        return mapping

    cdef uint8_t mirror(self):
        '''Return VRC2 mirroring once the control register has been written.'''
        if not self.mirror_written:
            return HARDWARE
        return HORIZONTAL if (self.mirror_control & 1) else VERTICAL

    cdef void reset(self):
        '''Reset both PRG banks, all CHR banks and the mirror override.'''
        cdef int i
        self.prg_bank_0 = 0
        self.prg_bank_1 = 0
        self.mirror_control = 0
        self.mirror_written = False
        for i in range(8):
            self.chr_select[i] = 0
