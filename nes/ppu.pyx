from libc.stdint cimport uint8_t, uint16_t, int16_t
from libc.string cimport memset
import numpy as np
cimport numpy as np

from bus cimport CPUBus
from cartridge cimport Cartridge
from mirror cimport *
from ppu_registers cimport Controller, Mask, Status, LoopRegister, BackgroundShiftRegister
from ppu_sprite cimport *


LOW_NIBBLE = 0
HIGH_NIBBLE = 1

cdef class PPU2C02:
    def __init__(self, bus: CPUBus) -> None:
        self._pattern_table = [[0x00] * 64 * 64] * 2
        self._nametable = [[0x00] * 32 * 32] * 2
        self._palette_table = [0x00] * 32
        
        self._palette_panel = [None] * 4 * 16
        self.screen_width, self.screen_height = 256, 240
        self._screen = np.zeros((self.screen_height,self.screen_width,3)).astype(np.uint8)

        self.PPUSTATUS = Status()
        self.PPUMASK = Mask()
        self.PPUCTRL = Controller()
        self.VRAM_addr = LoopRegister()
        self.temp_VRAM_addr = LoopRegister()

        self.fine_x = 0x00

        self.address_latch = 0x00
        self.ppu_data_buffer = 0x00

        self.scanline, self.cycle = 0, 0

        self.background_next_tile_id = 0x00
        self.background_next_tile_attribute = 0x00
        self.background_next_tile_lsb = 0x00
        self.background_next_tile_msb = 0x00
        self.background_pattern_shift_register = BackgroundShiftRegister()
        self.background_attribute_shift_register = BackgroundShiftRegister()

        memset(self.OAM, 0, 64*4*sizeof(uint8_t))
        self.OAMADDR = 0x00
        memset(self.secondary_OAM, 0, 8*4*sizeof(uint8_t))

        memset(self.sprite_pattern_shift_registers, 0, 8 * 2 * sizeof(uint8_t))
        self.eval_sprite0 = False
        self.render_sprite0 = False
        self.nmi = False
        self.frame_complete = False

        self.bus = bus
        self._set_palette_panel()

    cdef void connectCartridge(self, Cartridge cartridge):
        self.cartridge = cartridge   

    cpdef uint8_t[:,:,:] screen(self):
        return self._screen               

    cdef uint8_t readByCPU(self, uint16_t addr , bint readonly):
        data = 0x00

        if readonly:
            if addr == 0x0000:
                # Control
                data = self.PPUCTRL.value
            elif addr == 0x0001:
                # Mask
                data = self.PPUMASK.value
            elif addr == 0x0002:
                # Status
                data = self.PPUSTATUS.value
            elif addr == 0x0003:
                # OAM Address
                pass
            elif addr == 0x0004:
                # OAM Data
                pass
            elif addr == 0x0005:
                # Scroll
                pass
            elif addr == 0x0006:
                # PPU Address
                pass
            elif addr == 0x0007:
                # PPU Data
                pass
        else:
            if addr == 0x0000:
                # Control
                pass
            elif addr == 0x0001:
                # Mask
                pass
            elif addr == 0x0002:
                # Status
                data = (self.PPUSTATUS.value & 0xE0) | (self.ppu_data_buffer & 0x1F)
                self.PPUSTATUS.vertical_blank = 0
                self.address_latch = 0
            elif addr == 0x0003:
                # OAM Address
                pass
            elif addr == 0x0004:
                # OAM Data
                data = self.OAM[self.OAMADDR // 4][self.OAMADDR % 4]
            elif addr == 0x0005:
                # Scroll
                pass
            elif addr == 0x0006:
                # PPU Address
                pass
            elif addr == 0x0007:
                # PPU Data
                data = self.ppu_data_buffer
                self.ppu_data_buffer = self.readByPPU(self.VRAM_addr.value)
                if self.VRAM_addr.value >= 0x3F00:
                    data = self.ppu_data_buffer
                self.VRAM_addr.value += 32 if self.PPUCTRL.increment_mode == 1 else 1
        return data

    cdef void writeByCPU(self, uint16_t addr, uint8_t data):
        if addr == 0x0000:
            # Control
            self.PPUCTRL.value = data
            self.temp_VRAM_addr.nametable_x = self.PPUCTRL.nametable_x
            self.temp_VRAM_addr.nametable_y = self.PPUCTRL.nametable_y
        elif addr == 0x0001:
            # Mask
            self.PPUMASK.value = data
        elif addr == 0x0002:
            # Status
            pass
        elif addr == 0x0003:
            # OAM Address
            self.OAMADDR = data
        elif addr == 0x0004:
            # OAM Data
            self.OAM[self.OAMADDR // 4][self.OAMADDR % 4] = data
        elif addr == 0x0005:
            # Scroll
            if self.address_latch == 0:
                self.fine_x = data & 0x07
                self.temp_VRAM_addr.coarse_x = data >> 3
                self.address_latch = 1
            else:
                self.temp_VRAM_addr.fine_y = data & 0x07
                self.temp_VRAM_addr.coarse_y = data >> 3
                self.address_latch = 0
        elif addr == 0x0006:
            # PPU Address
            if self.address_latch == 0:
                self.temp_VRAM_addr.value = ((data & 0x3F) << 8) | (self.temp_VRAM_addr.value & 0x00FF)
                self.address_latch = 1
            else:
                self.temp_VRAM_addr.value = (self.temp_VRAM_addr.value & 0xFF00) | data
                self.VRAM_addr.value = self.temp_VRAM_addr.value
                self.address_latch = 0
        elif addr == 0x0007:
            # PPU Data
            self.writeByPPU(self.VRAM_addr.value, data)
            self.VRAM_addr.value += 32 if self.PPUCTRL.increment_mode == 1 else 1

    cdef uint8_t readByPPU(self, uint16_t addr):
        addr &= 0x3FFF

        success, data = self.cartridge.readByPPU(addr)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            data = self._pattern_table[(addr & 0x1000) >> 12][addr & 0x0FFF]
        elif 0x2000 <= addr <= 0x3EFF:
            addr &= 0x0FFF
            if self.cartridge.mirror == VERTICAL:
                if 0x0000 <= addr <= 0x03FF:
                    data = self._nametable[0][addr & 0x03FF]
                elif 0x0400 <= addr <= 0x07FF:
                    data = self._nametable[1][addr & 0x03FF]
                elif 0x0800 <= addr <= 0x0BFF:
                    data = self._nametable[0][addr & 0x03FF]
                elif 0x0C00 <= addr <= 0x0FFF:
                    data = self._nametable[1][addr & 0x03FF]                                 
            elif self.cartridge.mirror == HORIZONTAL:
                if 0x0000 <= addr <= 0x03FF:
                    data = self._nametable[0][addr & 0x03FF]
                elif 0x0400 <= addr <= 0x07FF:
                    data = self._nametable[0][addr & 0x03FF]
                elif 0x0800 <= addr <= 0x0BFF:
                    data = self._nametable[1][addr & 0x03FF]
                elif 0x0C00 <= addr <= 0x0FFF:
                    data = self._nametable[1][addr & 0x03FF]
        elif 0x3F00 <= addr <= 0x3FFF:
            addr &= 0x001F
            if addr == 0x0010:
                addr = 0x0000
            if addr == 0x0014:
                addr = 0x0004
            if addr == 0x0018:
                addr = 0x0008
            if addr == 0x001C:
                addr = 0x000C
            data = self._palette_table[addr] & (0x30 if self.PPUMASK.greyscale == 1 else 0x3F)
        return data

    cdef void writeByPPU(self, uint16_t addr, uint8_t data):
        addr &= 0x3FFF     

        success = self.cartridge.writeByPPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            self._pattern_table[(addr & 0x1000) >> 12][addr & 0x0FFF] = data
        elif 0x2000 <= addr <= 0x3EFF:
            addr &= 0x0FFF
            if self.cartridge.mirror == VERTICAL:
                if 0x0000 <= addr <= 0x03FF:
                    self._nametable[0][addr & 0x03FF] = data
                if 0x0400 <= addr <= 0x07FF:
                    self._nametable[1][addr & 0x03FF] = data
                if 0x0800 <= addr <= 0x0BFF:
                    self._nametable[0][addr & 0x03FF] = data
                if 0x0C00 <= addr <= 0x0FFF:
                    self._nametable[1][addr & 0x03FF] = data
            elif self.cartridge.mirror == HORIZONTAL:
                if 0x0000 <= addr <= 0x03FF:
                    self._nametable[0][addr & 0x03FF] = data
                if 0x0400 <= addr <= 0x07FF:
                    self._nametable[0][addr & 0x03FF] = data
                if 0x0800 <= addr <= 0x0BFF:
                    self._nametable[1][addr & 0x03FF] = data
                if 0x0C00 <= addr <= 0x0FFF:
                    self._nametable[1][addr & 0x03FF] = data
        elif 0x3F00 <= addr <= 0x3FFF:
            addr &= 0x001F
            if addr == 0x0010:
                addr = 0x0000
            if addr == 0x0014:
                addr = 0x0004
            if addr == 0x0018:
                addr = 0x0008
            if addr == 0x001C:
                addr = 0x000C
            self._palette_table[addr] = data            

    cdef void _set_palette_panel(self):    
        self._palette_panel[0x00],self._palette_panel[0x01],self._palette_panel[0x02],self._palette_panel[0x03],self._palette_panel[0x04],self._palette_panel[0x05],self._palette_panel[0x06],self._palette_panel[0x07],self._palette_panel[0x08],self._palette_panel[0x09],self._palette_panel[0x0a],self._palette_panel[0x0b],self._palette_panel[0x0c],self._palette_panel[0x0d],self._palette_panel[0x0e],self._palette_panel[0x0f] = ( 84,  84,  84), (  0,  30, 116), (  8,  16, 144), ( 48,   0, 136), ( 68,   0, 100), ( 92,   0,  48), ( 84,   4,   0), ( 60,  24,   0), ( 32,  42,   0), (  8,  58,   0), (  0,  64,   0), (  0,  60,   0), (  0,  50,  60), (  0,   0,   0), (  0,   0,   0), (  0,   0,   0)
        self._palette_panel[0x10],self._palette_panel[0x11],self._palette_panel[0x12],self._palette_panel[0x13],self._palette_panel[0x14],self._palette_panel[0x15],self._palette_panel[0x16],self._palette_panel[0x17],self._palette_panel[0x18],self._palette_panel[0x19],self._palette_panel[0x1a],self._palette_panel[0x1b],self._palette_panel[0x1c],self._palette_panel[0x1d],self._palette_panel[0x1e],self._palette_panel[0x1f] = (152, 150, 152), (  8,  76, 196), ( 48,  50, 236), ( 92,  30, 228), (136,  20, 176), (160,  20, 100), (152,  34,  32), (120,  60,   0), ( 84,  90,   0), ( 40, 114,   0), (  8, 124,   0), (  0, 118,  40), (  0, 102, 120), (  0,   0,   0), (  0,   0,   0), (  0,   0,   0)
        self._palette_panel[0x20],self._palette_panel[0x21],self._palette_panel[0x22],self._palette_panel[0x23],self._palette_panel[0x24],self._palette_panel[0x25],self._palette_panel[0x26],self._palette_panel[0x27],self._palette_panel[0x28],self._palette_panel[0x29],self._palette_panel[0x2a],self._palette_panel[0x2b],self._palette_panel[0x2c],self._palette_panel[0x2d],self._palette_panel[0x2e],self._palette_panel[0x2f] = (236, 238, 236), ( 76, 154, 236), (120, 124, 236), (176,  98, 236), (228,  84, 236), (236,  88, 180), (236, 106, 100), (212, 136,  32), (160, 170,   0), (116, 196,   0), ( 76, 208,  32), ( 56, 204, 108), ( 56, 180, 204), ( 60,  60,  60), (  0,   0,   0), (  0,   0,   0)
        self._palette_panel[0x30],self._palette_panel[0x31],self._palette_panel[0x32],self._palette_panel[0x33],self._palette_panel[0x34],self._palette_panel[0x35],self._palette_panel[0x36],self._palette_panel[0x37],self._palette_panel[0x38],self._palette_panel[0x39],self._palette_panel[0x3a],self._palette_panel[0x3b],self._palette_panel[0x3c],self._palette_panel[0x3d],self._palette_panel[0x3e],self._palette_panel[0x3f] = (236, 238, 236), (168, 204, 236), (188, 188, 236), (212, 178, 236), (236, 174, 236), (236, 174, 212), (236, 180, 176), (228, 196, 144), (204, 210, 120), (180, 222, 120), (168, 226, 144), (152, 226, 180), (160, 214, 228), (160, 162, 160), (  0,   0,   0), (  0,   0,   0)

    cdef tuple fetch_color(self, uint8_t palette, uint8_t pixel):
        color = self.readByPPU(0x3F00 + (palette << 2) + pixel) & 0x3F
        return self._palette_panel[color]

    cdef void reset(self):
        self.fine_x = 0x00
        self.address_latch = 0x00
        self.ppu_data_buffer = 0x00
        self.scanline, self.cycle  = 0, 0
        self.background_next_tile_id = 0x00
        self.background_next_tile_attribute = 0x00
        self.background_next_tile_lsb, self.background_next_tile_msb = 0x00, 0x00
        self.background_pattern_shift_register.reset()
        self.background_attribute_shift_register.reset()

        self.PPUSTATUS.reset()
        self.PPUMASK.reset()
        self.PPUCTRL.reset()
        self.VRAM_addr.reset()
        self.temp_VRAM_addr.reset()

    cdef void _incr_coarseX(self):
        if self.VRAM_addr.coarse_x == 31:
            self.VRAM_addr.coarse_x = 0
            self.VRAM_addr.nametable_x = ~self.VRAM_addr.nametable_x
        else:
            self.VRAM_addr.coarse_x += 1

    cdef void _incr_Y(self):
        if self.VRAM_addr.fine_y < 7:
            self.VRAM_addr.fine_y += 1
        else:
            self.VRAM_addr.fine_y = 0
            if self.VRAM_addr.coarse_y == 29:
                self.VRAM_addr.coarse_y = 0
                self.VRAM_addr.nametable_y = ~self.VRAM_addr.nametable_y
            elif self.VRAM_addr.coarse_y == 31:
                self.VRAM_addr.coarse_y = 0
            else:
                self.VRAM_addr.coarse_y += 1

    cdef void _transfer_X_address(self):
        self.VRAM_addr.nametable_x = self.temp_VRAM_addr.nametable_x
        self.VRAM_addr.coarse_x = self.temp_VRAM_addr.coarse_x

    cdef void _transfer_Y_address(self):
        self.VRAM_addr.fine_y = self.temp_VRAM_addr.fine_y
        self.VRAM_addr.nametable_y = self.temp_VRAM_addr.nametable_y
        self.VRAM_addr.coarse_y = self.temp_VRAM_addr.coarse_y

    cdef void _load_background_shifters(self):
        self.background_pattern_shift_register.low_bits &= 0xFF00
        self.background_pattern_shift_register.low_bits |= self.background_next_tile_lsb

        self.background_pattern_shift_register.high_bits &= 0xFF00
        self.background_pattern_shift_register.high_bits |= self.background_next_tile_msb

        self.background_attribute_shift_register.low_bits &= 0xFF00
        if self.background_next_tile_attribute & 0b01 > 0:
            self.background_attribute_shift_register.low_bits |= 0xFF

        self.background_attribute_shift_register.high_bits &= 0xFF00
        if self.background_next_tile_attribute & 0b10 > 0:
            self.background_attribute_shift_register.high_bits |= 0xFF

    cdef void _reset_sprite_shift_registers(self):
        for i in range(0, 8):
            self.sprite_pattern_shift_registers[i][LOW_NIBBLE] = 0x00
            self.sprite_pattern_shift_registers[i][HIGH_NIBBLE] = 0x00

    cdef void _update_background_shifters(self):
        self.background_pattern_shift_register.low_bits <<= 1
        self.background_pattern_shift_register.high_bits <<= 1
        self.background_attribute_shift_register.low_bits <<= 1
        self.background_attribute_shift_register.high_bits <<= 1

    cdef void _update_sprite_shifters(self):
        for i in range(0, self.sprite_count):
            if self.secondary_OAM[i][X] > 0:
                self.secondary_OAM[i][X] -= 1
            else:
                self.sprite_pattern_shift_registers[i][LOW_NIBBLE] <<= 1
                self.sprite_pattern_shift_registers[i][HIGH_NIBBLE] <<= 1

    cdef void eval_background(self):
        if self.PPUMASK.render_background == 0 and self.PPUMASK.render_sprites == 0:
            return
        if self.PPUMASK.render_background == 1:
            self._update_background_shifters()
        cdef int background_cycle = (self.cycle - 1) % 8
        if background_cycle == 0:
            self._load_background_shifters()
            self.background_next_tile_id = self.fetch_background_tile_id()
        elif background_cycle == 2:
            self.background_next_tile_attribute = self.fetch_background_attribute()
        elif background_cycle == 4:
            self.background_next_tile_lsb = self.fetch_background_tile_nibble(LOW_NIBBLE)
        elif background_cycle == 6:
            self.background_next_tile_msb = self.fetch_background_tile_nibble(HIGH_NIBBLE)
        elif background_cycle == 7:
            if self.cycle != 256:
                self._incr_coarseX()
            else:
                self._incr_Y()

    cdef uint8_t fetch_background_tile_nibble(self, int nibble):
        cdef uint16_t which_pattern_table = self.PPUCTRL.pattern_background
        cdef uint16_t which_tile = self.background_next_tile_id
        cdef uint16_t which_row = self.VRAM_addr.fine_y
        cdef uint16_t offset = 8 if nibble == HIGH_NIBBLE else 0    

        cdef uint16_t background_tile_addr = (which_pattern_table << 12) \
            + (which_tile << 4) \
            + (which_row) \
            + offset
        return self.readByPPU(background_tile_addr)

    cdef uint8_t fetch_background_tile_id(self):
        return self.readByPPU(0x2000 | (self.VRAM_addr.value & 0x0FFF))
    
    cdef uint8_t fetch_background_attribute(self):
        cdef uint8_t attribute = self.readByPPU(0x23C0 \
            | (self.VRAM_addr.nametable_y << 11) \
            | (self.VRAM_addr.nametable_x << 10) \
            | ((self.VRAM_addr.coarse_y >> 2) << 3) \
            | (self.VRAM_addr.coarse_x >> 2))
                
        if self.VRAM_addr.coarse_y & 0x02 > 0:
            attribute >>= 4
        if self.VRAM_addr.coarse_x & 0x02 > 0:
            attribute >>= 2
        attribute &= 0x03
        return attribute

    cdef void eval_sprites(self):
        cdef int16_t y_offset, sprite_height = 16 if self.PPUCTRL.sprite_size == 1 else 8
        self.sprite_count = 0
        self.eval_sprite0 = False
        memset(self.secondary_OAM, 0xFF, 8*4*sizeof(uint8_t))
        self._reset_sprite_shift_registers()
            
        cdef uint8_t nOAMEntry = 0
        for nOAMEntry in range(64):
            y_offset = self.scanline - <int16_t> (self.OAM[nOAMEntry][Y])
            if not (0 <= y_offset < sprite_height):
                continue
            if nOAMEntry == 0:
                self.eval_sprite0 = True
            if self.sprite_count >= 8:
                self.PPUSTATUS.sprite_overflow = 1
                break
            self.secondary_OAM[self.sprite_count][Y] = self.OAM[nOAMEntry][Y]
            self.secondary_OAM[self.sprite_count][ID] = self.OAM[nOAMEntry][ID]
            self.secondary_OAM[self.sprite_count][ATTRIBUTES] = self.OAM[nOAMEntry][ATTRIBUTES]
            self.secondary_OAM[self.sprite_count][X] = self.OAM[nOAMEntry][X]
            self.sprite_count += 1

    cdef void fetch_sprites(self):
        for i in range(0, self.sprite_count):
            self.fetch_sprite(i)    

    cdef void fetch_sprite(self, int i):
        cdef bint vertical_flip_sprite = attribute(self.secondary_OAM[i][ATTRIBUTES], BIT_VERTICAL_FLIP) > 0
        cdef int sprite_height = 16 if self.PPUCTRL.sprite_size == 1 else 8
        cdef uint16_t y_offset = self.scanline - self.secondary_OAM[i][Y]
        if vertical_flip_sprite:
            y_offset = sprite_height - 1 - y_offset
        if y_offset > 7:
            y_offset += 8

        cdef uint16_t which_pattern_table, which_tile
        if self.PPUCTRL.sprite_size == 0:
            # 8x8 Sprite
            which_pattern_table = self.PPUCTRL.pattern_sprite
            which_tile = self.secondary_OAM[i][ID]
        else:
            # 8x16 Sprite
            which_pattern_table = self.secondary_OAM[i][ID] & 0x01
            which_tile = self.secondary_OAM[i][ID] & 0xFE

        cdef uint16_t tile_addr = (which_pattern_table << 12) | (which_tile << 4) | (y_offset)
        cdef uint8_t sprite_pattern_low_bits = self.readByPPU(tile_addr + 0)
        cdef uint8_t sprite_pattern_high_bits = self.readByPPU(tile_addr + 8)
        
        cdef bint horizontal_flip_sprite = attribute(self.secondary_OAM[i][ATTRIBUTES], BIT_HORIZONTAL_FLIP) > 0
        if horizontal_flip_sprite:
            sprite_pattern_low_bits = flipbyte(sprite_pattern_low_bits)
            sprite_pattern_high_bits = flipbyte(sprite_pattern_high_bits)

        self.sprite_pattern_shift_registers[i][LOW_NIBBLE] = sprite_pattern_low_bits
        self.sprite_pattern_shift_registers[i][HIGH_NIBBLE] = sprite_pattern_high_bits 

    cdef tuple draw_background(self):
        if self.PPUMASK.render_background_left == 1 and (self.cycle - 1) < 8:
            return (0x00, 0x00)

        cdef uint16_t bit_mux = 0x8000 >> self.fine_x

        cdef uint8_t background_pixel = 0x00, background_pixel_low_bit = 0x00, background_pixel_high_bit = 0x00
        if (self.background_pattern_shift_register.low_bits & bit_mux) > 0:
            background_pixel_low_bit = 1
        if (self.background_pattern_shift_register.high_bits & bit_mux) > 0:
            background_pixel_high_bit = 1
        background_pixel = (background_pixel_high_bit << 1) | background_pixel_low_bit

        cdef uint8_t background_palette = 0x00, background_palette_low_bit = 0x00, background_palette_high_bit = 0x00
        if (self.background_attribute_shift_register.low_bits & bit_mux) > 0:
            background_palette_low_bit = 1
        if (self.background_attribute_shift_register.high_bits & bit_mux) > 0:
            background_palette_high_bit = 1
        background_palette = (background_palette_high_bit << 1) | background_palette_low_bit

        return (background_palette, background_pixel)

    cdef tuple draw_sprites(self):
        cdef uint8_t foreground_pixel = 0x00, foreground_pixel_low_bit = 0x00, foreground_pixel_high_bit = 0x00
        cdef uint8_t foreground_palette

        cdef int i, sprite_index = 7
        for i in range(0, self.sprite_count):
            if self.secondary_OAM[i][X] == 0:
                if (self.sprite_pattern_shift_registers[i][LOW_NIBBLE] & 0x80) > 0:
                    foreground_pixel_low_bit = 1
                if (self.sprite_pattern_shift_registers[i][HIGH_NIBBLE] & 0x80) > 0:
                    foreground_pixel_high_bit = 1
                foreground_pixel = (foreground_pixel_high_bit << 1) | foreground_pixel_low_bit
                if foreground_pixel != 0:
                    sprite_index = i
                    foreground_palette = attribute(self.secondary_OAM[i][ATTRIBUTES], BIT_PALETTE) + 0x04
                    self.foreground_priority = attribute(self.secondary_OAM[i][ATTRIBUTES], BIT_PRIORITY) == 0
                    break
        self.render_sprite0 = sprite_index == 0
        cdef start_render_position = 8 if self.PPUMASK.render_sprites_left == 1 else 0
        if foreground_pixel == 0 or (self.cycle - 1) < start_render_position:
            return (0x00, 0x00)
        return (foreground_palette, foreground_pixel)

    cdef tuple draw_by_rule(self, uint8_t background_palette, uint8_t background_pixel, uint8_t foreground_palette, uint8_t foreground_pixel):
        cdef uint8_t palette = 0x00, pixel = 0x00
        cdef int16_t start_render_position

        if background_pixel == 0 and foreground_pixel > 0:
            pixel = foreground_pixel
            palette = foreground_palette
        elif background_pixel > 0 and foreground_pixel == 0:
            pixel = background_pixel
            palette = background_palette
        elif background_pixel > 0 and foreground_pixel > 0:
            if self.foreground_priority:
                pixel = foreground_pixel
                palette = foreground_palette
            else:
                pixel = background_pixel
                palette = background_palette

            if (self.PPUMASK.render_background != 0 or self.PPUMASK.render_sprites != 0):              
                if self.eval_sprite0 and self.render_sprite0:
                    start_render_position = 0
                    if self.PPUMASK.render_background_left == 1 or self.PPUMASK.render_sprites_left == 1:
                        start_render_position = 8
                    if start_render_position < self.cycle < 256:
                        self.PPUSTATUS.sprite_zero_hit = 1

        return (palette, pixel)

    cdef void clock(self) except *:
        cdef bint pre_render_scanline = self.scanline == -1 or self.scanline == 261
        cdef bint visible_scanlines = 0 <= self.scanline <= 239
        cdef bint post_render_scanline = self.scanline == 240
        cdef bint vertical_blanking_lines = 241 <= self.scanline <= 260

        if pre_render_scanline:
            if 1 <= self.cycle <= 256:
                self.eval_background()
            elif self.cycle == 257:                
                self._load_background_shifters()
                if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:
                    self._transfer_X_address()
            elif 321 <= self.cycle <= 336: 
                self.eval_background()
            if self.cycle == 340:                
                self.background_next_tile_id = self.fetch_background_tile_id()
                self.background_next_tile_id = self.fetch_background_tile_id()

            if 2 <= self.cycle <= 256:
                if self.PPUMASK.render_sprites == 1:
                    self._update_sprite_shifters()   
            if self.cycle == 340:
                self.fetch_sprites()

            if self.cycle == 1:
                self.PPUSTATUS.vertical_blank = 0
                self.PPUSTATUS.sprite_overflow = 0
                self.PPUSTATUS.sprite_zero_hit = 0
                self._reset_sprite_shift_registers()
            elif 280 <= self.cycle <= 304:
                if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:               
                    self._transfer_Y_address()
        elif visible_scanlines:
            if self.scanline == 0 and self.cycle == 0:
                self.cycle = 1

            if 1 <= self.cycle <= 256:
                self.eval_background()
            elif self.cycle == 257:                
                self._load_background_shifters()
                if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:
                    self._transfer_X_address()
            elif 321 <= self.cycle <= 336: 
                self.eval_background()
            if self.cycle == 340:
                self.background_next_tile_id = self.fetch_background_tile_id()
                self.background_next_tile_id = self.fetch_background_tile_id()

            if 2 <= self.cycle <= 256: 
                if self.PPUMASK.render_sprites == 1:
                    self._update_sprite_shifters()        
            elif self.cycle == 257:
                self.eval_sprites()
            elif self.cycle == 340:
                self.fetch_sprites()        
        elif post_render_scanline:
            pass
        elif vertical_blanking_lines:            
            if self.scanline == 241 and self.cycle == 1:
                self.PPUSTATUS.vertical_blank = 1
                if self.PPUCTRL.enable_nmi == 1:
                    self.nmi = True

        cdef uint8_t background_palette = 0x00, background_pixel = 0x00
        if self.PPUMASK.render_background == 1:
            background_palette, background_pixel = self.draw_background()

        cdef uint8_t foreground_palette = 0x00, foreground_pixel = 0x00
        self.foreground_priority = False
        if self.PPUMASK.render_sprites == 1:
            foreground_palette, foreground_pixel = self.draw_sprites()

        cdef uint8_t pixel = 0x00, palette = 0x00
        palette, pixel = self.draw_by_rule(background_palette, background_pixel, foreground_palette, foreground_pixel)

        if 0 <= self.cycle - 1 < self.screen_width and 0 <= self.scanline < self.screen_height: 
            self._screen[self.scanline][<int>(self.cycle - 1)] = self.fetch_color(palette, pixel)

        self.cycle += 1

        if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:
            if self.cycle == 260 and self.scanline < 240:
                self.cartridge.getMapper().scanline()

        if self.cycle >= 341:
            self.cycle = 0
            self.scanline += 1
            if self.scanline >= 261:
                self.scanline = -1
                self.frame_complete = True
                    