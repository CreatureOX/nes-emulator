from libc.stdint cimport uint8_t, uint16_t, int16_t
from libc.string cimport memset
import numpy as np
cimport numpy as np

from bus cimport CPUBus
from cartridge cimport Cartridge
from mirror cimport *
from ppu_registers cimport Controller, Mask, Status, LoopRegister


Y = 0
ID = 1
ATTRIBUTE = 2
X = 3

cdef uint8_t flipbyte(uint8_t b):
    b = (b & 0xF0) >> 4 | (b & 0x0F) << 4
    b = (b & 0xCC) >> 2 | (b & 0x33) << 2
    b = (b & 0xAA) >> 1 | (b & 0x55) << 1
    return b

cdef class PPU2C02:
    def __init__(self, bus: CPUBus) -> None:
        self.patternTable = [[0x00] * 64 * 64] * 2
        self.nameTable = [[0x00] * 32 * 32] * 2
        self.paletteTable = [0x00] * 32
        
        self.palettePanel = [None] * 4 * 16
        self.screenWidth, self.screenHeight = 256, 240
        self.spriteScreen = np.zeros((self.screenHeight,self.screenWidth,3)).astype(np.uint8)
        self.spriteNameTable = [np.zeros((self.screenHeight,self.screenWidth,3)),np.zeros((self.screenHeight,self.screenWidth,3))]
        self.spritePatternTable = [np.zeros((128,128,3)).astype(np.uint8),np.zeros((128,128,3)).astype(np.uint8)]

        self.PPUSTATUS = Status()
        self.PPUMASK = Mask()
        self.PPUCTRL = Controller()
        self.vram_addr = LoopRegister()
        self.tram_addr = LoopRegister()

        self.fine_x = 0x00

        self.address_latch = 0x00
        self.ppu_data_buffer = 0x00

        self.scanline, self.cycle = 0, 0

        self.background_next_tile_id = 0x00
        self.background_next_tile_attribute = 0x00
        self.background_next_tile_lsb = 0x00
        self.background_next_tile_msb = 0x00
        self.background_shifter_pattern_lo = 0x0000
        self.background_shifter_pattern_hi = 0x0000
        self.background_shifter_attribute_lo = 0x0000
        self.background_shifter_attribute_hi = 0x0000

        memset(self.OAM, 0, 64*4*sizeof(uint8_t))
        self.OAMADDR = 0x00
        memset(self.secondary_OAM, 0, 8*4*sizeof(uint8_t))

        self.sprite_shifter_pattern_lo = [0x00] * 8
        self.sprite_shifter_pattern_hi = [0x00] * 8
        self.eval_sprite0 = False
        self.render_sprite0 = False
        self.nmi = False
        self.frame_complete = False

        self.bus = bus
        self.setPalettePanel()    

    cdef void connectCartridge(self, Cartridge cartridge):
        self.cartridge = cartridge   

    cpdef uint8_t[:,:,:] getScreen(self):
        return self.spriteScreen               

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
                self.ppu_data_buffer = self.readByPPU(self.vram_addr.value)
                if self.vram_addr.value >= 0x3F00:
                    data = self.ppu_data_buffer
                self.vram_addr.value += 32 if self.PPUCTRL.increment_mode == 1 else 1
        return data

    cdef void writeByCPU(self, uint16_t addr, uint8_t data):
        if addr == 0x0000:
            # Control
            self.PPUCTRL.value = data
            self.tram_addr.nametable_x = self.PPUCTRL.nametable_x
            self.tram_addr.nametable_y = self.PPUCTRL.nametable_y
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
                self.tram_addr.coarse_x = data >> 3
                self.address_latch = 1
            else:
                self.tram_addr.fine_y = data & 0x07
                self.tram_addr.coarse_y = data >> 3
                self.address_latch = 0
        elif addr == 0x0006:
            # PPU Address
            if self.address_latch == 0:
                self.tram_addr.value = ((data & 0x3F) << 8) | (self.tram_addr.value & 0x00FF)
                self.address_latch = 1
            else:
                self.tram_addr.value = (self.tram_addr.value & 0xFF00) | data
                self.vram_addr.value = self.tram_addr.value
                self.address_latch = 0
        elif addr == 0x0007:
            # PPU Data
            self.writeByPPU(self.vram_addr.value, data)
            self.vram_addr.value += 32 if self.PPUCTRL.increment_mode == 1 else 1

    cdef uint8_t readByPPU(self, uint16_t addr):
        addr &= 0x3FFF

        success, data = self.cartridge.readByPPU(addr)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            data = self.patternTable[(addr & 0x1000) >> 12][addr & 0x0FFF]
        elif 0x2000 <= addr <= 0x3EFF:
            addr &= 0x0FFF
            if self.cartridge.mirror == VERTICAL:
                if 0x0000 <= addr <= 0x03FF:
                    data = self.nameTable[0][addr & 0x03FF]
                elif 0x0400 <= addr <= 0x07FF:
                    data = self.nameTable[1][addr & 0x03FF]
                elif 0x0800 <= addr <= 0x0BFF:
                    data = self.nameTable[0][addr & 0x03FF]
                elif 0x0C00 <= addr <= 0x0FFF:
                    data = self.nameTable[1][addr & 0x03FF]                                 
            elif self.cartridge.mirror == HORIZONTAL:
                if 0x0000 <= addr <= 0x03FF:
                    data = self.nameTable[0][addr & 0x03FF]
                elif 0x0400 <= addr <= 0x07FF:
                    data = self.nameTable[0][addr & 0x03FF]
                elif 0x0800 <= addr <= 0x0BFF:
                    data = self.nameTable[1][addr & 0x03FF]
                elif 0x0C00 <= addr <= 0x0FFF:
                    data = self.nameTable[1][addr & 0x03FF]
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
            data = self.paletteTable[addr] & (0x30 if self.PPUMASK.greyscale == 1 else 0x3F)
        return data

    cdef void writeByPPU(self, uint16_t addr, uint8_t data):
        addr &= 0x3FFF     

        success = self.cartridge.writeByPPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            self.patternTable[(addr & 0x1000) >> 12][addr & 0x0FFF] = data
        elif 0x2000 <= addr <= 0x3EFF:
            addr &= 0x0FFF
            if self.cartridge.mirror == VERTICAL:
                if 0x0000 <= addr <= 0x03FF:
                    self.nameTable[0][addr & 0x03FF] = data
                if 0x0400 <= addr <= 0x07FF:
                    self.nameTable[1][addr & 0x03FF] = data
                if 0x0800 <= addr <= 0x0BFF:
                    self.nameTable[0][addr & 0x03FF] = data
                if 0x0C00 <= addr <= 0x0FFF:
                    self.nameTable[1][addr & 0x03FF] = data
            elif self.cartridge.mirror == HORIZONTAL:
                if 0x0000 <= addr <= 0x03FF:
                    self.nameTable[0][addr & 0x03FF] = data
                if 0x0400 <= addr <= 0x07FF:
                    self.nameTable[0][addr & 0x03FF] = data
                if 0x0800 <= addr <= 0x0BFF:
                    self.nameTable[1][addr & 0x03FF] = data
                if 0x0C00 <= addr <= 0x0FFF:
                    self.nameTable[1][addr & 0x03FF] = data
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
            self.paletteTable[addr] = data            

    cdef void setPalettePanel(self):    
        self.palettePanel[0x00],self.palettePanel[0x01],self.palettePanel[0x02],self.palettePanel[0x03],self.palettePanel[0x04],self.palettePanel[0x05],self.palettePanel[0x06],self.palettePanel[0x07],self.palettePanel[0x08],self.palettePanel[0x09],self.palettePanel[0x0a],self.palettePanel[0x0b],self.palettePanel[0x0c],self.palettePanel[0x0d],self.palettePanel[0x0e],self.palettePanel[0x0f] = ( 84,  84,  84), (  0,  30, 116), (  8,  16, 144), ( 48,   0, 136), ( 68,   0, 100), ( 92,   0,  48), ( 84,   4,   0), ( 60,  24,   0), ( 32,  42,   0), (  8,  58,   0), (  0,  64,   0), (  0,  60,   0), (  0,  50,  60), (  0,   0,   0), (  0,   0,   0), (  0,   0,   0)
        self.palettePanel[0x10],self.palettePanel[0x11],self.palettePanel[0x12],self.palettePanel[0x13],self.palettePanel[0x14],self.palettePanel[0x15],self.palettePanel[0x16],self.palettePanel[0x17],self.palettePanel[0x18],self.palettePanel[0x19],self.palettePanel[0x1a],self.palettePanel[0x1b],self.palettePanel[0x1c],self.palettePanel[0x1d],self.palettePanel[0x1e],self.palettePanel[0x1f] = (152, 150, 152), (  8,  76, 196), ( 48,  50, 236), ( 92,  30, 228), (136,  20, 176), (160,  20, 100), (152,  34,  32), (120,  60,   0), ( 84,  90,   0), ( 40, 114,   0), (  8, 124,   0), (  0, 118,  40), (  0, 102, 120), (  0,   0,   0), (  0,   0,   0), (  0,   0,   0)
        self.palettePanel[0x20],self.palettePanel[0x21],self.palettePanel[0x22],self.palettePanel[0x23],self.palettePanel[0x24],self.palettePanel[0x25],self.palettePanel[0x26],self.palettePanel[0x27],self.palettePanel[0x28],self.palettePanel[0x29],self.palettePanel[0x2a],self.palettePanel[0x2b],self.palettePanel[0x2c],self.palettePanel[0x2d],self.palettePanel[0x2e],self.palettePanel[0x2f] = (236, 238, 236), ( 76, 154, 236), (120, 124, 236), (176,  98, 236), (228,  84, 236), (236,  88, 180), (236, 106, 100), (212, 136,  32), (160, 170,   0), (116, 196,   0), ( 76, 208,  32), ( 56, 204, 108), ( 56, 180, 204), ( 60,  60,  60), (  0,   0,   0), (  0,   0,   0)
        self.palettePanel[0x30],self.palettePanel[0x31],self.palettePanel[0x32],self.palettePanel[0x33],self.palettePanel[0x34],self.palettePanel[0x35],self.palettePanel[0x36],self.palettePanel[0x37],self.palettePanel[0x38],self.palettePanel[0x39],self.palettePanel[0x3a],self.palettePanel[0x3b],self.palettePanel[0x3c],self.palettePanel[0x3d],self.palettePanel[0x3e],self.palettePanel[0x3f] = (236, 238, 236), (168, 204, 236), (188, 188, 236), (212, 178, 236), (236, 174, 236), (236, 174, 212), (236, 180, 176), (228, 196, 144), (204, 210, 120), (180, 222, 120), (168, 226, 144), (152, 226, 180), (160, 214, 228), (160, 162, 160), (  0,   0,   0), (  0,   0,   0)

    cdef tuple getColorFromPaletteTable(self, uint8_t palette, uint8_t pixel):
        color = self.readByPPU(0x3F00 + (palette << 2) + pixel) & 0x3F
        return self.palettePanel[color]          

    cpdef uint8_t[:,:,:] getPatternTable(self, uint8_t i, uint8_t palette):
        cdef uint8_t tileY, tileX, tile_lsb, tile_msb, row, col, pixel
        cdef uint16_t offset

        for tileY in range(0,16):
            for tileX in range(0,16):
                offset = tileY * 256 + tileX * 16
                for row in range(0,8):
                    tile_lsb = self.readByPPU(i * 0x1000 + offset + row + 0x0000)
                    tile_msb = self.readByPPU(i * 0x1000 + offset + row + 0x0008)
                    for col in range(0,8):
                        pixel = (tile_msb & 0x01) << 1 | (tile_lsb & 0x01)
                        tile_lsb, tile_msb = tile_lsb >> 1, tile_msb >> 1
                        self.spritePatternTable[i][tileY * 8 + row,tileX * 8 + (7 - col)] = self.getColorFromPaletteTable(palette, pixel)
        
        return self.spritePatternTable[i]

    cpdef uint8_t[:,:,:] getPalette(self):
        _palette = np.zeros((4,16,3)).astype(np.uint8)
        for x in range(4):
            for y in range(16):
                _palette[x][y][:] = self.palettePanel[x*16+y]
        return _palette

    cdef void reset(self):
        self.fine_x = 0x00
        self.address_latch = 0x00
        self.ppu_data_buffer = 0x00
        self.scanline, self.cycle  = 0, 0
        self.background_next_tile_id = 0x00
        self.background_next_tile_attribute = 0x00
        self.background_next_tile_lsb, self.background_next_tile_msb = 0x00, 0x00
        self.background_shifter_pattern_lo, self.background_shifter_pattern_hi = 0x0000, 0x0000
        self.background_shifter_attribute_lo, self.background_shifter_attribute_hi = 0x0000, 0x0000
        self.PPUSTATUS.value = 0x00
        self.PPUMASK.value = 0x00
        self.PPUCTRL.value = 0x00
        self.vram_addr.value = 0x0000
        self.tram_addr.value = 0x0000

    cdef void incrementScrollX(self):
        if self.vram_addr.coarse_x == 31:
            self.vram_addr.coarse_x = 0
            self.vram_addr.nametable_x = ~self.vram_addr.nametable_x
        else:
            self.vram_addr.coarse_x += 1

    cdef void incrementScrollY(self):
        if self.vram_addr.fine_y < 7:
            self.vram_addr.fine_y += 1
        else:
            self.vram_addr.fine_y = 0
            if self.vram_addr.coarse_y == 29:
                self.vram_addr.coarse_y = 0
                self.vram_addr.nametable_y = ~self.vram_addr.nametable_y
            elif self.vram_addr.coarse_y == 31:
                self.vram_addr.coarse_y = 0
            else:
                self.vram_addr.coarse_y += 1

    cdef void transferAddressX(self):
        self.vram_addr.nametable_x = self.tram_addr.nametable_x
        self.vram_addr.coarse_x = self.tram_addr.coarse_x

    cdef void transferAddressY(self):
        self.vram_addr.fine_y = self.tram_addr.fine_y
        self.vram_addr.nametable_y = self.tram_addr.nametable_y
        self.vram_addr.coarse_y = self.tram_addr.coarse_y

    cdef void loadBackgroundShifters(self):
        self.background_shifter_pattern_lo = ((self.background_shifter_pattern_lo & 0xFF00) | self.background_next_tile_lsb)
        self.background_shifter_pattern_hi = ((self.background_shifter_pattern_hi & 0xFF00) | self.background_next_tile_msb) 
        self.background_shifter_attribute_lo = (self.background_shifter_attribute_lo & 0xFF00) | (0xFF if (self.background_next_tile_attribute & 0b01) > 0 else 0x00)
        self.background_shifter_attribute_hi = (self.background_shifter_attribute_hi & 0xFF00) | (0xFF if (self.background_next_tile_attribute & 0b10) > 0 else 0x00)

    cdef void update_background_shifters(self):
        if self.PPUMASK.render_background == 1:
            self.background_shifter_pattern_lo <<= 1
            self.background_shifter_pattern_hi <<= 1
            self.background_shifter_attribute_lo <<= 1
            self.background_shifter_attribute_hi <<= 1

    cdef void update_sprite_shifters(self):
        if self.PPUMASK.render_sprites == 1:
            for i in range(0, self.sprite_count):
                if self.secondary_OAM[i][X] > 0:
                    self.secondary_OAM[i][X] -= 1
                else:
                    self.sprite_shifter_pattern_lo[i] <<= 1
                    self.sprite_shifter_pattern_hi[i] <<= 1

    cdef void updateShifters(self):
        self.update_background_shifters()
        if 1 <= self.cycle < 258:
            self.update_sprite_shifters()

    cdef void eval_background(self):
        self.updateShifters()
        cdef background_cycle = (self.cycle - 1) % 8
        if background_cycle == 0:
            self.loadBackgroundShifters()
            self.background_next_tile_id = self.fetch_background_tile()
        elif background_cycle == 2:
            self.background_next_tile_attribute = self.fetch_background_attribute()
        elif background_cycle == 4:
            self.background_next_tile_lsb = self.fetch_background(0)
        elif background_cycle == 6:
            self.background_next_tile_msb = self.fetch_background(8)
        elif background_cycle == 7:
            if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:
                self.incrementScrollX()

    cdef uint8_t fetch_background(self, uint16_t offset):
        cdef uint16_t which_pattern_table = self.PPUCTRL.pattern_background
        cdef uint16_t which_tile = self.background_next_tile_id
        cdef uint16_t which_row = self.vram_addr.fine_y    

        cdef uint16_t background_tile_addr = (which_pattern_table << 12) \
            + (which_tile << 4) \
            + (which_row) \
            + offset
        return self.readByPPU(background_tile_addr)

    cdef uint8_t fetch_background_tile(self):
        return self.readByPPU(0x2000 | (self.vram_addr.value & 0x0FFF))
    
    cdef uint8_t fetch_background_attribute(self):
        cdef uint8_t attribute = self.readByPPU(0x23C0 \
            | (self.vram_addr.nametable_y << 11) \
            | (self.vram_addr.nametable_x << 10) \
            | ((self.vram_addr.coarse_y >> 2) << 3) \
            | (self.vram_addr.coarse_x >> 2))
                
        if self.vram_addr.coarse_y & 0x02 > 0:
            attribute >>= 4
        if self.vram_addr.coarse_x & 0x02 > 0:
            attribute >>= 2
        attribute &= 0x03
        return attribute

    cdef void eval_sprites(self):
        memset(self.secondary_OAM, 0xFF, 8*4*sizeof(uint8_t))
        self.sprite_count = 0
        for i in range(0, 8):
            self.sprite_shifter_pattern_lo[i] = 0
            self.sprite_shifter_pattern_hi[i] = 0
            
        cdef uint8_t nOAMEntry = 0
        cdef int16_t y_offset, sprite_height
        self.eval_sprite0 = False
        while nOAMEntry < 64 and self.sprite_count < 9:
            y_offset = self.scanline - <int16_t> (self.OAM[nOAMEntry][0])
            sprite_height = 16 if self.PPUCTRL.sprite_size == 1 else 8
            if 0 <= y_offset < sprite_height:
                if self.sprite_count < 8:
                    if nOAMEntry == 0:
                        self.eval_sprite0 = True
                    self.secondary_OAM[self.sprite_count][Y] = self.OAM[nOAMEntry][Y]
                    self.secondary_OAM[self.sprite_count][ID] = self.OAM[nOAMEntry][ID]
                    self.secondary_OAM[self.sprite_count][ATTRIBUTE] = self.OAM[nOAMEntry][ATTRIBUTE]
                    self.secondary_OAM[self.sprite_count][X] = self.OAM[nOAMEntry][X]
                    self.sprite_count += 1
            nOAMEntry += 1
        self.PPUSTATUS.sprite_overflow = 1 if self.sprite_count > 8 else 0

    cdef void fetch_sprites(self):
        for i in range(0, self.sprite_count):
            self.fetch_sprite(i)    

    cdef void fetch_sprite(self, int i):
        cdef uint16_t which_pattern_table, which_tile, y_offset
        cdef bint is_upper_tile

        cdef bint vertical_flip_sprite = self.secondary_OAM[i][ATTRIBUTE] & 0x80 > 0
        y_offset = self.scanline - self.secondary_OAM[i][Y]
        if self.PPUCTRL.sprite_size == 0:
            # 8x8 Sprite
            which_pattern_table = self.PPUCTRL.pattern_sprite
            which_tile = self.secondary_OAM[i][ID]
            y_offset = (7 - y_offset if vertical_flip_sprite else y_offset) & 0xFFFF
        else:
            # 8x16 Sprite
            which_pattern_table = self.secondary_OAM[i][ID] & 0x01
            which_tile = self.secondary_OAM[i][ID] & 0xFE
            y_offset = (7 - y_offset if vertical_flip_sprite else y_offset) & 0x07
            is_upper_tile = self.scanline - self.secondary_OAM[i][Y] < 8
            which_tile += 0 if not vertical_flip_sprite and is_upper_tile else 1
            which_tile += 1 if vertical_flip_sprite and is_upper_tile else 0

        cdef uint16_t tile_addr = (which_pattern_table << 12) | (which_tile << 4) | (y_offset)
        cdef uint8_t sprite_pattern_bits_lo = self.readByPPU(tile_addr + 0)
        cdef uint8_t sprite_pattern_bits_hi = self.readByPPU(tile_addr + 8)
        
        cdef bint horizontal_flip_sprite = self.secondary_OAM[i][ATTRIBUTE] & 0x40 > 0
        if horizontal_flip_sprite:
            sprite_pattern_bits_lo = flipbyte(sprite_pattern_bits_lo)
            sprite_pattern_bits_hi = flipbyte(sprite_pattern_bits_hi)

        self.sprite_shifter_pattern_lo[i] = sprite_pattern_bits_lo
        self.sprite_shifter_pattern_hi[i] = sprite_pattern_bits_hi 

    cdef tuple draw_background(self):
        cdef uint8_t background_pixel = 0x00, background_pixel_0, background_pixel_1
        cdef uint8_t background_palette = 0x00, background_palette_0, background_palette_1
        cdef uint16_t bit_mux = 0x8000 >> self.fine_x

        background_pixel_0 = 1 if (self.background_shifter_pattern_lo & bit_mux) > 0 else 0
        background_pixel_1 = 1 if (self.background_shifter_pattern_hi & bit_mux) > 0 else 0
        background_pixel = (background_pixel_1 << 1) | background_pixel_0

        background_palette_0 = 1 if (self.background_shifter_attribute_lo & bit_mux) > 0 else 0
        background_palette_1 = 1 if (self.background_shifter_attribute_hi & bit_mux) > 0 else 0
        background_palette = (background_palette_1 << 1) | background_palette_0

        return (background_palette, background_pixel)

    cdef tuple draw_sprites(self):
        cdef uint8_t foreground_pixel = 0x00, foreground_pixel_lo, foreground_pixel_hi
        cdef uint8_t foreground_palette

        self.render_sprite0 = False
        for i in range(0, self.sprite_count):
            if self.secondary_OAM[i][X] == 0:
                foreground_pixel_lo = 1 if (self.sprite_shifter_pattern_lo[i] & 0x80) > 0 else 0
                foreground_pixel_hi = 1 if (self.sprite_shifter_pattern_hi[i] & 0x80) > 0 else 0
                foreground_pixel = (foreground_pixel_hi << 1) | foreground_pixel_lo
                foreground_palette = (self.secondary_OAM[i][ATTRIBUTE] & 0x03) + 0x04
                self.foreground_priority = self.secondary_OAM[i][ATTRIBUTE] & 0x20 == 0

                if foreground_pixel != 0:
                    if i == 0:
                        self.render_sprite0 = True
                    break

        return (foreground_palette, foreground_pixel)

    cdef tuple draw_by_rule(self, uint8_t background_palette, uint8_t background_pixel, uint8_t foreground_palette, uint8_t foreground_pixel):
        cdef uint8_t palette, pixel

        if background_pixel == 0 and foreground_pixel == 0:
            pixel = 0x00
            palette = 0x00
        elif background_pixel == 0 and foreground_pixel > 0:
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
            if self.eval_sprite0 and self.render_sprite0:
                if self.PPUMASK.render_background & self.PPUMASK.render_sprites != 0:
                    if ((self.PPUMASK.render_background_left | self.PPUMASK.render_sprites_left) == 0):
                        if 9 <= self.cycle < 258:
                            self.PPUSTATUS.sprite_zero_hit = 1
                    else:
                        if 1 <= self.cycle < 258:
                            self.PPUSTATUS.sprite_zero_hit = 1

        return (palette, pixel)

    cdef void clock(self) except *:
        cdef bint pre_render_scanline = self.scanline == -1 or self.scanline == 261
        cdef bint visible_scanlines = 0 <= self.scanline <= 239
        cdef bint post_render_scanline = self.scanline == 240
        cdef bint vertical_blanking_lines = 241 <= self.scanline <= 260

        if pre_render_scanline:
            if self.cycle == 1:
                self.PPUSTATUS.vertical_blank = 0
                self.PPUSTATUS.sprite_overflow = 0
                self.PPUSTATUS.sprite_zero_hit = 0
                for i in range(0, 8):
                    self.sprite_shifter_pattern_hi[i] = 0
                    self.sprite_shifter_pattern_lo[i] = 0
            if (2 <= self.cycle < 258) or (321 <= self.cycle < 338): 
                self.eval_background()
            if self.cycle == 256:
                if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:
                    self.incrementScrollY()
            if self.cycle == 257:                
                self.loadBackgroundShifters()
                if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:
                    self.transferAddressX()
            if self.cycle == 338 or self.cycle == 340:                
                self.background_next_tile_id = self.fetch_background_tile()
            if 280 <= self.cycle < 305:
                if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:               
                    self.transferAddressY()
            if self.cycle == 340:
                self.fetch_sprites()
        elif visible_scanlines:
            if self.scanline == 0 and self.cycle == 0:
                self.cycle = 1
            if (2 <= self.cycle < 258) or (321 <= self.cycle < 338): 
                self.eval_background()
            if self.cycle == 256:
                if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:
                    self.incrementScrollY()
            if self.cycle == 257:                
                self.loadBackgroundShifters()
                if self.PPUMASK.render_background == 1 or self.PPUMASK.render_sprites == 1:
                    self.transferAddressX()
            if self.cycle == 338 or self.cycle == 340:                
                self.background_next_tile_id = self.readByPPU(0x2000 | (self.vram_addr.value & 0x0FFF))
            if self.cycle == 257:
                self.eval_sprites()
            if self.cycle == 340:
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

        if 0 <= self.cycle - 1 < self.screenWidth and 0 <= self.scanline < self.screenHeight: 
            self.spriteScreen[self.scanline][<int>(self.cycle - 1)] = self.getColorFromPaletteTable(palette, pixel)

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
                    