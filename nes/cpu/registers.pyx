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
