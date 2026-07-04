from libc.stdint cimport uint8_t, uint32_t


cdef class CPUReadMapping:
    """
    Result structure for CPU read address mapping.
    
    Attributes:
        success: Whether the address is mapped to cartridge space
        addr: Translated address in cartridge's PRG ROM/RAM space
        data: Direct data value (for register-mapped reads)
    """
    def __init__(self) -> None:
        self.success = False
        self.addr = 0x00000000
        self.data = 0x00

cdef class CPUWriteMapping:
    """
    Result structure for CPU write address mapping.
    
    Attributes:
        success: Whether the address is mapped to cartridge space
        addr: Translated address in cartridge's PRG ROM/RAM space
    """
    def __init__(self) -> None:
        self.success = False
        self.addr = 0x00000000

cdef class PPUReadMapping:
    """
    Result structure for PPU read address mapping.
    
    Attributes:
        success: Whether the address is mapped to cartridge space
        addr: Translated address in cartridge's CHR ROM/RAM space
    """
    def __init__(self) -> None:
        self.success = False
        self.addr = 0x00000000

cdef class PPUWriteMapping:
    """
    Result structure for PPU write address mapping.
    
    Attributes:
        success: Whether the address is mapped to cartridge space
        addr: Translated address in cartridge's CHR RAM space
    """
    def __init__(self) -> None:
        self.success = False
        self.addr = 0x00000000