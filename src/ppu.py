from typing import List
from matplotlib import pyplot as plt
from numpy import array, uint16, uint8, void


class Tile:
    bytes: bytes
    matrix: List[List[uint8]]

    def __init__(self, bytes: bytes) -> None:
        self.bytes = bytes[:8]
        self.matrix = []
        for byte in bytes:
            str = bin(byte).replace("b","").zfill(8)
            self.matrix.append([int(chr) for chr in str])

    def __str__(self):
        strs = ["".join([str(i) for i in row]) for row in self.matrix]
        return "\n".join([str for str in strs])

    @classmethod
    def combine(cls, msbTile, lsbTile) -> List[List[uint8]]:
        result = []
        for i in range(8):
            msbStr, lsbStr = bin(msbTile.bytes[i]).replace("b","").zfill(8), bin(lsbTile.bytes[i]).replace("b","").zfill(8)
            msbList, lsbList = [int(i) for i in msbStr], [int(i) for i in lsbStr]
            list = [msbList[i]<<1 | lsbList[i] for i in range(8)]
            result.append(list)
        return result

class PPU2C02:
    patternTables: List[List[bytes]]
    nameTable: List[bytes]
    paletteTable: List[bytes]
    
    cycle: uint16
    scanline: uint16

    def __init__(self) -> None:
        self.nameTable = [None] * 2
        self.paletteTable = [None] * 4 * 16
        self.patternTables = [[None] * 64 * 64] * 2

    def readByCPU(self, addr: uint16, readonly: bool = False) -> uint8:
        data: uint8 = 0x00

        if addr == 0x0000:
            # Control
            pass
        elif addr == 0x0001:
            # Mask
            pass
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
            pass
        elif addr == 0x0006:
            # PPU Address
            pass
        elif addr == 0x0007:
            # PPU Data
            pass

        return data

    def writeByCPU(self, addr: uint16, data: uint8) -> void:
        pass

    def readByPPU(self, addr: uint16, readonly: bool = False) -> uint8:
        data: uint8 = 0x00
        addr &= 0x3FFF

        return data

    def writeByPPU(self, addr: uint16, data: uint8) -> void:
        addr &= 0x3FFF     

    def clock(self) -> void:
        self.cycle += 1
        if self.cycle >= 341:
            self.cycle = 0

    def drawPattern(self, index: int, scale: int = 1) -> void:
        plt.figure(figsize=(scale,scale))

        patternTable = self.patternTables[index]
        for i in range(0, len(patternTable), 16):
            plt.subplot(16,16,i//16+1)
            msb, lsb = Tile(patternTable[i:i+8]), Tile(patternTable[i+8:i+16])
            combined = Tile.combine(msb, lsb)
            plt.imshow(combined)
            plt.axis('off')
        plt.show()        

    def setPalette(self) -> void:    
        self.paletteTable[0x00],self.paletteTable[0x01],self.paletteTable[0x02],self.paletteTable[0x03],self.paletteTable[0x04],self.paletteTable[0x05],self.paletteTable[0x06],self.paletteTable[0x07],self.paletteTable[0x08],self.paletteTable[0x09],self.paletteTable[0x0a],self.paletteTable[0x0b],self.paletteTable[0x0c],self.paletteTable[0x0d],self.paletteTable[0x0e],self.paletteTable[0x0f] = ( 84,  84,  84), (  0,  30, 116), (  8,  16, 144), ( 48,   0, 136), ( 68,   0, 100), ( 92,   0,  48), ( 84,   4,   0), ( 60,  24,   0), ( 32,  42,   0), (  8,  58,   0), (  0,  64,   0), (  0,  60,   0), (  0,  50,  60), (  0,   0,   0), (  0,   0,   0), (  0,   0,   0)
        self.paletteTable[0x10],self.paletteTable[0x11],self.paletteTable[0x12],self.paletteTable[0x13],self.paletteTable[0x14],self.paletteTable[0x15],self.paletteTable[0x16],self.paletteTable[0x17],self.paletteTable[0x18],self.paletteTable[0x19],self.paletteTable[0x1a],self.paletteTable[0x1b],self.paletteTable[0x1c],self.paletteTable[0x1d],self.paletteTable[0x1e],self.paletteTable[0x1f] = (152, 150, 152), (  8,  76, 196), ( 48,  50, 236), ( 92,  30, 228), (136,  20, 176), (160,  20, 100), (152,  34,  32), (120,  60,   0), ( 84,  90,   0), ( 40, 114,   0), (  8, 124,   0), (  0, 118,  40), (  0, 102, 120), (  0,   0,   0), (  0,   0,   0), (  0,   0,   0)
        self.paletteTable[0x20],self.paletteTable[0x21],self.paletteTable[0x22],self.paletteTable[0x23],self.paletteTable[0x24],self.paletteTable[0x25],self.paletteTable[0x26],self.paletteTable[0x27],self.paletteTable[0x28],self.paletteTable[0x29],self.paletteTable[0x2a],self.paletteTable[0x2b],self.paletteTable[0x2c],self.paletteTable[0x2d],self.paletteTable[0x2e],self.paletteTable[0x2f] = (236, 238, 236), ( 76, 154, 236), (120, 124, 236), (176,  98, 236), (228,  84, 236), (236,  88, 180), (236, 106, 100), (212, 136,  32), (160, 170,   0), (116, 196,   0), ( 76, 208,  32), ( 56, 204, 108), ( 56, 180, 204), ( 60,  60,  60), (  0,   0,   0), (  0,   0,   0)
        self.paletteTable[0x30],self.paletteTable[0x31],self.paletteTable[0x32],self.paletteTable[0x33],self.paletteTable[0x34],self.paletteTable[0x35],self.paletteTable[0x36],self.paletteTable[0x37],self.paletteTable[0x38],self.paletteTable[0x39],self.paletteTable[0x3a],self.paletteTable[0x3b],self.paletteTable[0x3c],self.paletteTable[0x3d],self.paletteTable[0x3e],self.paletteTable[0x3f] = (236, 238, 236), (168, 204, 236), (188, 188, 236), (212, 178, 236), (236, 174, 236), (236, 174, 212), (236, 180, 176), (228, 196, 144), (204, 210, 120), (180, 222, 120), (168, 226, 144), (152, 226, 180), (160, 214, 228), (160, 162, 160), (  0,   0,   0), (  0,   0,   0)

    def drawPalette(self, scale: int = 1) -> void:
        plt.figure(figsize=(scale,scale))

        matrix = array(self.paletteTable).reshape((4,16,3))
        plt.imshow(matrix)
        plt.axis('off')
        plt.show()
