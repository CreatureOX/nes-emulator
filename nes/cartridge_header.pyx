cdef class Header:
    def __init__(self, bytes bytes) -> None:
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
