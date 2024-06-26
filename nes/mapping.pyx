from libc.stdint cimport uint8_t, uint32_t


cdef class CPUReadMapping:
    def __init__(self) -> None:
        self.success = False
        self.addr = 0x00000000
        self.data = 0x00

cdef class CPUWriteMapping:
    def __init__(self) -> None:
        self.success = False
        self.addr = 0x00000000

cdef class PPUReadMapping:
    def __init__(self) -> None:
        self.success = False
        self.addr = 0x00000000

cdef class PPUWriteMapping:
    def __init__(self) -> None:
        self.success = False
        self.addr = 0x00000000
