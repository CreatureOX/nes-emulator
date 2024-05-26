cdef class Op:
    def __init__(self, str name, object operate, object addrmode, int cycles):
        self.name = name
        self.operate = operate
        self.addrmode = addrmode
        self.cycles = cycles
