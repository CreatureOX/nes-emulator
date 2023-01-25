from typing import List, Tuple
from numpy import ndarray, uint16, int16, uint8, zeros

from bus import CPUBus
from cartridge import Cartridge
from mapper import Mirror

class Status:
    def __init__(self) -> None:
        self.reg = 0b00000000

    def set_reg(self,val):
        self.reg = val

    def get_reg(self):
        return self.reg
    
    def set_unused(self,val):
        self.reg |= val & 0b11111
    
    def get_unused(self):
        return self.reg & 0b11111
    
    def set_sprite_overflow(self,val):
        self.reg |= (val << 5) & 0b100000
    
    def get_sprite_overflow(self):
        return (self.reg & 0b100000) >> 5
    
    def set_sprite_zero_hit(self,val):
        self.reg |= (val << 6) & 0b1000000
    
    def get_sprite_zero_hit(self):
        return (self.reg & 0b1000000) >> 6
    
    def set_vertical_blank(self,val):
        self.reg |= (val << 7) & 0b10000000
    
    def get_vertical_blank(self):
        return (self.reg & 0b10000000) >> 7

class Mask:
    def __init__(self) -> None:
        self.reg = 0b00000000

    def set_reg(self,val):
        self.reg = val

    def get_reg(self):
        return self.reg

    def set_grayscale(self,val):
        self.reg |= val & 0b1

    def get_grayscale(self):
        return self.reg & 0b1

    def set_render_background_left(self,val):
        self.reg |= (val << 1) & 0b10

    def get_render_background_left(self):
        return (self.reg & 0b10) >> 1

    def set_render_sprites_left(self,val):
        self.reg |= (val << 2) & 0b100
    
    def get_render_sprites_left(self):
        return (self.reg & 0b100) >> 2

    def set_render_background(self,val):
        self.reg |= (val << 3) & 0b1000
    
    def get_render_background(self):
        return (self.reg & 0b1000) >> 3

    def set_render_sprites(self,val):
        self.reg |= (val << 4) & 0b10000
    
    def get_render_sprites(self):
        return (self.reg & 0b10000) >> 4

    def set_enhance_red(self,val):
        self.reg |= (val << 5) & 0b100000
    
    def get_enhance_red(self):
        return (self.reg & 0b100000) >> 5

    def set_enhance_green(self,val):
        self.reg |= (val << 6) & 0b1000000
    
    def get_enhance_green(self):
        return (self.reg & 0b1000000) >> 6

    def set_enhance_blue(self,val):
        self.reg |= (val << 7) & 0b10000000
    
    def get_enhance_blue(self):
        return (self.reg & 0b10000000) >> 7

class PPUCTRL:
    def __init__(self) -> None:
        self.reg = 0b00000000

    def set_reg(self,val):
        self.reg = val

    def get_reg(self):
        return self.reg

    def set_nametable_x(self,val):
        self.reg |= val & 0b1

    def get_nametable_x(self):
        return self.reg & 0b1

    def set_nametable_y(self,val):
        self.reg |= (val << 1) & 0b10

    def get_nametable_y(self):
        return (self.reg & 0b10) >> 1

    def set_increment_mode(self,val):
        self.reg |= (val << 2) & 0b100
    
    def get_increment_mode(self):
        return (self.reg & 0b100) >> 2

    def set_pattern_sprite(self,val):
        self.reg |= (val << 3) & 0b1000
    
    def get_pattern_sprite(self):
        return (self.reg & 0b1000) >> 3

    def set_pattern_background(self,val):
        self.reg |= (val << 4) & 0b10000
    
    def get_pattern_background(self):
        return (self.reg & 0b10000) >> 4

    def set_sprite_size(self,val):
        self.reg |= (val << 5) & 0b100000
    
    def get_sprite_size(self):
        return (self.reg & 0b100000) >> 5

    def set_slave_mode(self,val):
        self.reg |= (val << 6) & 0b1000000
    
    def get_slave_mode(self):
        return (self.reg & 0b1000000) >> 6

    def set_enable_nmi(self,val):
        self.reg |= (val << 7) & 0b10000000
    
    def get_enable_nmi(self):
        return (self.reg & 0b10000000) >> 7

