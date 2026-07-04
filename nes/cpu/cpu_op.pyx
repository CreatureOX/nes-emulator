cdef class Op:
    """
    CPU instruction definition combining operation, address mode, and cycle count.
    
    Used to build the 6502 instruction lookup table with all 151 official
    opcodes plus unofficial opcodes.
    """
    def __init__(self, str name, object operate, object addrmode, int cycles):
        self.name = name
        self.operate = operate
        self.addrmode = addrmode
        self.cycles = cycles