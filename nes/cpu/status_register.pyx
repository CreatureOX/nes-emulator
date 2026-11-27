from libc.stdint cimport uint32_t

cdef class StatusRegister:
    """MOS 6502 Processor Status Register.

    Each flag is a C-level bint field; ``status.flag_C`` etc. compile to
    direct struct access on the CPU hot path. ``value`` is the packed 8-bit
    view used by PHP/PLP and the debugger, rebuilt on demand from the fields.
    """

    def __cinit__(self):
        self.flag_C = False
        self.flag_Z = False
        self.flag_I = False
        self.flag_D = False
        self.flag_B = False
        # value=0 on init in the original union implementation; clock() sets
        # U on every cycle, so keep the same initial state for byte-exactness.
        self.flag_U = False
        self.flag_V = False
        self.flag_N = False

    @property
    def value(self):
        return ((<uint32_t>self.flag_C)
                | ((<uint32_t>self.flag_Z) << 1)
                | ((<uint32_t>self.flag_I) << 2)
                | ((<uint32_t>self.flag_D) << 3)
                | ((<uint32_t>self.flag_B) << 4)
                | ((<uint32_t>self.flag_U) << 5)
                | ((<uint32_t>self.flag_V) << 6)
                | ((<uint32_t>self.flag_N) << 7))

    @value.setter
    def value(self, uint32_t val):
        self.flag_C = val & 0x01 != 0
        self.flag_Z = val & 0x02 != 0
        self.flag_I = val & 0x04 != 0
        self.flag_D = val & 0x08 != 0
        self.flag_B = val & 0x10 != 0
        self.flag_U = val & 0x20 != 0
        self.flag_V = val & 0x40 != 0
        self.flag_N = val & 0x80 != 0