class LoopRegister:
    def __init__(self) -> None:
        self.reg = 0b0000_0000_0000_0000

    def set_reg(self,val):
        self.reg = val

    def get_reg(self):
        return self.reg

    def set_coarse_x(self,val):
        self.reg &= ~(0b11111 << 0)
        val &= 0xFFFF
        self.reg |= val & 0b11111    

    def get_coarse_x(self):
        return self.reg & 0b11111  

    def set_coarse_y(self,val):
        self.reg &= ~(0b11111 << 5)
        val &= 0xFFFF
        self.reg |= (val << 5) & 0b1111100000    

    def get_coarse_y(self):
        return (self.reg & 0b1111100000) >> 5

    def set_nametable_x(self,val):
        self.reg &= ~(0b1 << 10)
        val &= 0xFFFF
        self.reg |= (val << 10) & 0b10000000000 

    def get_nametable_x(self):
        return (self.reg & 0b10000000000) >> 10  

    def set_nametable_y(self,val):
        self.reg &= ~(0b1 << 11)
        val &= 0xFFFF
        self.reg |= (val << 11) & 0b10_00000_00000 

    def get_nametable_y(self):
        return (self.reg & 0b10_00000_00000) >> 11  

    def set_fine_y(self,val):
        self.reg &= ~(0b111 << 12)
        val &= 0xFFFF
        self.reg |= (val << 12) & 0b11100_00000_00000 

    def get_fine_y(self):
        return (self.reg & 0b11100_00000_00000) >> 12

    def set_unused(self,val):
        self.reg &= ~(0b1 << 15)
        val &= 0xFFFF
        self.reg |= (val << 15) & 0b100000_00000_00000 

    def get_unused(self):
        return (self.reg & 0b100000_00000_00000) >> 15

# class sObjectAttributeEntry(LittleEndianStructure):
#     _fields_ = [
#         ("y", c_uint8),
#         ("id", c_uint8),
#         ("attribute", c_uint8),
#         ("x", c_uint8),
#     ]

# class sObjectAttributeEntry:
#     def __init__(self,y,id,attribute,x) -> None:
#         self.y = y
#         self.id = id
#         self.attribute = attribute 
#         self.x = x

Y = 0
ID = 1
ATTRIBUTE = 2
X = 3

def offset(i: uint8, offset: uint8):
    return i*4+offset

def flipbyte(b: uint8) -> uint8:
    b = (b & 0xF0) >> 4 | (b & 0x0F) << 4
    b = (b & 0xCC) >> 2 | (b & 0x33) << 2
    b = (b & 0xAA) >> 1 | (b & 0x55) << 1
    return b

