from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HARDWARE, HORIZONTAL, VERTICAL
from nes.mapper.mirror cimport ONESCREEN_LO, ONESCREEN_HI


cdef class MapperAction53(Mapper):
    '''
    Action 53 multicart mapper (iNES 28).

    $5000-$5FFF selects one of four registers and $8000-$FFFF writes the
    selected value, letting one board emulate NROM, CNROM, UxROM, AxROM and
    BNROM. PRG banking follows the 16 KB bank formula published with the
    mapper spec; the board fits 32 KB CHR RAM in four 8 KB banks and can
    switch all four nametable arrangements.
    Ref: NESdev wiki "Action 53 mapper" and its reference implementation.
    '''
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "028"

    cdef uint32_t chr_ram_size(self):
        '''Return the 32 KB CHR RAM fitted to the board.'''
        return 0x8000

    cdef uint32_t _prg_bank(self, uint16_t addr):
        '''Return the 16 KB PRG bank selected for a CPU address.'''
        cdef uint8_t cpu_a14 = (addr >> 14) & 0x01
        cdef uint32_t outer_bank = <uint32_t> self.outer_bank << 1
        cdef uint8_t bank_mode = self.mode >> 2
        cdef uint32_t current_bank = self.inner_bank
        cdef uint32_t mask

        if (bank_mode ^ cpu_a14) & 0x03 == 0x02:
            bank_mode = 0
        if (bank_mode & 0x02) == 0:
            current_bank = (current_bank << 1) | cpu_a14
        mask = <uint32_t> ((2 << ((bank_mode >> 2) & 0x03)) - 1)
        return (current_bank & mask) | (outer_bank & (0xFFFFFFFF ^ mask))

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        '''Map $8000-$FFFF through the mode, inner and outer bank registers.'''
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x8000 <= addr <= 0xFFFF and prg_bytes > 0:
            mapping.success = True
            mapping.addr = (self._prg_bank(addr) * 0x4000
                            + (addr & 0x3FFF)) % prg_bytes
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        '''Route register-select and register-value writes.'''
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x5000 <= addr <= 0x5FFF:
            self.selected_reg = ((data & 0x80) >> 6) | (data & 0x01)
        elif 0x8000 <= addr <= 0xFFFF:
            if self.selected_reg == 0:
                self.chr_bank = data & 0x03
            elif self.selected_reg == 1:
                self.inner_bank = data & 0x0F
            elif self.selected_reg == 2:
                self.mode = data
                self.mode_written = True
                self.mirror_bit = data & 0x01
            else:
                self.outer_bank = data
            if self.selected_reg < 2 and (self.mode & 0x02) == 0:
                self.mirror_bit = (data >> 4) & 0x01
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        '''Map pattern-table reads to the selected 8 KB CHR bank.'''
        cdef PPUReadMapping mapping = PPUReadMapping()

        mapping.success = addr < 0x2000
        mapping.addr = self.chr_bank * 0x2000 + addr
        if self.CHR_banks > 0:
            mapping.addr %= self.CHR_banks * 0x2000
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        '''Map pattern-table writes to the selected CHR RAM bank.'''
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        mapping.success = addr < 0x2000 and self.CHR_banks == 0
        mapping.addr = self.chr_bank * 0x2000 + addr
        return mapping

    cdef uint8_t mirror(self):
        '''Return the mode register's nametable arrangement.'''
        if not self.mode_written:
            return HARDWARE
        if (self.mode & 0x02) == 0:
            return ONESCREEN_LO if self.mirror_bit == 0 else ONESCREEN_HI
        return HORIZONTAL if (self.mode & 0x01) else VERTICAL

    cdef void reset(self):
        '''Power up in the last 32 KB bank; a later reset keeps mapper state.'''
        if self.started:
            return
        self.started = True
        self.selected_reg = 0
        self.chr_bank = 0
        self.inner_bank = 0
        self.mode = 0
        self.outer_bank = 0xFF
        self.mirror_bit = 0
        self.mode_written = False
