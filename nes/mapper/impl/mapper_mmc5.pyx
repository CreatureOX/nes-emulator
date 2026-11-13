from libc.stdint cimport uint8_t, int8_t, uint16_t, uint32_t, UINT32_MAX

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping
from nes.mapper.mapper cimport PPU_FETCH_OTHER, PPU_FETCH_BACKGROUND
from nes.mapper.mapper cimport PPU_FETCH_SPRITE


cdef class MapperMMC5(Mapper):
    '''
    Nintendo MMC5 / ExROM (iNES 5).

    Four PRG and four CHR banking modes, 1 KB of internal extended RAM,
    an unsigned 8x8 multiplier, a scanline IRQ counter, the four $5105
    nametable windows and fill-mode tile/color substitution. Scanline starts
    are recovered from the PPU's repeated nametable reads rather than from
    a PPU-side hook. In 8x16 sprite mode the fetch context selects the
    sprite ($5120-$5127) or background ($5128-$512B) bank set. Extended
    attributes, vertical split and expansion audio are not implemented.
    Ref: NESdev wiki "MMC5".
    '''
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "005"

    cdef void reset(self):
        '''Apply power-on state; a CPU reset only disables the scanline IRQ.'''
        cdef int i
        if not self.started:
            self.started = True
            self.prg_mode = 3
            self.mul_a = 0xFF
            self.mul_b = 0xFF
            self.last_ppu_addr = 0xFFFF
            self.fetch_kind = PPU_FETCH_OTHER
            for i in range(1, 5):
                self.prg_bank[i] = 0xFF
        else:
            self.irq_enable = False

    cdef void _leave_frame(self):
        '''Drop the in-frame signal and acknowledge a pending scanline IRQ.'''
        self.in_frame = False
        self.irq_pending = False
        self.irq_counter = 0
        self.match_count = 0
        self.last_ppu_addr = 0xFFFF

    cdef void _on_scanline(self):
        '''Advance the IRQ counter once the PPU completes a scanline start.'''
        if not self.in_frame:
            self.in_frame = True
            self.irq_counter = 0
            self.irq_pending = False
            return
        self.irq_counter += 1
        if self.irq_target != 0 and self.irq_counter == self.irq_target:
            self.irq_pending = True
        if self.irq_counter >= 241:
            self._leave_frame()

    cdef void _detect_scanline(self, uint16_t addr):
        '''Recognize two matching nametable reads as a scanline boundary.

        Hardware watches PPU /RD: two identical $2xxx reads mark the end of
        a scanline, and the following read is the next scanline's start.
        Ref: NESdev wiki "MMC5", Scanline Detection and Scanline IRQ.
        '''
        if 0x2000 <= addr <= 0x2FFF and addr == self.last_ppu_addr:
            self.match_count += 1
            if self.match_count == 2:
                self._on_scanline()
        else:
            self.match_count = 0
        self.last_ppu_addr = addr

    cdef bint irq_line(self):
        '''Assert /IRQ only while the pending flag and enable bit are set.'''
        return self.irq_enable and self.irq_pending

    cdef void ppu_fetch_kind(self, uint8_t kind):
        '''Remember whether the PPU is fetching a background or sprite tile.

        The MMC5 watches the PPU address bus to tell the two apart in 8x16
        sprite mode; the renderer supplies that context explicitly here.
        Ref: NESdev wiki "MMC5", CHR Bankswitching ($5120-$5130).
        '''
        self.fetch_kind = kind

    cdef int8_t nametable_source(self, uint16_t addr):
        '''Return the $5105 source selected for this 1 KB nametable window.

        $5105 packs four 2-bit fields for $2000, $2400, $2800 and $2C00;
        PPU $3000-$3EFF repeats the same 4 KB arrangement. Values 0 and 1
        select a CIRAM page, 2 selects ExRAM and 3 selects fill mode.
        Ref: NESdev wiki "MMC5", Nametable mapping ($5105).
        '''
        cdef uint8_t window

        if addr < 0x2000 or addr > 0x3EFF:
            return -1
        window = (addr >> 10) & 0x03
        return <int8_t> ((self.nt_mapping >> (window * 2)) & 0x03)

    cdef uint8_t nametable_read(self, uint16_t addr):
        '''Supply the byte a mapper-owned nametable window exposes.

        Attribute-table bytes occupy the last 64 bytes of each 1 KB window;
        fill mode repeats the two $5107 palette bits across all four indexes.
        ExRAM windows read as zeros once $5104 selects a plain RAM mode.
        Ref: NESdev wiki "MMC5", Fill-mode tile ($5106) and color ($5107).
        '''
        cdef uint16_t offset = addr & 0x03FF
        cdef uint8_t source = <uint8_t> self.nametable_source(addr)
        cdef uint8_t attr

        if source == 2:
            if self.exram_mode >= 2:
                return 0x00
            return self.exram[offset]
        if source == 3:
            if offset >= 0x03C0:
                attr = self.fill_attr & 0x03
                return attr | (attr << 2) | (attr << 4) | (attr << 6)
            return self.fill_tile
        return 0x00

    cdef void nametable_write(self, uint16_t addr, uint8_t data):
        '''Route a PPUDATA write into ExRAM for windows that select it.

        In $5104 modes %10 and %11 ExRAM is not a nametable, so writes there
        are discarded just like reads.
        Ref: NESdev wiki "MMC5", Internal extended RAM mode ($5104).
        '''
        if self.nametable_source(addr) == 2 and self.exram_mode < 2:
            self.exram[addr & 0x03FF] = data

    cdef uint32_t _prg_addr(self, uint16_t addr):
        '''Translate $8000-$FFFF into a PRG ROM offset for the active mode.'''
        cdef uint8_t reg
        cdef uint32_t bank
        cdef uint32_t prg_bytes = self.PRG_banks * 0x4000

        if self.prg_mode == 0:
            reg = self.prg_bank[4]
            bank = (reg & 0x7C) | ((addr >> 13) & 0x03)
        elif self.prg_mode == 1:
            reg = self.prg_bank[2] if addr < 0xC000 else self.prg_bank[4]
            bank = (reg & 0x7E) | ((addr >> 13) & 0x01)
        elif self.prg_mode == 2:
            if addr < 0xC000:
                reg = self.prg_bank[2]
                bank = (reg & 0x7E) | ((addr >> 13) & 0x01)
            elif addr < 0xE000:
                reg = self.prg_bank[3]
                bank = reg & 0x7F
            else:
                reg = self.prg_bank[4]
                bank = reg & 0x7F
        else:
            reg = self.prg_bank[1 + ((addr - 0x8000) >> 13)]
            bank = reg & 0x7F

        if prg_bytes == 0:
            return bank * 0x2000 + (addr & 0x1FFF)
        return (bank * 0x2000 + (addr & 0x1FFF)) % prg_bytes

    cdef uint32_t _chr_addr(self, uint16_t addr):
        '''Translate a pattern-table address through the selected CHR mode.

        Bank registers hold an index in units of the currently selected
        bank size, so their low bits are never discarded. With 8x16 sprites
        and rendering enabled, $5120-$5127 feed sprite fetches and
        $5128-$512B feed background fetches; with 8x8 sprites the second
        set is ignored. PPUDATA always uses the last written set.
        Ref: NESdev wiki "MMC5", CHR Bankswitching ($5120-$5130).
        '''
        cdef uint16_t slot
        cdef uint8_t reg
        cdef uint32_t bank
        cdef uint32_t size
        cdef bint use_b
        cdef uint32_t chr_bytes = self.CHR_banks * 0x2000

        if self.fetch_kind == PPU_FETCH_SPRITE:
            use_b = False
        elif self.fetch_kind == PPU_FETCH_BACKGROUND:
            use_b = self.sprite_8x16 and self.substitutions
        else:
            use_b = self.last_chr_set

        if self.chr_mode == 0:
            size = 0x2000
            reg = self.chr_bank_b[3] if use_b else self.chr_bank_a[7]
        elif self.chr_mode == 1:
            size = 0x1000
            slot = (addr >> 12) & 0x01
            if use_b:
                reg = self.chr_bank_b[3]
            else:
                reg = self.chr_bank_a[3 + 4 * slot]
        elif self.chr_mode == 2:
            size = 0x0800
            slot = (addr >> 11) & 0x03
            if use_b:
                reg = self.chr_bank_b[1 + 2 * (slot & 0x01)]
            else:
                reg = self.chr_bank_a[1 + 2 * slot]
        else:
            size = 0x0400
            slot = (addr >> 10) & 0x07
            if use_b:
                reg = self.chr_bank_b[slot & 0x03]
            else:
                reg = self.chr_bank_a[slot]

        bank = (<uint32_t> self.chr_upper << 8) | <uint32_t> reg
        if chr_bytes > 0:
            return (bank * size + (addr % size)) % chr_bytes
        return (bank * size + (addr % size)) % 0x2000

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        '''Serve status, product and ExRAM registers plus PRG ROM windows.'''
        cdef CPUReadMapping mapping = CPUReadMapping()
        cdef uint16_t product
        cdef uint8_t status

        if addr == 0xFFFA or addr == 0xFFFB:
            self._leave_frame()

        if addr == 0x5204:
            status = (0x80 if self.irq_pending else 0x00)
            status |= 0x40 if self.in_frame else 0x00
            mapping.success = True
            mapping.addr = UINT32_MAX
            mapping.data = status
            self.irq_pending = False
            return mapping
        if addr == 0x5205 or addr == 0x5206:
            product = <uint16_t> self.mul_a * <uint16_t> self.mul_b
            mapping.success = True
            mapping.addr = UINT32_MAX
            if addr == 0x5205:
                mapping.data = <uint8_t> (product & 0x00FF)
            else:
                mapping.data = <uint8_t> (product >> 8)
            return mapping
        if 0x5C00 <= addr <= 0x5FFF and self.exram_mode >= 2:
            mapping.success = True
            mapping.addr = UINT32_MAX
            mapping.data = self.exram[addr - 0x5C00]
            return mapping
        if 0x8000 <= addr <= 0xFFFF:
            mapping.success = True
            mapping.addr = self._prg_addr(addr)
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        '''Decode the MMC5 register block and guard PRG RAM writes.'''
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if addr == 0x2000:
            # Only the fully decoded register is watched; $2008-$200F
            # mirrors are heard by the PPU but not by the MMC5.
            self.sprite_8x16 = (data >> 5) & 0x01
            return mapping
        if addr == 0x2001:
            # Clearing both render bits turns off every data-bus
            # substitution (8x16 banks, extended attributes, split).
            self.substitutions = (data & 0x18) != 0
            if not self.substitutions:
                self._leave_frame()
            return mapping
        if 0x5000 <= addr <= 0x5015:
            return mapping
        if 0x5100 <= addr <= 0x5107:
            if addr == 0x5100:
                self.prg_mode = data & 0x03
            elif addr == 0x5101:
                self.chr_mode = data & 0x03
            elif addr == 0x5102:
                self.protect1 = data & 0x03
            elif addr == 0x5103:
                self.protect2 = data & 0x03
            elif addr == 0x5104:
                self.exram_mode = data & 0x03
            elif addr == 0x5105:
                self.nt_mapping = data
            elif addr == 0x5106:
                self.fill_tile = data
            else:
                self.fill_attr = data & 0x03
            return mapping
        if 0x5113 <= addr <= 0x5117:
            self.prg_bank[addr - 0x5113] = data
            return mapping
        if 0x5120 <= addr <= 0x5127:
            self.chr_bank_a[addr - 0x5120] = data
            self.last_chr_set = False
            return mapping
        if 0x5128 <= addr <= 0x512B:
            self.chr_bank_b[addr - 0x5128] = data
            self.last_chr_set = True
            return mapping
        if addr == 0x5130:
            self.chr_upper = data & 0x03
            return mapping
        if 0x5200 <= addr <= 0x5206:
            if addr == 0x5200:
                self.split_mode = data
            elif addr == 0x5201:
                self.split_scroll = data
            elif addr == 0x5202:
                self.split_bank = data
            elif addr == 0x5203:
                self.irq_target = data
            elif addr == 0x5204:
                self.irq_enable = (data & 0x80) != 0
            elif addr == 0x5205:
                self.mul_a = data
            else:
                self.mul_b = data
            return mapping
        if 0x5C00 <= addr <= 0x5FFF:
            if self.exram_mode == 2 or (self.exram_mode < 2 and self.in_frame):
                self.exram[addr - 0x5C00] = data
            mapping.success = True
            mapping.addr = UINT32_MAX
            return mapping
        if 0x6000 <= addr <= 0x7FFF:
            if self.protect1 != 0x02 or self.protect2 != 0x01:
                mapping.success = True
                mapping.addr = UINT32_MAX
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        '''Watch PPU reads for scanline starts and map pattern-table banks.'''
        cdef PPUReadMapping mapping = PPUReadMapping()

        self._detect_scanline(addr)
        if addr < 0x2000:
            mapping.success = True
            mapping.addr = self._chr_addr(addr)
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        '''Map pattern-table writes into the board's CHR RAM.'''
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        if addr < 0x2000 and self.CHR_banks == 0:
            mapping.success = True
            mapping.addr = self._chr_addr(addr)
        return mapping
