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
    attributes and expansion audio (PCM) are implemented; vertical split
    mode is implemented. Ref: NESdev wiki "MMC5".
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
            self.pcm_data = 0
            self.pcm_control = 0
            self.pcm_channel_enable = False
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
        select a CIRAM page, 2 selects ExRAM and 3 selects fill mode. While
        vertical split is active the columns inside the split region draw from
        ExRAM regardless of $5105, so they are reported as an ExRAM window
        for that fetch only. Ref: NESdev wiki "MMC5", Nametable mapping
        ($5105) and Vertical split screen.
        '''
        cdef uint8_t window

        if addr < 0x2000 or addr > 0x3EFF:
            return -1
        if self._in_split_for_col(addr & 0x1F):
            return 2
        window = (addr >> 10) & 0x03
        return <int8_t> ((self.nt_mapping >> (window * 2)) & 0x03)

    cdef uint8_t nametable_read(self, uint16_t addr):
        '''Supply the byte a mapper-owned nametable window exposes.

        Attribute-table bytes occupy the last 64 bytes of each 1 KB window;
        fill mode repeats the two $5107 palette bits across all four indexes.
        ExRAM windows read as zeros once $5104 selects a plain RAM mode.
        Inside the vertical-split region the byte comes from ExRAM at a
        split-scrolled vertical row, matching the FCEUX MMC5 hook.
        Ref: NESdev wiki "MMC5", Fill-mode tile ($5106) and color ($5107);
        Vertical split screen.
        '''
        cdef uint16_t offset = addr & 0x03FF
        cdef uint8_t source = <uint8_t> self.nametable_source(addr)
        cdef uint8_t attr
        cdef uint16_t a
        cdef int linetile

        if source == 2:
            if self._in_split_for_col(addr & 0x1F):
                # Vertical split: the nametable/attribute byte is read from
                # ExRAM at a vertical position scrolled by $5201. The current
                # column (addr & 0x1F) and nametable select are kept; only the
                # vertical tile index is replaced by the split-scrolled row.
                a = addr & 0x3FFF
                linetile = ((<int>self.bg_scanline) - 1) // 8 \
                    + (<int>((self.split_scroll >> 3) & 0x1F))
                if (a & 0x3FF) >= 0x3C0:
                    a &= ~(0x1C << 1)
                    a |= (linetile & 0x1C) << 1
                else:
                    a &= ~((0x1F << 5) | (1 << 0xB))
                    a |= (linetile & 31) << 5
                return self.exram[a & 0x3FF]
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

    cdef int background_attribute(self, uint16_t nt_addr):
        '''Per-tile palette from ExRAM in extended-attribute mode ($5104=%01).

        Each ExRAM byte at the matching nametable address holds "AACC CCCC";
        the AA bits (7-6) are the palette for that background tile. Returns
        -1 when extended attributes are off (or a split region overrides the
        attribute source) so the PPU uses its attribute table as usual.
        Ref: NESdev wiki "MMC5", Extended attributes.
        '''
        if self._in_split():
            return -1
        if self.exram_mode == 1 and self.substitutions:
            return (self.exram[nt_addr & 0x03FF] >> 6) & 0x03
        return -1

    cdef int expansion_audio_sample(self):
        '''MMC5 PCM level for the APU mix, or 0 when disabled.

        The PCM channel is a single 8-bit DAC: $5010 bit 7 enables it, $5015
        bit 3 is the APU channel enable and $5011 holds the sample level that
        is output directly. The level is mixed only while both enables are set
        and the value is non-zero. Ref: NESdev wiki "MMC5", Expansion audio.
        '''
        if (self.pcm_control & 0x80) and self.pcm_channel_enable \
                and self.pcm_data != 0:
            return <int> self.pcm_data
        return 0

    cdef bint _in_split_for_col(self, int ht):
        '''True when column `ht` (0-31) lies inside the vertical split region.

        Vertical split ($5200) only engages while rendering is on, the CHR
        mode is not 1 KB ($5101 bit 1 clear) and bit 7 of $5200 enables it.
        The split covers columns below $5200[0:5] on the left side (bit 6
        clear) or at or above it on the right side (bit 6 set). The column is
        taken from the read's own PPU address so the test is exact for every
        nametable/pattern fetch. Ref: NESdev wiki "MMC5", Vertical split
        screen.
        '''
        cdef int target, side
        if not ((self.split_mode & 0x80) != 0
                and (self.chr_mode & 0x02) == 0
                and self.substitutions):
            return False
        target = self.split_mode & 0x1F
        side = self.split_mode & 0x40
        if side == 0:
            return (ht & 0x1F) < target
        return (ht & 0x1F) >= target

    cdef bint _in_split(self):
        '''Convenience split test for the tracked background fetch column.'''
        return self._in_split_for_col(self.bg_tile_x & 0x1F)

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
        cdef uint8_t ex
        cdef uint32_t bank
        cdef uint32_t size
        cdef bint use_b
        cdef uint32_t chr_bytes = self.CHR_banks * 0x2000

        # Vertical split: a background fetch inside the split region always
        # pulls its pattern from the fixed 4 KB bank in $5202, superseding the
        # normal CHR banking (and the extended-attribute CHR source). Sprites
        # and $2007 keep using the normal banks, matching the real MMC5.
        if self.fetch_kind == PPU_FETCH_BACKGROUND and self._in_split():
            return (self.split_bank * 0x1000 + (addr & 0x0FFF)) \
                % (chr_bytes if chr_bytes > 0 else 0x2000)

        # Extended-attribute mode ($5104=%01): the background tile's 4 KB CHR
        # bank comes from ExRAM "AACC CCCC" bits 5-0 plus $5130 bits 6-7
        # (chr_upper), ignoring CHR mode and the $5120-$512B registers.
        # Sprites and $2007 access are unaffected (handled below).
        # Ref: NESdev wiki "MMC5", Extended attributes.
        if self.exram_mode == 1 and self.substitutions \
                and self.fetch_kind == PPU_FETCH_BACKGROUND:
            ex = self.exram[self.bg_nt_addr & 0x03FF]
            bank = (<uint32_t>(ex & 0x3F)) \
                | (<uint32_t>(self.chr_upper & 0x03) << 6)
            return (bank * 0x1000 + (addr & 0x0FFF)) \
                % (chr_bytes if chr_bytes > 0 else 0x2000)

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
            if addr == 0x5010:
                self.pcm_control = data
            elif addr == 0x5011:
                self.pcm_data = data
            elif addr == 0x5015:
                self.pcm_channel_enable = (data & 0x08) != 0
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
