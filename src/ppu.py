from copy import deepcopy
from random import randint
from turtle import width
from typing import List
from matplotlib import pyplot as plt
from numpy import uint16, uint8, void, zeros
from bus import CPUBus

from cartridge import Cartridge
from graph import Pixel, Sprite
from utils import get_bit, set_bit


class PPU2C02:
    class Status:
        reg: uint8

        unused: uint8
        sprite_overflow: uint8
        sprite_zero_hit: uint8
        vertical_blank: uint8

        def __init__(self) -> None:
            self.set_reg(0)

        def set_reg(self, reg: uint8) -> None:
            reg = uint8(reg)
            self.reg = reg
            
            self.sprite_overflow = uint8(get_bit(reg, 5))
            self.sprite_zero_hit = uint8(get_bit(reg, 6))
            self.vertical_blank = uint8(get_bit(reg, 7))

        def set_sprite_overflow(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 5, value))
            self.sprite_overflow = value

        def set_sprite_zero_hit(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 6, value))
            self.sprite_zero_hit = value

        def set_vertical_blank(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 7, value))
            self.vertical_blank = value

        def get_reg(self) -> uint8:
            return uint8(self.reg)

        def get_sprite_overflow(self) -> uint8:
            return uint8(self.sprite_overflow)

        def get_sprite_zero_hit(self) -> uint8:
            return uint8(self.sprite_zero_hit)

        def get_vertical_blank(self) -> uint8:
            return uint8(self.vertical_blank)

    class Mask:
        reg: uint8

        grayscale: uint8
        render_background_left: uint8
        render_sprites_left: uint8
        render_background: uint8
        render_sprites: uint8
        enhance_red: uint8
        enhance_green: uint8
        enhance_blue: uint8

        def __init__(self) -> None:
            self.set_reg(0)

        def set_reg(self, reg: uint8) -> None:
            reg = uint8(reg)
            self.reg = reg

            self.grayscale = uint8(get_bit(reg, 0))
            self.render_background_left = uint8(get_bit(reg, 1))
            self.render_sprites_left = uint8(get_bit(reg, 2))
            self.render_background = uint8(get_bit(reg, 3))
            self.render_sprites = uint8(get_bit(reg, 4))
            self.enhance_red = uint8(get_bit(reg, 5))
            self.enhance_green = uint8(get_bit(reg, 6))
            self.enhance_blue = uint8(get_bit(reg, 7))

        def set_grayscale(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 0, value))
            self.grayscale = value

        def set_render_background_left(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 1, value))
            self.render_background_left = value

        def set_render_sprites_left(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 2, value))
            self.render_sprites_left = value

        def set_render_background(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 3, value))
            self.render_background = value

        def set_render_sprites(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 4, value))
            self.render_sprites = value

        def set_enhance_red(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 5, value))
            self.enhance_red = value

        def set_enhance_green(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 6, value))
            self.enhance_green = value

        def set_enhance_blue(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 7, value))
            self.enhance_blue = value

        def get_reg(self) -> uint8:
            return uint8(self.reg)

        def get_grayscale(self) -> uint8:
            return uint8(self.grayscale)

        def get_render_background_left(self) -> uint8:
            return uint8(self.render_background_left)

        def get_render_sprites_left(self) -> uint8:
            return uint8(self.render_sprites_left)

        def get_render_background(self) -> uint8:
            return uint8(self.render_background)

        def get_render_sprites(self) -> uint8:
            return uint8(self.render_sprites)

        def get_enhance_red(self) -> uint8:
            return uint8(self.enhance_red)

        def get_enhance_green(self) -> uint8:
            return uint8(self.enhance_green)

        def get_enhance_blue(self) -> uint8:
            return uint8(self.enhance_blue)

    class PPUCTRL:
        reg: uint8

        nametable_x: uint8
        nametable_y: uint8
        increment_mode: uint8
        pattern_sprite: uint8
        pattern_background: uint8
        sprite_size: uint8
        slave_mode: uint8
        enable_nmi: uint8

        def __init__(self) -> None:
            self.set_reg(0)

        def set_reg(self, reg: uint8) -> None:
            reg = uint8(reg)
            self.reg = reg

            self.nametable_x = uint8(get_bit(reg, 0))
            self.nametable_y = uint8(get_bit(reg, 1))
            self.increment_mode = uint8(get_bit(reg, 2))
            self.pattern_sprite = uint8(get_bit(reg, 3))
            self.pattern_background = uint8(get_bit(reg, 4))
            self.sprite_size = uint8(get_bit(reg, 5))
            self.slave_mode = uint8(get_bit(reg, 6))
            self.enable_nmi = uint8(get_bit(reg, 7))

        def set_nametable_x(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 0, value))
            self.nametable_x = value

        def set_nametable_y(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 1, value))
            self.nametable_y = value

        def set_increment_mode(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 2, value))
            self.increment_mode = value

        def set_pattern_sprite(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 3, value))
            self.pattern_sprite = value          

        def set_pattern_background(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 4, value))
            self.pattern_background = self.reg[4] = value

        def set_sprite_size(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 5, value))
            self.sprite_size = value
        
        def set_slave_mode(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 6, value))
            self.slave_mode = value

        def set_enable_nmi(self, value: uint8) -> None:
            value = uint8(value)
            self.reg = uint8(set_bit(self.reg, 7, value))
            self.enable_nmi = value

        def get_reg(self) -> uint8:
            return uint8(self.reg)

        def get_nametable_x(self) -> uint8:
            return uint8(self.nametable_x)

        def get_nametable_y(self) -> uint8:
            return uint8(self.nametable_y)

        def get_increment_mode(self) -> uint8:
            return uint8(self.increment_mode)

        def get_pattern_sprite(self) -> uint8:
            return uint8(self.pattern_sprite)

        def get_pattern_background(self) -> uint8:
            return uint8(self.pattern_background)

        def get_sprite_size(self) -> uint8:
            return uint8(self.sprite_size)
        
        def get_slave_mode(self) -> uint8:
            return uint8(self.slave_mode)

        def get_enable_nmi(self) -> uint8:
            return uint8(self.enable_nmi)

    class LoopRegister:
        reg: uint16 = 0x0000

        coarse_x: uint16
        coarse_y: uint16
        nametable_x: uint16
        nametable_y: uint16
        fine_y: uint16
        unused: uint16

        def __init__(self) -> None:
            self.set_reg(0)
            
        def set_reg(self, reg: uint16) -> None:
            reg = uint16(reg)
            self.reg = reg
            
            self.coarse_x = uint16(get_bit(reg, 0) \
                | get_bit(reg, 1) << 1 \
                | get_bit(reg, 2) << 2 \
                | get_bit(reg, 3) << 3 \
                | get_bit(reg, 4) << 4) 
            self.coarse_y = uint16(get_bit(reg, 5) \
                | get_bit(reg, 6) << 1 \
                | get_bit(reg, 7) << 2 \
                | get_bit(reg, 8) << 3 \
                | get_bit(reg, 9) << 4) 
            self.nametable_x = get_bit(reg, 10)
            self.nametable_y = get_bit(reg, 11)
            self.fine_y = get_bit(reg, 12) \
                | get_bit(reg, 13) \
                | get_bit(reg, 14)

        def set_coarse_x(self, value: uint16) -> None:
            value = uint16(value)
            self.reg = set_bit(self.reg, 0, get_bit(value, 0))
            self.reg = set_bit(self.reg, 1, get_bit(value, 1))
            self.reg = set_bit(self.reg, 2, get_bit(value, 2))
            self.reg = set_bit(self.reg, 3, get_bit(value, 3))
            self.reg = set_bit(self.reg, 4, get_bit(value, 4))
            self.coarse_x = value

        def set_coarse_y(self, value: uint16) -> None:
            value = uint16(value)
            self.reg = set_bit(self.reg, 5, get_bit(value, 0))
            self.reg = set_bit(self.reg, 6, get_bit(value, 1))
            self.reg = set_bit(self.reg, 7, get_bit(value, 2))
            self.reg = set_bit(self.reg, 8, get_bit(value, 3))
            self.reg = set_bit(self.reg, 9, get_bit(value, 4))
            self.coarse_y = value

        def set_nametable_x(self, value: uint16) -> None:
            value = uint16(value)
            self.reg = set_bit(self.reg, 10, value)
            self.nametable_x = value

        def set_nametable_y(self, value: uint16) -> None:
            value = uint16(value)
            self.reg = set_bit(self.reg, 11, value)
            self.nametable_y = value

        def set_fine_y(self, value: uint16) -> None:
            value = uint16(value)
            self.reg = set_bit(self.reg, 12, get_bit(value, 0))
            self.reg = set_bit(self.reg, 13, get_bit(value, 1))
            self.reg = set_bit(self.reg, 14, get_bit(value, 2))
            self.fine_y = value

        def get_reg(self) -> uint16:
            return uint16(self.reg)

        def get_coarse_x(self) -> uint16:
            return uint16(self.coarse_x)

        def get_coarse_y(self) -> uint16:
            return uint16(self.coarse_y)

        def get_nametable_x(self) -> uint16:
            return uint16(self.nametable_x)

        def get_nametable_y(self) -> uint16:
            return uint16(self.nametable_y)

        def get_fine_y(self) -> uint16:
            return uint16(self.fine_y)

    patternTable: List[List[uint8]] = [[0x00] * 64 * 64] * 2
    nameTable: List[List[uint8]] = [[0x00] * 32 * 32] * 2
    paletteTable: List[uint8] = [0x00] * 32

    palettePanel: List[Pixel] = [None] * 4 * 16
    spriteScreen: Sprite = Sprite(256,240)
    spriteNameTable: List[Sprite] = [Sprite(256,240),Sprite(256,240)]
    spritePatternTable: List[Sprite] = [Sprite(128,128),Sprite(128,128)]

    status: Status = Status()
    mask: Mask = Mask()
    control: PPUCTRL = PPUCTRL()
    vram_addr: LoopRegister = LoopRegister()
    tram_addr: LoopRegister = LoopRegister()

    fine_x: uint8 = 0x00

    address_latch: uint8 = 0x00
    ppu_data_buffer: uint8 = 0x00

    scanline: uint16 = 0
    cycle: uint16 = 0

    background_next_tile_id: uint8 = 0x00
    background_next_tile_attribute: uint8 = 0x00
    background_next_tile_lsb: uint8 = 0x00
    background_next_tile_msb: uint8 = 0x00
    background_shifter_pattern_lo: uint16 = 0x0000
    background_shifter_pattern_hi: uint16 = 0x0000
    background_shifter_attribute_lo: uint16 = 0x0000
    background_shifter_attribute_hi: uint16 = 0x0000

    class sObjectAttributeEntry:
        y: uint8
        id: uint8
        attribute: uint8
        x: uint8

        def __init__(self) -> None:
            self.y = uint8(0)
            self.id = uint8(0)
            self.attribute = uint8(0)
            self.x = uint8(0)

    OAM: List[sObjectAttributeEntry] = [sObjectAttributeEntry()] * 64

    oam_addr: uint8 = 0x00

    spriteScanline: List[sObjectAttributeEntry] = [sObjectAttributeEntry()] * 8
    sprite_count: uint8
    sprite_shifter_pattern_lo: List[uint8] = [0x00] * 8
    sprite_shifter_pattern_hi: List[uint8] = [0x00] * 8

    bSpriteZeroHitPossible: bool = False
    bSpriteZeroBeingPossible: bool = False

    cartridge: Cartridge

    nmi: bool = False

    frame_complete: bool = False 

    bus: CPUBus

    def __init__(self, bus: CPUBus) -> None:
        self.bus = bus
        self.setPalettePanel()

    def connectCartridge(self, cartridge: Cartridge):
        self.cartridge = cartridge
    
    def getScreen(self) -> Sprite:
        return self.spriteScreen

    def readByCPU(self, addr: uint16, readonly: bool = False) -> uint8:
        addr, data = uint16(addr), uint8(0x00)

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
                data = uint8((self.status.get_reg() & 0xE0) | (self.ppu_data_buffer & 0x1F))
                self.status.set_vertical_blank(0)
                self.address_latch = 0
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
                data = self.ppu_data_buffer
                self.ppu_data_buffer = self.readByPPU(self.vram_addr.get_reg())
                if self.vram_addr.get_reg() >= 0x3F00:
                    data = self.ppu_data_buffer
                self.vram_addr.set_reg(uint16(self.vram_addr.get_reg() + 32 if self.control.get_increment_mode() == 1 else 1))      
        return uint8(data)

    def writeByCPU(self, addr: uint16, data: uint8) -> void:
        addr, data = uint16(addr), uint8(data)
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
            pass
        elif addr == 0x0004:
            # OAM Data
            pass
        elif addr == 0x0005:
            # Scroll
            if self.address_latch == 0:
                self.fine_x = uint8(data & 0x07)
                self.tram_addr.set_coarse_x(data >> 3)
                self.address_latch = 1
            else:
                self.tram_addr.set_fine_y(data & 0x07)
                self.tram_addr.set_coarse_y(data >> 3)
                self.address_latch = 0
        elif addr == 0x0006:
            # PPU Address
            if self.address_latch == 0:
                self.tram_addr.set_reg(uint16((data & 0x3F) << 8) | (self.tram_addr.get_reg() & 0x00FF))
                self.address_latch = 1
            else:
                self.tram_addr.set_reg((self.tram_addr.get_reg() & 0xFF00) | data)
                self.vram_addr = deepcopy(self.tram_addr)
                self.address_latch = 0
        elif addr == 0x0007:
            # PPU Data
            self.writeByPPU(self.vram_addr.get_reg(), data)
            self.vram_addr.set_reg(self.vram_addr.get_reg() + (32 if self.control.get_increment_mode() else 1))

    def readByPPU(self, addr: uint16, readonly: bool = False) -> uint8:
        addr, data = uint16(addr), uint8(0x00)
        addr &= 0x3FFF

        success, data = self.cartridge.readByPPU(addr)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            data = self.patternTable[(addr & 0x1000) >> 12][addr & 0x0FFF]
        elif 0x2000 <= addr <= 0x3EFF:
            addr &= 0x0FFF
            if self.cartridge.mirror == Cartridge.MIRROR.VERTICAL:
                if 0x0000 <= addr <= 0x03FF:
                    data = self.nameTable[0][addr & 0x03FF]
                elif 0x0400 <= addr <= 0x07FF:
                    data = self.nameTable[1][addr & 0x03FF]
                elif 0x0800 <= addr <= 0x0BFF:
                    data = self.nameTable[0][addr & 0x03FF]
                elif 0x0C00 <= addr <= 0x0FFF:
                    data = self.nameTable[1][addr & 0x03FF]                                 
            elif self.cartridge.mirror == Cartridge.MIRROR.HORIZONTAL:
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
            data = self.paletteTable[addr] & uint8(0x30 if self.mask.get_grayscale() == 1 else 0x3F)
        return uint8(data)

    def writeByPPU(self, addr: uint16, data: uint8) -> void:
        addr, data = uint16(addr), uint8(data)
        addr &= 0x3FFF     

        success = self.cartridge.writeByPPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            self.patternTable[(addr & 0x1000) >> 12][addr & 0x0FFF] = data
        elif 0x2000 <= addr <= 0x3EFF:
            addr &= 0x0FFF
            if self.cartridge.mirror == Cartridge.MIRROR.VERTICAL:
                if 0x0000 <= addr <= 0x03FF:
                    self.nameTable[0][addr & 0x03FF] = data
                if 0x0400 <= addr <= 0x07FF:
                    self.nameTable[1][addr & 0x03FF] = data
                if 0x0800 <= addr <= 0x0BFF:
                    self.nameTable[0][addr & 0x03FF] = data
                if 0x0C00 <= addr <= 0x0FFF:
                    self.nameTable[1][addr & 0x03FF] = data
            elif self.cartridge.mirror == Cartridge.MIRROR.HORIZONTAL:
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

    def setPalettePanel(self) -> void:    
        self.palettePanel[0x00],self.palettePanel[0x01],self.palettePanel[0x02],self.palettePanel[0x03],self.palettePanel[0x04],self.palettePanel[0x05],self.palettePanel[0x06],self.palettePanel[0x07],self.palettePanel[0x08],self.palettePanel[0x09],self.palettePanel[0x0a],self.palettePanel[0x0b],self.palettePanel[0x0c],self.palettePanel[0x0d],self.palettePanel[0x0e],self.palettePanel[0x0f] = Pixel( 84,  84,  84), Pixel(  0,  30, 116), Pixel(  8,  16, 144), Pixel( 48,   0, 136), Pixel( 68,   0, 100), Pixel( 92,   0,  48), Pixel( 84,   4,   0), Pixel( 60,  24,   0), Pixel( 32,  42,   0), Pixel(  8,  58,   0), Pixel(  0,  64,   0), Pixel(  0,  60,   0), Pixel(  0,  50,  60), Pixel(  0,   0,   0), Pixel(  0,   0,   0), Pixel(  0,   0,   0)
        self.palettePanel[0x10],self.palettePanel[0x11],self.palettePanel[0x12],self.palettePanel[0x13],self.palettePanel[0x14],self.palettePanel[0x15],self.palettePanel[0x16],self.palettePanel[0x17],self.palettePanel[0x18],self.palettePanel[0x19],self.palettePanel[0x1a],self.palettePanel[0x1b],self.palettePanel[0x1c],self.palettePanel[0x1d],self.palettePanel[0x1e],self.palettePanel[0x1f] = Pixel(152, 150, 152), Pixel(  8,  76, 196), Pixel( 48,  50, 236), Pixel( 92,  30, 228), Pixel(136,  20, 176), Pixel(160,  20, 100), Pixel(152,  34,  32), Pixel(120,  60,   0), Pixel( 84,  90,   0), Pixel( 40, 114,   0), Pixel(  8, 124,   0), Pixel(  0, 118,  40), Pixel(  0, 102, 120), Pixel(  0,   0,   0), Pixel(  0,   0,   0), Pixel(  0,   0,   0)
        self.palettePanel[0x20],self.palettePanel[0x21],self.palettePanel[0x22],self.palettePanel[0x23],self.palettePanel[0x24],self.palettePanel[0x25],self.palettePanel[0x26],self.palettePanel[0x27],self.palettePanel[0x28],self.palettePanel[0x29],self.palettePanel[0x2a],self.palettePanel[0x2b],self.palettePanel[0x2c],self.palettePanel[0x2d],self.palettePanel[0x2e],self.palettePanel[0x2f] = Pixel(236, 238, 236), Pixel( 76, 154, 236), Pixel(120, 124, 236), Pixel(176,  98, 236), Pixel(228,  84, 236), Pixel(236,  88, 180), Pixel(236, 106, 100), Pixel(212, 136,  32), Pixel(160, 170,   0), Pixel(116, 196,   0), Pixel( 76, 208,  32), Pixel( 56, 204, 108), Pixel( 56, 180, 204), Pixel( 60,  60,  60), Pixel(  0,   0,   0), Pixel(  0,   0,   0)
        self.palettePanel[0x30],self.palettePanel[0x31],self.palettePanel[0x32],self.palettePanel[0x33],self.palettePanel[0x34],self.palettePanel[0x35],self.palettePanel[0x36],self.palettePanel[0x37],self.palettePanel[0x38],self.palettePanel[0x39],self.palettePanel[0x3a],self.palettePanel[0x3b],self.palettePanel[0x3c],self.palettePanel[0x3d],self.palettePanel[0x3e],self.palettePanel[0x3f] = Pixel(236, 238, 236), Pixel(168, 204, 236), Pixel(188, 188, 236), Pixel(212, 178, 236), Pixel(236, 174, 236), Pixel(236, 174, 212), Pixel(236, 180, 176), Pixel(228, 196, 144), Pixel(204, 210, 120), Pixel(180, 222, 120), Pixel(168, 226, 144), Pixel(152, 226, 180), Pixel(160, 214, 228), Pixel(160, 162, 160), Pixel(  0,   0,   0), Pixel(  0,   0,   0)

    def showPalettePanel(self) -> void:
        rgb = zeros((4, 16, 3)).astype(uint8)
        for row in range(4):
            for col in range(16):
                pixel = self.palettePanel[row * 16 + col]
                rgb[row][col][0], rgb[row][col][1], rgb[row][col][2] = pixel.r, pixel.g, pixel.b
        plt.imshow(rgb)
        plt.axis('off')
        plt.show()

    def getColorFromPaletteTable(self, palette: uint8, pixel: uint8) -> Pixel:
        color = self.readByPPU(0x3F00 + (palette << 2) + pixel) & 0x3F
        # if color > 0:
        #     print("color: {color}".format(color=color))
        return self.palettePanel[self.readByPPU(0x3F00 + (palette << 2) + pixel) & 0x3F]

    def getPatternTable(self, i: uint8, palette: uint8) -> Sprite:
        for tileY in range(0,16):
            for tileX in range(0,16):
                offset: uint16 = tileY * 256 + tileX * 16
                for row in range(0,8):
                    tile_lsb: uint8 = self.readByPPU(i * 0x1000 + offset + row + 0x0000)
                    tile_msb: uint8 = self.readByPPU(i * 0x1000 + offset + row + 0x0008)
                    for col in range(0,8):
                        pixel: uint8 = (tile_lsb & 0x01) + (tile_msb & 0x01)
                        tile_lsb, tile_msb = tile_lsb >> 1, tile_msb >> 1
                        self.spritePatternTable[i].setPixel(
                            tileX * 8 + (7 - col),
                            tileY * 8 + row,
                            self.getColorFromPaletteTable(palette, pixel)
                        )
        
        return self.spritePatternTable[i]

    def reset(self) -> void:
        self.fine_x = uint8(0x00)
        self.address_latch = uint8(0x00)
        self.ppu_data_buffer = uint8(0x00)
        self.scanline, self.cycle  = uint16(0), uint16(0)
        self.background_next_tile_id = uint8(0x00)
        self.background_next_tile_attribute = uint8(0x00)
        self.background_next_tile_lsb, self.background_next_tile_msb = uint8(0x00), uint8(0x00)
        self.background_shifter_pattern_lo, self.background_shifter_pattern_hi = uint16(0x0000), uint16(0x0000)
        self.background_shifter_attribute_lo, self.background_shifter_attribute_hi = uint16(0x0000), uint16(0x0000)
        self.status.set_reg(0x00)
        self.mask.set_reg(0x00)
        self.control.set_reg(0x00)
        self.vram_addr.set_reg(0x0000)
        self.tram_addr.set_reg(0x0000)

    def clock(self, debug: bool = False) -> void:
        def incrementScrollX() -> None:
            if self.mask.get_render_background() == 1 or self.mask.get_render_sprites() == 1:
                if self.vram_addr.get_coarse_x() == 31:
                    self.vram_addr.set_coarse_x(0)
                    self.vram_addr.set_nametable_x(~self.vram_addr.get_nametable_x())
                else:
                    self.vram_addr.set_coarse_x(self.vram_addr.get_coarse_x() + 1)

        def incrementScrollY() -> None:
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

        def transferAddressX() -> None:
            if self.mask.get_render_background() == 1 or self.mask.get_render_sprites() == 1:
                self.vram_addr.set_nametable_x(self.tram_addr.get_nametable_x())
                self.vram_addr.set_coarse_x(self.tram_addr.get_coarse_x())

        def transferAddressY() -> None:
            if self.mask.get_render_background() == 1 or self.mask.get_render_sprites() == 1:
                self.vram_addr.set_fine_y(self.tram_addr.get_fine_y())
                self.vram_addr.set_nametable_y(self.tram_addr.get_nametable_y())
                self.vram_addr.set_coarse_y(self.tram_addr.get_coarse_y())

        def loadBackgroundShifters() -> None:
            self.background_shifter_pattern_lo = uint16((self.background_shifter_pattern_lo & 0xFF00) | self.background_next_tile_lsb)
            self.background_shifter_pattern_hi = uint16((self.background_shifter_pattern_hi & 0xFF00) | self.background_next_tile_msb) 
            self.background_shifter_attribute_lo = uint16(0xFF if ((self.background_shifter_attribute_lo & 0xFF00) | (self.background_next_tile_attribute & 0b01)) else 0x00)
            self.background_shifter_attribute_hi = uint16(0xFF if ((self.background_shifter_attribute_hi & 0xFF00) | (self.background_next_tile_attribute & 0b10)) else 0x00)

        def updateShifters() -> None:
            if self.mask.get_render_background() == 1:
                self.background_shifter_pattern_lo <<= 1
                self.background_shifter_pattern_hi <<= 1
                self.background_shifter_attribute_lo <<= 1
                self.background_shifter_attribute_hi <<= 1

        log = []
        if -1 <= self.scanline < 240:
            log.append("|-1 <= self.scanline < 240|")
            if self.scanline == 0 and self.cycle == 0:
                log.append("|self.scanline == 0 and self.cycle == 0|")
                self.cycle = 1
            if self.scanline == -1 and self.cycle == 1:
                log.append("|self.scanline == -1 and self.cycle == 1|")
                self.status.set_vertical_blank(uint8(0))
            if (2 <= self.cycle < 258) or (321 <= self.cycle < 338):
                log.append("|(2 <= self.cycle < 258) or (321 <= self.cycle < 338)|")
                updateShifters()
                v: uint16 = (self.cycle - 1) % 8
                if v == 0:
                    loadBackgroundShifters()
                    self.background_next_tile_id = self.readByPPU(0x2000 | (self.vram_addr.get_reg() & 0x0FFF))
                elif v == 2:
                    self.background_next_tile_attribute = self.readByPPU(0x23C0 \
                        | (self.vram_addr.get_nametable_y() << 11) \
                        | (self.vram_addr.get_nametable_x() << 10) \
                        | ((self.vram_addr.get_coarse_y() >> 2) << 3) \
                        | (self.vram_addr.get_coarse_x() >> 2)    
                    )
                    if self.vram_addr.get_coarse_y() & 0x02 > 0:
                        self.background_next_tile_attribute >>= uint8(4)
                    if self.vram_addr.get_coarse_x() & 0x02 > 0:
                        self.background_next_tile_attribute >>= uint8(2)
                    self.background_next_tile_attribute &= uint8(0x03)
                elif v == 4:
                    self.background_next_tile_lsb = self.readByPPU((self.control.get_pattern_background() << 12) \
                        + uint16(self.background_next_tile_id << 4) \
                        + (self.vram_addr.get_fine_y()) + 0
                    )
                elif v == 6:
                    self.background_next_tile_msb = self.readByPPU((self.control.get_pattern_background() << 12) \
                        + uint16(self.background_next_tile_id << 4) \
                        + (self.vram_addr.get_fine_y()) + 8
                    )
                elif v == 7:
                    incrementScrollX()
            if self.cycle == 256:
                log.append("|self.cycle == 256|")
                incrementScrollY()
            if self.cycle == 257:
                log.append("|self.cycle == 257|")
                loadBackgroundShifters()
                transferAddressX()
            if self.cycle == 338 or self.cycle == 340:
                log.append("|self.cycle == 338 or self.cycle == 340|")
                self.background_next_tile_id = self.readByPPU(0x2000 | (self.vram_addr.get_reg() & 0x0FFF))
            if self.scanline == -1 and 280 <= self.cycle < 305:
                log.append("|self.scanline == -1 and 280 <= self.cycle < 305|")
                transferAddressY()
        if self.scanline == 240:
            pass
        if 241 <= self.scanline < 261:
            log.append("|241 <= self.scanline < 261|")
            if self.scanline == 241 and self.cycle == 1:
                log.append("|self.scanline == 241 and self.cycle == 1|")
                self.status.set_vertical_blank(uint8(1))
                if self.control.get_enable_nmi():
                    self.nmi = True

        background_pixel: uint8 = 0x00
        background_palette: uint8 = 0x00
        if self.mask.get_render_background() == 1:
            bit_mux: uint16 = 0x8000 >> self.fine_x

            background_pixel_0: uint8 = (self.background_shifter_pattern_lo & bit_mux) > 0
            background_pixel_1: uint8 = (self.background_shifter_pattern_hi & bit_mux) > 0
            background_pixel = (background_pixel_0 << 1) | background_pixel_1

            background_palette_0: uint8 = (self.background_shifter_attribute_lo & bit_mux) > 0
            background_palette_1: uint8 = (self.background_shifter_attribute_hi & bit_mux) > 0
            background_palette = (background_palette_1 << 1) | background_palette_0
        
        self.spriteScreen.setPixel(self.cycle - 1, self.scanline, self.getColorFromPaletteTable(background_palette, background_pixel))
        
        # if debug:
        #     print(" -> ".join(log))

        self.cycle += 1
        if self.cycle >= 341:
            self.cycle = 0
            self.scanline += 1
            if self.scanline >= 261:
                self.scanline = -1
                self.frame_complete = True
                