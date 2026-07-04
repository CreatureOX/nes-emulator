cdef extern from "status_register.h":
    pass

from nes.cpu.status_register cimport StatusRegister

cdef class Registers:
    """
    MOS 6502 CPU register set.
    
    Contains the Program Counter (PC), Stack Pointer (SP),
    Accumulator (A), and Index Registers (X, Y).
    """
    def __init__(self):
        self.PC = 0x0000    
        self.SP = 0x00
        self.A = 0x00
        self.X = 0x00                
        self.Y = 0x00
        self.status = StatusRegister()

    @property
    def P(self):
        """Get processor status register."""
        return self.status.value

    @P.setter
    def P(self, long status_value):
        """Set processor status register."""
        self.status.value = <uint8_t> status_value & 0xFF

    def __reduce__(self):
        """Support for pickling (save/load state)."""
        state = {
            'PC': self.PC,
            'SP': self.SP,
            'A': self.A,
            'X': self.X,
            'Y': self.Y,
            'P': self.P
        }
        return (self.__class__, (), state)

    def __setstate__(self, state):
        """Restore state from pickle."""
        self.PC = state['PC']
        self.SP = state['SP']
        self.A = state['A']
        self.X = state['X']
        self.Y = state['Y']
        self.P = state['P']