class PPU2C02:
    patternTable: List[List[uint8]]
    nameTable: List[List[uint8]]
    paletteTable: List[uint8]

    palettePanel: List[Tuple[uint8,uint8,uint8]]
    spriteScreen: ndarray
    spriteNameTable: List[ndarray]
    spritePatternTable: List[ndarray]

    status: Status
    mask: Mask
    control: PPUCTRL
    vram_addr: LoopRegister
    tram_addr: LoopRegister

    fine_x: uint8

    address_latch: uint8
    ppu_data_buffer: uint8

    scanline: int16
    cycle: int16

    background_next_tile_id: uint8
    background_next_tile_attribute: uint8
    background_next_tile_lsb: uint8
    background_next_tile_msb: uint8
    background_shifter_pattern_lo: uint16
    background_shifter_pattern_hi: uint16
    background_shifter_attribute_lo: uint16
    background_shifter_attribute_hi: uint16

    # OAM: List[sObjectAttributeEntry]
    pOAM: List[uint8]

    oam_addr: uint8

    # spriteScanline: List[sObjectAttributeEntry]
    pSpriteScanline: List[uint8]
    sprite_count: uint8
    sprite_shifter_pattern_lo: List[uint8]
    sprite_shifter_pattern_hi: List[uint8]

    bSpriteZeroHitPossible: bool
    bSpriteZeroBeingRendered: bool

    cartridge: Cartridge

    nmi: bool

    frame_complete: bool 

    bus: CPUBus

    def __init__(self, bus: CPUBus) -> None:
        self.patternTable = [[0x00] * 64 * 64] * 2
        self.nameTable = [[0x00] * 32 * 32] * 2
        self.paletteTable = [0x00] * 32
        
        self.palettePanel = [None] * 4 * 16
        self.screenWidth, self.screenHeight = 256, 240
        self.spriteScreen = zeros((self.screenHeight,self.screenWidth,3)).astype(uint8)
        self.spriteNameTable = [zeros((self.screenHeight,self.screenWidth,3)),zeros((self.screenHeight,self.screenWidth,3))]
        self.spritePatternTable = [zeros((128,128,3)).astype(uint8),zeros((128,128,3)).astype(uint8)]

        self.status = Status()
        self.mask = Mask()
        self.control = PPUCTRL()
        self.vram_addr = LoopRegister()
        self.tram_addr = LoopRegister()

        self.fine_x = 0x00

        self.address_latch = 0x00
        self.ppu_data_buffer = 0x00

        self.scanline = 0
        self.cycle = 0

        self.background_next_tile_id = 0x00
        self.background_next_tile_attribute = 0x00
        self.background_next_tile_lsb = 0x00
        self.background_next_tile_msb = 0x00
        self.background_shifter_pattern_lo = 0x0000
        self.background_shifter_pattern_hi = 0x0000
        self.background_shifter_attribute_lo = 0x0000
        self.background_shifter_attribute_hi = 0x0000

        # self.OAM = (sObjectAttributeEntry * 64)()
        # self.pOAM = cast(self.OAM, POINTER(c_uint8))
        self.pOAM = zeros((64 * 32), dtype=uint8)

        self.oam_addr = 0x00

        # self.spriteScanline = (sObjectAttributeEntry * 8)()
        # self.spriteScanline = array([sObjectAttributeEntry(0x00,0x00,0x00,0x00) for _ in range(8)])
        self.pSpriteScanline = zeros((8 * 32), dtype=uint8)

        self.sprite_shifter_pattern_lo = [0x00] * 8
        self.sprite_shifter_pattern_hi = [0x00] * 8
        self.bSpriteZeroHitPossible = False
        self.bSpriteZeroBeingRendered = False
        self.nmi = False
        self.frame_complete = False

        self.bus = bus
        self.setPalettePanel()

    def connectCartridge(self, cartridge) -> None:
        self.cartridge = cartridge
    
    def getScreen(self) -> ndarray:
        return self.spriteScreen

    def readByCPU(self, addr: uint16, readonly: bool) -> uint8:
        data = 0x00

        if readonly:
            if addr == 0x0000:
                # Control
                data = self.control.get_reg()
            elif addr == 0x0001:
                # Mask
                data = self.mask.get_reg()
            elif addr == 0x0002:
                # Status
                data = self.status.get_reg()
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
                data = (self.status.get_reg() & 0xE0) | (self.ppu_data_buffer & 0x1F)
                self.status.set_vertical_blank(0)
                self.address_latch = 0
            elif addr == 0x0003:
                # OAM Address
                pass
            elif addr == 0x0004:
                # OAM Data
                data = self.pOAM[self.oam_addr]
            elif addr == 0x0005:
                # Scroll
                pass
            elif addr == 0x0006:
                # PPU Address
                pass
            elif addr == 0x0007:
                # PPU Data
                data = self.ppu_data_buffer
                self.ppu_data_buffer = self.readByPPU(self.vram_addr.get_reg())
                if self.vram_addr.get_reg() >= 0x3F00:
                    data = self.ppu_data_buffer
                #self.vram_addr.reg += 32 if self.control.get_increment_mode() == 1 else 1  
                self.vram_addr.set_reg(self.vram_addr.get_reg() + (32 if self.control.get_increment_mode() == 1 else 1  ))  
        return data

    def writeByCPU(self, addr: uint16, data: uint8) -> None:
        if addr == 0x0000:
            # Control
            self.control.set_reg(data)
            self.tram_addr.set_nametable_x(self.control.get_nametable_x())
            self.tram_addr.set_nametable_y(self.control.get_nametable_y())
        elif addr == 0x0001:
            # Mask
            self.mask.set_reg(data)
        elif addr == 0x0002:
            # Status
            pass
        elif addr == 0x0003:
            # OAM Address
            self.oam_addr = data
        elif addr == 0x0004:
            # OAM Data
            self.pOAM[self.oam_addr] = data
        elif addr == 0x0005:
            # Scroll
            if self.address_latch == 0:
                self.fine_x = data & 0x07
                self.tram_addr.set_coarse_x(data >> 3)
                self.address_latch = 1
            else:
                self.tram_addr.set_fine_y(data & 0x07)
                self.tram_addr.set_coarse_y(data >> 3)
                self.address_latch = 0
        elif addr == 0x0006:
            # PPU Address
            if self.address_latch == 0:
                self.tram_addr.set_reg(((data & 0x3F) << 8) | (self.tram_addr.get_reg() & 0x00FF))
                self.address_latch = 1
            else:
                self.tram_addr.set_reg((self.tram_addr.reg & 0xFF00) | data)
                self.vram_addr.set_reg(self.tram_addr.get_reg())
                self.address_latch = 0
        elif addr == 0x0007:
            # PPU Data
            self.writeByPPU(self.vram_addr.get_reg(), data)
            self.vram_addr.set_reg(self.vram_addr.get_reg() + (32 if self.control.get_increment_mode() else 1))

    def readByPPU(self, addr: uint16) -> uint8:
        addr &= 0x3FFF

        success, data = self.cartridge.readByPPU(addr)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            data = self.patternTable[(addr & 0x1000) >> 12][addr & 0x0FFF]
        elif 0x2000 <= addr <= 0x3EFF:
            addr &= 0x0FFF
            if self.cartridge.mirror == Mirror.VERTICAL:
                if 0x0000 <= addr <= 0x03FF:
                    data = self.nameTable[0][addr & 0x03FF]
                elif 0x0400 <= addr <= 0x07FF:
                    data = self.nameTable[1][addr & 0x03FF]
                elif 0x0800 <= addr <= 0x0BFF:
                    data = self.nameTable[0][addr & 0x03FF]
                elif 0x0C00 <= addr <= 0x0FFF:
                    data = self.nameTable[1][addr & 0x03FF]                                 
            elif self.cartridge.mirror == Mirror.HORIZONTAL:
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
            data = self.paletteTable[addr] & (0x30 if self.mask.get_grayscale() == 1 else 0x3F)
        return data

    def writeByPPU(self, addr: uint16, data: uint8) -> None:
        addr &= 0x3FFF     

        success = self.cartridge.writeByPPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            self.patternTable[(addr & 0x1000) >> 12][addr & 0x0FFF] = data
        elif 0x2000 <= addr <= 0x3EFF:
            addr &= 0x0FFF
            if self.cartridge.mirror == Mirror.VERTICAL:
                if 0x0000 <= addr <= 0x03FF:
                    self.nameTable[0][addr & 0x03FF] = data
                if 0x0400 <= addr <= 0x07FF:
                    self.nameTable[1][addr & 0x03FF] = data
                if 0x0800 <= addr <= 0x0BFF:
                    self.nameTable[0][addr & 0x03FF] = data
                if 0x0C00 <= addr <= 0x0FFF:
                    self.nameTable[1][addr & 0x03FF] = data
            elif self.cartridge.mirror == Mirror.HORIZONTAL:
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

    def setPalettePanel(self) -> None:    
        self.palettePanel[0x00],self.palettePanel[0x01],self.palettePanel[0x02],self.palettePanel[0x03],self.palettePanel[0x04],self.palettePanel[0x05],self.palettePanel[0x06],self.palettePanel[0x07],self.palettePanel[0x08],self.palettePanel[0x09],self.palettePanel[0x0a],self.palettePanel[0x0b],self.palettePanel[0x0c],self.palettePanel[0x0d],self.palettePanel[0x0e],self.palettePanel[0x0f] = ( 84,  84,  84), (  0,  30, 116), (  8,  16, 144), ( 48,   0, 136), ( 68,   0, 100), ( 92,   0,  48), ( 84,   4,   0), ( 60,  24,   0), ( 32,  42,   0), (  8,  58,   0), (  0,  64,   0), (  0,  60,   0), (  0,  50,  60), (  0,   0,   0), (  0,   0,   0), (  0,   0,   0)
        self.palettePanel[0x10],self.palettePanel[0x11],self.palettePanel[0x12],self.palettePanel[0x13],self.palettePanel[0x14],self.palettePanel[0x15],self.palettePanel[0x16],self.palettePanel[0x17],self.palettePanel[0x18],self.palettePanel[0x19],self.palettePanel[0x1a],self.palettePanel[0x1b],self.palettePanel[0x1c],self.palettePanel[0x1d],self.palettePanel[0x1e],self.palettePanel[0x1f] = (152, 150, 152), (  8,  76, 196), ( 48,  50, 236), ( 92,  30, 228), (136,  20, 176), (160,  20, 100), (152,  34,  32), (120,  60,   0), ( 84,  90,   0), ( 40, 114,   0), (  8, 124,   0), (  0, 118,  40), (  0, 102, 120), (  0,   0,   0), (  0,   0,   0), (  0,   0,   0)
        self.palettePanel[0x20],self.palettePanel[0x21],self.palettePanel[0x22],self.palettePanel[0x23],self.palettePanel[0x24],self.palettePanel[0x25],self.palettePanel[0x26],self.palettePanel[0x27],self.palettePanel[0x28],self.palettePanel[0x29],self.palettePanel[0x2a],self.palettePanel[0x2b],self.palettePanel[0x2c],self.palettePanel[0x2d],self.palettePanel[0x2e],self.palettePanel[0x2f] = (236, 238, 236), ( 76, 154, 236), (120, 124, 236), (176,  98, 236), (228,  84, 236), (236,  88, 180), (236, 106, 100), (212, 136,  32), (160, 170,   0), (116, 196,   0), ( 76, 208,  32), ( 56, 204, 108), ( 56, 180, 204), ( 60,  60,  60), (  0,   0,   0), (  0,   0,   0)
        self.palettePanel[0x30],self.palettePanel[0x31],self.palettePanel[0x32],self.palettePanel[0x33],self.palettePanel[0x34],self.palettePanel[0x35],self.palettePanel[0x36],self.palettePanel[0x37],self.palettePanel[0x38],self.palettePanel[0x39],self.palettePanel[0x3a],self.palettePanel[0x3b],self.palettePanel[0x3c],self.palettePanel[0x3d],self.palettePanel[0x3e],self.palettePanel[0x3f] = (236, 238, 236), (168, 204, 236), (188, 188, 236), (212, 178, 236), (236, 174, 236), (236, 174, 212), (236, 180, 176), (228, 196, 144), (204, 210, 120), (180, 222, 120), (168, 226, 144), (152, 226, 180), (160, 214, 228), (160, 162, 160), (  0,   0,   0), (  0,   0,   0)
   
    def getColorFromPaletteTable(self, palette: uint8, pixel: uint8) -> Tuple[uint8,uint8,uint8]:
        color = self.readByPPU(0x3F00 + (palette << 2) + pixel) & 0x3F
        # if color > 0:
        #     print("color: {color}".format(color=color))
        return self.palettePanel[color]

    def getPatternTable(self, i: uint8, palette: uint8) -> ndarray:
        for tileY in range(0,16):
            for tileX in range(0,16):
                offset: uint16 = tileY * 256 + tileX * 16
                for row in range(0,8):
                    tile_lsb: uint8 = self.readByPPU(i * 0x1000 + offset + row + 0x0000)
                    tile_msb: uint8 = self.readByPPU(i * 0x1000 + offset + row + 0x0008)
                    for col in range(0,8):
                        pixel: uint8 = (tile_lsb & 0x01) << 1 | (tile_msb & 0x01)
                        tile_lsb, tile_msb = tile_lsb >> 1, tile_msb >> 1
                        self.spritePatternTable[i][tileY * 8 + row,tileX * 8 + (7 - col)] = self.getColorFromPaletteTable(palette, pixel)
        
        return self.spritePatternTable[i]

    def reset(self) -> None:
        self.fine_x = 0x00
        self.address_latch = 0x00
        self.ppu_data_buffer = 0x00
        self.scanline, self.cycle  = 0, 0
        self.background_next_tile_id = 0x00
        self.background_next_tile_attribute = 0x00
        self.background_next_tile_lsb, self.background_next_tile_msb = 0x00, 0x00
        self.background_shifter_pattern_lo, self.background_shifter_pattern_hi = 0x0000, 0x0000
        self.background_shifter_attribute_lo, self.background_shifter_attribute_hi = 0x0000, 0x0000
        self.status.set_reg(0x00)
        self.mask.set_reg(0x00)
        self.control.set_reg(0x00)
        self.vram_addr.set_reg(0x0000)
        self.tram_addr.set_reg(0x0000)

    def incrementScrollX(self) -> None:
        if self.mask.get_render_background() == 1 or self.mask.get_render_sprites() == 1:
            if self.vram_addr.get_coarse_x() == 31:
                self.vram_addr.set_coarse_x(0)
                self.vram_addr.set_nametable_x(~self.vram_addr.get_nametable_x())
            else:
                self.vram_addr.set_coarse_x(self.vram_addr.get_coarse_x() + 1)

    def incrementScrollY(self) -> None:
        if self.mask.get_render_background() == 1 or self.mask.get_render_sprites() == 1:
            if self.vram_addr.get_fine_y() < 7:
                self.vram_addr.set_fine_y(self.vram_addr.get_fine_y() + 1)
            else:
                self.vram_addr.set_fine_y(0)
                if self.vram_addr.get_coarse_y() == 29:
                    self.vram_addr.set_coarse_y(0)
                    self.vram_addr.set_nametable_y(~self.vram_addr.get_nametable_y())
                elif self.vram_addr.get_coarse_y() == 31:
                    self.vram_addr.set_coarse_y(0)
                else:
                    self.vram_addr.set_coarse_y(self.vram_addr.get_coarse_y() + 1)

    def transferAddressX(self) -> None:
        if self.mask.get_render_background() == 1 or self.mask.get_render_sprites() == 1:
            self.vram_addr.set_nametable_x(self.tram_addr.get_nametable_x())
            self.vram_addr.set_coarse_x(self.tram_addr.get_coarse_x())

    def transferAddressY(self) -> None:
        if self.mask.get_render_background() == 1 or self.mask.get_render_sprites() == 1:
            self.vram_addr.set_fine_y(self.tram_addr.get_fine_y())
            self.vram_addr.set_nametable_y(self.tram_addr.get_nametable_y())
            self.vram_addr.set_coarse_y(self.tram_addr.get_coarse_y())

    def loadBackgroundShifters(self) -> None:
        self.background_shifter_pattern_lo = ((self.background_shifter_pattern_lo & 0xFF00) | self.background_next_tile_lsb)
        self.background_shifter_pattern_hi = ((self.background_shifter_pattern_hi & 0xFF00) | self.background_next_tile_msb) 
        self.background_shifter_attribute_lo = 0xFF if ((self.background_shifter_attribute_lo & 0xFF00) | (self.background_next_tile_attribute & 0b01)) > 0 else 0x00
        self.background_shifter_attribute_hi = 0xFF if ((self.background_shifter_attribute_hi & 0xFF00) | (self.background_next_tile_attribute & 0b10)) > 0 else 0x00

    def updateShifters(self) -> None:
        if self.mask.get_render_background() == 1:
            self.background_shifter_pattern_lo <<= 1
            self.background_shifter_pattern_hi <<= 1
            self.background_shifter_attribute_lo <<= 1
            self.background_shifter_attribute_hi <<= 1
        if self.mask.get_render_sprites() == 1 and self.cycle >= 1 and self.cycle < 258:
            for i in range(0, self.sprite_count):
                if self.pSpriteScanline[offset(i,X)] > 0:
                    # self.spriteScanline[i].x = self.spriteScanline[i].x - 1
                    # self.pSpriteScanline[offset(i,X)] = self.pSpriteScanline[offset(i,X)] - 1
                    self.pSpriteScanline[offset(i,X)] = self.pSpriteScanline[offset(i,X)] - 1
                else:
                    self.sprite_shifter_pattern_lo[i] <<= 1
                    self.sprite_shifter_pattern_hi[i] <<= 1

    def clock(self) -> None:
        if -1 <= self.scanline < 240:
            if self.scanline == 0 and self.cycle == 0:
                self.cycle = 1
            if self.scanline == -1 and self.cycle == 1:
                self.status.set_vertical_blank(0)
                self.status.set_sprite_overflow(0)
                self.status.set_sprite_zero_hit(0)
                for i in range(0, 8):
                    self.sprite_shifter_pattern_hi[i] = 0
                    self.sprite_shifter_pattern_lo[i] = 0
            if (2 <= self.cycle < 258) or (321 <= self.cycle < 338): 
                self.updateShifters()
                v: uint16 = (self.cycle - 1) % 8
                if v == 0:
                    self.loadBackgroundShifters()
                    self.background_next_tile_id = self.readByPPU(0x2000 | (self.vram_addr.get_reg() & 0x0FFF))
                elif v == 2:
                    self.background_next_tile_attribute = self.readByPPU(0x23C0 \
                        | (self.vram_addr.get_nametable_y() << 11) \
                        | (self.vram_addr.get_nametable_x() << 10) \
                        | ((self.vram_addr.get_coarse_y() >> 2) << 3) \
                        | (self.vram_addr.get_coarse_x() >> 2)    
                    )
                    if self.vram_addr.get_coarse_y() & 0x02 > 0:
                        self.background_next_tile_attribute >>= 4
                    if self.vram_addr.get_coarse_x() & 0x02 > 0:
                        self.background_next_tile_attribute >>= 2
                    self.background_next_tile_attribute &= 0x03
                elif v == 4:
                    self.background_next_tile_lsb = self.readByPPU((self.control.get_pattern_background() << 12) \
                        + (self.background_next_tile_id << 4) \
                        + (self.vram_addr.get_fine_y()) + 0
                    )
                elif v == 6:
                    self.background_next_tile_msb = self.readByPPU((self.control.get_pattern_background() << 12) \
                        + (self.background_next_tile_id << 4) \
                        + (self.vram_addr.get_fine_y()) + 8
                    )
                elif v == 7:
                    self.incrementScrollX()
            if self.cycle == 256:
                self.incrementScrollY()
            if self.cycle == 257:                
                self.loadBackgroundShifters()
                self.transferAddressX()
            if self.cycle == 338 or self.cycle == 340:                
                self.background_next_tile_id = self.readByPPU(0x2000 | (self.vram_addr.get_reg() & 0x0FFF))
            if self.scanline == -1 and 280 <= self.cycle < 305:               
                self.transferAddressY()
            if self.cycle == 257 and self.scanline >= 0:
                # memset(self.spriteScanline, 0xFF, 8 * sizeof(sObjectAttributeEntry))
                # self.spriteScanline = array([sObjectAttributeEntry(0xFF,0xFF,0xFF,0xFF) for _ in range(8)])
                self.pSpriteScanline = [0xFF for _ in range(8 * 32)]
                self.sprite_count = 0
                for i in range(0, 8):
                    self.sprite_shifter_pattern_lo[i] = 0
                    self.sprite_shifter_pattern_hi[i] = 0
                nOAMEntry: uint8 = 0
                self.bSpriteZeroHitPossible = False
                while nOAMEntry < 64 and self.sprite_count < 9:
                    # diff = self.scanline - int16(self.OAM(nOAMEntry).y)
                    diff = self.scanline - int16(self.pOAM[offset(nOAMEntry, Y)])
                    diff_compare = 16 if self.control.get_sprite_size() == 1 else 8
                    if diff >= 0 and diff < diff_compare:
                        if self.sprite_count < 8:
                            if nOAMEntry == 0:
                                self.bSpriteZeroHitPossible = True
                            # self.spriteScanline[self.sprite_count] = self.OAM(nOAMEntry)
                            self.pSpriteScanline[offset(self.sprite_count,Y)] = self.pOAM[offset(nOAMEntry,Y)]
                            self.pSpriteScanline[offset(self.sprite_count,ID)] = self.pOAM[offset(nOAMEntry,ID)]
                            self.pSpriteScanline[offset(self.sprite_count,ATTRIBUTE)] = self.pOAM[offset(nOAMEntry,ATTRIBUTE)]
                            self.pSpriteScanline[offset(self.sprite_count,X)] = self.pOAM[offset(nOAMEntry,X)]
                            self.sprite_count += 1
                    nOAMEntry += 1
                self.status.set_sprite_overflow(1 if self.sprite_count > 8 else 0)
            if self.cycle == 340:
                for i in range(0, self.sprite_count):
                    sprite_pattern_bits_lo, sprite_pattern_bits_hi = 0x00, 0x00
                    sprite_pattern_addr_lo, sprite_pattern_addr_hi = 0x0000, 0x0000
                    if self.control.get_sprite_size() == 0:
                        if (self.pSpriteScanline[offset(i,ATTRIBUTE)] & 0x80) == 0:
                            sprite_pattern_addr_lo = (self.control.get_pattern_sprite()<<12) \
                                | (self.pSpriteScanline[offset(i,ID)]<<4) \
                                | ((self.scanline - self.pSpriteScanline[offset(i,Y)]) & 0xFFFF)
                        else:
                            sprite_pattern_addr_lo = (self.control.get_pattern_sprite()<<12) \
                                | (self.pSpriteScanline[offset(i,ID)]<<4) \
                                | ((7 - (self.scanline - self.pSpriteScanline[offset(i,Y)])) & 0xFFFF)
                    else:
                        if (self.pSpriteScanline[offset(i,ATTRIBUTE)] & 0x80) == 0:
                            if self.scanline - self.pSpriteScanline[offset(i,Y)] < 8:
                                sprite_pattern_addr_lo = ((self.pSpriteScanline[offset(i,ID)] & 0x01)<<12) \
                                    | ((self.pSpriteScanline[offset(i,ID)] & 0xFE)<<4) \
                                    | ((self.scanline - self.pSpriteScanline[offset(i,Y)])&0x07) 
                            else:
                                sprite_pattern_addr_lo = ((self.pSpriteScanline[offset(i,ID)] & 0x01)<<12) \
                                    | (((self.pSpriteScanline[offset(i,ID)] & 0xFE)+1)<<4) \
                                    | ((self.scanline - self.pSpriteScanline[offset(i,Y)])&0x07) 
                        else:
                            if self.scanline - self.pSpriteScanline[offset(i,Y)] < 8:
                                sprite_pattern_addr_lo = ((self.pSpriteScanline[offset(i,ID)] & 0x01)<<12) \
                                    | (((self.pSpriteScanline[offset(i,ID)] & 0xFE)+1)<<4) \
                                    | ((7-(self.scanline - self.pSpriteScanline[offset(i,Y)]))&0x07) 
                            else:
                                sprite_pattern_addr_lo = ((self.pSpriteScanline[offset(i,ID)] & 0x01)<<12) \
                                    | ((self.pSpriteScanline[offset(i,ID)] & 0xFE)<<4) \
                                    | ((7-(self.scanline - self.pSpriteScanline[offset(i,Y)]))&0x07)   
                
                    sprite_pattern_addr_hi = sprite_pattern_addr_lo + 8
                    
                    sprite_pattern_bits_lo = self.readByPPU(sprite_pattern_addr_lo)
                    sprite_pattern_bits_hi = self.readByPPU(sprite_pattern_addr_hi)
                    
                    if self.pSpriteScanline[offset(i,ATTRIBUTE)] & 0x40 != 0:
                        sprite_pattern_bits_lo = flipbyte(sprite_pattern_bits_lo)
                        sprite_pattern_bits_hi = flipbyte(sprite_pattern_bits_hi)

                    self.sprite_shifter_pattern_lo[i] = sprite_pattern_bits_lo
                    self.sprite_shifter_pattern_hi[i] = sprite_pattern_bits_hi
        if self.scanline == 240:
            pass
        if 241 <= self.scanline < 261:            
            if self.scanline == 241 and self.cycle == 1:
                self.status.set_vertical_blank(1)
                if self.control.get_enable_nmi() == 1:
                    self.nmi = True

        background_pixel: uint8 = 0x00
        background_palette: uint8 = 0x00
        if self.mask.get_render_background() == 1:
            bit_mux: uint16 = 0x8000 >> self.fine_x

            background_pixel_0: uint8 = 1 if (self.background_shifter_pattern_lo & bit_mux) > 0 else 0
            background_pixel_1: uint8 = 1 if (self.background_shifter_pattern_hi & bit_mux) > 0 else 0
            background_pixel = (background_pixel_1 << 1) | background_pixel_0

            background_palette_0: uint8 = 1 if (self.background_shifter_attribute_lo & bit_mux) > 0 else 0
            background_palette_1: uint8 = 1 if (self.background_shifter_attribute_hi & bit_mux) > 0 else 0
            background_palette = (background_palette_1 << 1) | background_palette_0

        foreground_pixel: uint8 = 0
        foreground_palette: uint8 = 0x00
        foreground_priority: uint8 = 0x00

        if self.mask.get_render_sprites() == 1:
            self.bSpriteZeroBeingRendered = False
            for i in range(0, self.sprite_count):
                if self.pSpriteScanline[offset(i,X)] == 0:
                    foreground_pixel_lo: uint8 = 1 if (self.sprite_shifter_pattern_lo[i] & 0x80) > 0 else 0
                    foreground_pixel_hi: uint8 = 1 if (self.sprite_shifter_pattern_hi[i] & 0x80) > 0 else 0
                    foreground_pixel = (foreground_pixel_hi << 1) | foreground_pixel_lo
                    foreground_palette = (self.pSpriteScanline[offset(i,ATTRIBUTE)] & 0x03) + 0x04
                    foreground_priority = 1 if (self.pSpriteScanline[offset(i,ATTRIBUTE)] & 0x20) == 0 else 0

                    if foreground_pixel != 0:
                        if i == 0:
                            self.bSpriteZeroBeingRendered = True
                        break
        pixel: uint8 = 0x00
        palette: uint8 = 0x00
        
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
            if foreground_priority:
                pixel = foreground_pixel
                palette = foreground_palette
            else:
                pixel = background_pixel
                palette = background_palette
            if self.bSpriteZeroHitPossible and self.bSpriteZeroBeingRendered:
                if self.mask.get_render_background() & self.mask.get_render_sprites() != 0:
                    if (~(self.mask.get_render_background_left() | self.mask.get_render_sprites_left()) != 0):
                        if 9 <= self.cycle < 258:
                            self.status.set_sprite_zero_hit(1)
                    else:
                        if 1 <= self.cycle < 258:
                            self.status.set_sprite_zero_hit(1)

        if 0 <= self.cycle - 1 < self.screenWidth and 0 <= self.scanline < self.screenHeight: 
            self.spriteScreen[self.scanline, self.cycle - 1] = self.getColorFromPaletteTable(palette, pixel)

        self.cycle += 1
        if self.cycle >= 341:
            self.cycle = 0
            self.scanline += 1
            if self.scanline >= 261:
                self.scanline = -1
                self.frame_complete = True
                