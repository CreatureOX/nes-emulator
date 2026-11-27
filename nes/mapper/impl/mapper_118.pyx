from libc.stdint cimport uint8_t, int8_t, uint16_t, uint32_t

from nes.mapper.impl.mapper_mmc3 cimport MapperMMC3
from nes.mapper.mapping cimport PPUReadMapping
from nes.mapper.mirror cimport HARDWARE


cdef class Mapper118(MapperMMC3):
    """
    TKSROM / TLSROM (iNES 118), an MMC3 board variant.

    Banking and the scanline IRQ are plain MMC3. The board rewires CHR A16
    (bit 7 of each $8001 bank value) to CIRAM A10 instead of using the MMC3
    mirroring register, so the four nametable windows each take their CIRAM
    page from the CHR bank register that the MMC3 would select for the same
    PPU address. $A000 writes therefore have no effect.
    Ref: NESdev wiki "INES Mapper 118".
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "118"

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        '''Strip CHR A16: on these boards that line selects a CIRAM page.

        The fitted CHR ROM is 64 KiB, so a $8001 value with bit 7 set would
        otherwise address the second 128 KiB half that is not wired up.
        Ref: NESdev wiki "INES Mapper 118", Bank data ($8001-$9FFF, odd).
        '''
        cdef PPUReadMapping mapping = MapperMMC3.map_ppu_read(self, addr)
        cdef uint32_t chr_bytes = self.CHR_banks * 0x2000

        if mapping.success and chr_bytes > 0:
            mapping.addr %= chr_bytes
        return mapping

    cdef uint8_t mirror(self):
        '''$A000 is bypassed; nametable_source() owns every CIRAM page.'''
        return HARDWARE

    cdef int8_t nametable_source(self, uint16_t addr):
        '''Return the CIRAM page chosen by the matching CHR bank's bit 7.

        With 2 KiB CHR banks at PPU $0000-$0FFF (inversion clear) the R0/R1
        registers own the two 2 KiB nametable halves at $2000-$27FF and
        $2800-$2FFF; with inversion set the R2-R5 registers own the four
        1 KiB windows. PPU $3000-$3EFF mirrors $2000-$2FFF.
        Ref: NESdev wiki "INES Mapper 118", Bank data ($8001-$9FFF, odd).
        '''
        cdef uint8_t window
        cdef uint8_t reg

        if addr < 0x2000 or addr > 0x3EFF:
            return -1
        window = (addr >> 10) & 0x03
        if self.CHR_inversion:
            reg = 2 + window
        else:
            reg = window >> 1
        return <int8_t> ((self.register[reg] >> 7) & 0x01)
