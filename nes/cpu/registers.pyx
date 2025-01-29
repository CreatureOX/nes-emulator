cdef class Registers:
    def __init__(self):
        self.PC = 0x0000    
        self.SP = 0x00
        self.A = 0x00
        self.X = 0x00                
        self.Y = 0x00

    @property
    def P(self):
        return self.status.value

    @P.setter
    def P(self, long status_value):
        self.status.value = <uint8_t> status_value & 0xFF

    def __reduce__(self):
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
        self.PC = state['PC']
        self.SP = state['SP']
        self.A = state['A']
        self.X = state['X']
        self.Y = state['Y']
        self.P = state['P']
