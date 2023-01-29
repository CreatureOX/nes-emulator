from typing import Tuple, List
from numpy import uint16, uint8, frombuffer, array

from mirror import *
from mapper import Mapper, Mapper000, Mapper001, Mapper002, Mapper003, Mapper004, Mapper066


class Header:
    name: str
    prg_rom_chunks: uint8
    chr_rom_chunks: uint8
    mapper1: uint8
    mapper2: uint8
    prg_ram_size: uint8
    tv_system1: uint8
    tv_system2: uint8
    unused: str

    def __init__(self, bytes: bytes) -> None:
        self.name = bytes[0:3+1].decode("UTF-8")
        self.prg_rom_chunks = bytes[4]
        self.chr_rom_chunks = bytes[5]
        self.mapper1 = bytes[6]
        self.mapper2 = bytes[7]
        self.prg_ram_size = bytes[8]
        self.tv_system1 = bytes[9]
        self.tv_system2 = bytes[10]
        self.unused = bytes[11:15+1].decode("UTF-8")
        
    def __str__(self) -> str:
        return "name={0}\nprg_rom_chunks={1}\nchr_rom_chunks={2}\nmapper1={3}\nmapper2={4}\nprg_ram_size={5}\ntv_system1={6}\ntv_system2={7}\nunused={8}"\
            .format(self.name,\
                self.prg_rom_chunks,\
                self.chr_rom_chunks,\
                bin(self.mapper1),\
                bin(self.mapper2),\
                self.prg_ram_size,\
                bin(self.tv_system1),\
                bin(self.tv_system2),
                self.unused)

class Cartridge:
    header: Header
    trainer: bytes
    PRGMemory: List[uint8]
    CHRMemory: List[uint8]
    playChoiceINSTMemory: bytes
    playChoicePMemory: bytes

    mapper: Mapper
    mirror: int

    def __init__(self, filename: str) -> None:
        with open(filename, 'rb') as nes:
            self.header = Header(nes.read(16))

            if self.header.mapper1 & 0b100 != 0:
                self.trainer = nes.read(512)
            
            mapperNo = ((self.header.mapper2 >> 4)) << 4 | (self.header.mapper1 >> 4)
            self.mirror = VERTICAL if self.header.mapper1 & 0x01 else HORIZONTAL
            
            fileType: uint8 = 1
            if self.header.mapper2 & 0x0C == 0x08:
                fileType = 2
            
            if fileType == 0:
                pass
            if fileType == 1:
                PRGBanks = self.header.prg_rom_chunks
                self.PRGMemory = frombuffer(nes.read(16384 * PRGBanks), dtype=uint8).copy()
                
                CHRBanks = self.header.chr_rom_chunks
                if CHRBanks == 0:
                    chrMemory = frombuffer(nes.read(8192), dtype=uint8).copy()
                    self.CHRMemory = array([0x00] * 8192, dtype=uint8) if len(chrMemory) == 0 else chrMemory
                else:
                    self.CHRMemory = frombuffer(nes.read(8192 * CHRBanks), dtype=uint8).copy()
                
                if self.header.mapper2 & 0b10 != 0:
                    self.playChoiceINSTMemory = nes.read(8192)
                    self.playChoicePMemory = nes.read(16)
            if fileType == 2:
                PRGBanks = (self.header.prg_ram_size & 0x07) << 8 | self.header.prg_rom_chunks
                self.PRGMemory = frombuffer(nes.read(16384 * PRGBanks), dtype=uint8).copy()

                CHRBanks = (self.header.prg_ram_size & 0x38) << 8 | self.header.chr_rom_chunks
                self.CHRMemory = frombuffer(nes.read(8192 * CHRBanks), dtype=uint8).copy()

            if mapperNo == 000:
                self.mapper = Mapper000(PRGBanks, CHRBanks)
            elif mapperNo == 1:
                self.mapper = Mapper001(PRGBanks, CHRBanks)
            elif mapperNo == 2:
                self.mapper = Mapper002(PRGBanks, CHRBanks)
            elif mapperNo == 3:
                self.mapper = Mapper003(PRGBanks, CHRBanks)
            elif mapperNo == 4:
                self.mapper = Mapper004(PRGBanks, CHRBanks)
            elif mapperNo == 66:
                self.mapper = Mapper066(PRGBanks, CHRBanks)

    def readByCPU(self, addr: uint16) -> Tuple[bool, uint8]:
        success, mapped_addr, data = self.mapper.mapReadByCPU(addr)
        if success:
            if mapped_addr == 0xFFFFFFFF:
                return (True, data)
            else:
                return (True, self.PRGMemory[mapped_addr])
        else:
            return (False, data)

        # success, mapped_addr = self.mapper.mapReadByCPU(addr)
        # return (success, self.PRGMemory[mapped_addr] if success else 0x00)

    def writeByCPU(self, addr: uint16, data: uint8) -> bool:
        success, mapped_addr = self.mapper.mapWriteByCPU(addr, data)
        if success:
            if mapped_addr == 0xFFFFFFFF:
                return True
            else:
               self.PRGMemory[mapped_addr] = data
               return True
        else:
            return False 

        # success, mapped_addr = self.mapper.mapWriteByCPU(addr)
        # if success:
        #     self.PRGMemory[mapped_addr] = data
        # return success

    def readByPPU(self, addr: uint16) -> Tuple[bool, uint8]:
        success, mapped_addr = self.mapper.mapReadByPPU(addr)
        return (success, self.CHRMemory[mapped_addr] if success else 0x00)

    def writeByPPU(self, addr: uint16, data: uint8) -> bool:
        success, mapped_addr = self.mapper.mapWriteByPPU(addr)
        if success:
            self.CHRMemory[mapped_addr] = data
        return success

    def connectBus(self, bus):
        self.bus = bus

    def reset(self):
        if self.mapper is not None:
            self.mapper.reset()

    def getMirror(self) -> uint8:
        m = self.mapper.mirror()
        if m == HARDWARE:
            return self.mirror
        else:
            return m

    def getMapper(self):
        return self.mapper
    