from enum import Enum
from typing import Tuple
from numpy import uint16, uint8

from src.mapper import Mapper, Mapper000


class Cartridge:
    class MIRROR(Enum):
        HORIZONTAL = 0
        VERTICAL = 1

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

    header: Header
    trainer: bytes
    PRGMemory: bytes
    CHRMemory: bytes
    playChoiceINSTMemory: bytes
    playChoicePMemory: bytes

    mapper: Mapper

    def __init__(self, filename: str) -> None:
        with open(filename, 'rb') as nes:
            self.header = self.Header(nes.read(16))

            if self.header.mapper1 & 0b100 != 0:
                self.trainer = nes.read(512)
            
            PRGBanks = 16384 * self.header.prg_rom_chunks
            self.PRGMemory = nes.read(PRGBanks)

            CHRBanks = 8192 * self.header.chr_rom_chunks
            self.CHRMemory = nes.read(CHRBanks)

            if self.header.mapper2 & 0b10 != 0:
                self.playChoiceINSTMemory = nes.read(8192)
                self.playChoicePMemory = nes.read(16)

            mapperNo = ((self.header.mapper2 >> 4)) << 4 | (self.header.mapper1 >> 4)
            if mapperNo == 000:
                self.mapper = Mapper000(PRGBanks, CHRBanks)
            
    def readByCPU(self, addr: uint16) -> Tuple[bool, uint8]:
        success, mapped_addr = self.mapper.mapReadByCPU(addr)
        return (success, self.PRGMemory[mapped_addr])

    def writeByCPU(self, addr: uint16, data: uint8) -> bool:
        success, mapped_addr = self.mapper.mapWriteByCPU(addr)
        if success:
            self.PRGMemory[mapped_addr] = data
        return success

    def readByPPU(self, addr: uint16) -> Tuple[bool, uint8]:
        success, mapped_addr = self.mapper.mapReadByPPU(addr)
        return (success, self.CHRMemory[mapped_addr])

    def writeByPPU(self, addr: uint16, data: uint8) -> bool:
        success, mapped_addr = self.mapper.mapWriteByPPU(addr)
        if success:
            self.CHRMemory[mapped_addr] = data
        return success