from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HORIZONTAL, VERTICAL


cdef class MapperMMC2(Mapper):
    """
    MMC2 mapper (iNES 9, PxROM), used by Punch-Out!!.

    PRG is one switchable 8 KiB window at $8000-$9FFF and the last three
    8 KiB banks fixed from $A000 upward. CHR is four 4 KiB banks selected
    through two latches: reading the high plane of tile $FD/$FE in a pattern
    table switches the corresponding window on the following fetch, so the
    trigger tile itself still renders from the old bank.

    The low pattern table's latch only reacts to the top row ($0FD8/$0FE8),
    while the high table's latch reacts to every row ($1FDx/$1FEx).
    Ref: NESdev wiki "MMC2", Banks and Registers.
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "009"

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        """Map one switchable 8 KiB PRG window and three fixed tail banks."""
        cdef uint32_t pages = self.PRG_banks * 2
        cdef uint32_t page
        cdef CPUReadMapping mapping = CPUReadMapping()

        if pages < 4 or addr < 0x8000:
            return mapping
        if addr < 0xA000:
            page = self.prg_bank
        elif addr < 0xC000:
            page = pages - 3
        elif addr < 0xE000:
            page = pages - 2
        else:
            page = pages - 1
        mapping.success = True
        mapping.addr = (page % pages) * 0x2000 + (addr & 0x1FFF)
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        """Decode PRG bank, four CHR latch banks and mirroring."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0xA000 <= addr <= 0xAFFF:
            self.prg_bank = data & 0x0F
        elif 0xB000 <= addr <= 0xBFFF:
            self.chr_bank_fd_lo = data & 0x1F
        elif 0xC000 <= addr <= 0xCFFF:
            self.chr_bank_fe_lo = data & 0x1F
        elif 0xD000 <= addr <= 0xDFFF:
            self.chr_bank_fd_hi = data & 0x1F
        elif 0xE000 <= addr <= 0xEFFF:
            self.chr_bank_fe_hi = data & 0x1F
        elif 0xF000 <= addr <= 0xFFFF:
            self.mirroring = HORIZONTAL if (data & 1) else VERTICAL
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        """Resolve a pattern fetch through the current CHR latches."""
        cdef PPUReadMapping mapping = PPUReadMapping()
        cdef uint32_t chr_bytes = self.CHR_banks * 0x2000
        cdef uint8_t page

        if addr >= 0x2000:
            return mapping
        mapping.success = True

        # A trigger is applied on the next pattern fetch: the $FD/$FE tile
        # whose high-plane byte caused it must finish from the old bank.
        if self.pending_lo != 0xFF:
            self.latch_lo = self.pending_lo
            self.pending_lo = 0xFF
        if self.pending_hi != 0xFF:
            self.latch_hi = self.pending_hi
            self.pending_hi = 0xFF

        if addr == 0x0FD8:
            self.pending_lo = 0
        elif addr == 0x0FE8:
            self.pending_lo = 1
        elif 0x1FD8 <= addr <= 0x1FDF:
            self.pending_hi = 0
        elif 0x1FE8 <= addr <= 0x1FEF:
            self.pending_hi = 1

        if chr_bytes == 0:
            mapping.addr = addr
        elif addr < 0x1000:
            page = self.chr_bank_fd_lo if self.latch_lo == 0 else self.chr_bank_fe_lo
            mapping.addr = (page * 0x1000 + (addr & 0x0FFF)) % chr_bytes
        else:
            page = self.chr_bank_fd_hi if self.latch_hi == 0 else self.chr_bank_fe_hi
            mapping.addr = (page * 0x1000 + (addr & 0x0FFF)) % chr_bytes
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        """PxROM boards carry CHR ROM, so pattern writes are rejected."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()
        return mapping

    cdef uint8_t mirror(self):
        """Return the $F000-controlled nametable arrangement."""
        return self.mirroring

    cdef void reset(self):
        """Power-on state: bank 0, $FE latches, vertical mirroring."""
        self.prg_bank = 0
        self.chr_bank_fd_lo = 0
        self.chr_bank_fe_lo = 0
        self.chr_bank_fd_hi = 0
        self.chr_bank_fe_hi = 0
        self.latch_lo = 1
        self.latch_hi = 1
        self.pending_lo = 0xFF
        self.pending_hi = 0xFF
        self.mirroring = VERTICAL
