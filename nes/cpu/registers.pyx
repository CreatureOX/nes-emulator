cdef class StatusRegister:
    def __init__(self):
        self.value = 0
        self.status_mask = {
            "C": 1 << 0, # Carry Bit
            "Z": 1 << 1, # Zero
            "I": 1 << 2, # Disable Interrupts
            "D": 1 << 3, # Decimal Mode
            "B": 1 << 4, # Break
            "U": 1 << 5, # Unused
            "V": 1 << 6, # Overflow
            "N": 1 << 7 # Negative
        }

    cdef void _set_status(self, uint8_t mask, bint value):
        if value:
            self.value |= mask
        else:
            self.value &= ~mask

    cdef bint _get_status(self, uint8_t mask):
        return self.value & mask > 0

    @property
    def C(self):
        return self._get_status(self.status_mask["C"])

    @property
    def Z(self):
        return self._get_status(self.status_mask["Z"])

    @property
    def I(self):
        return self._get_status(self.status_mask["I"])

    @property
    def D(self):
        return self._get_status(self.status_mask["D"])

    @property
    def B(self):
        return self._get_status(self.status_mask["B"])

    @property
    def U(self):
        return self._get_status(self.status_mask["U"])

    @property
    def V(self):
        return self._get_status(self.status_mask["V"])

    @property
    def N(self):
        return self._get_status(self.status_mask["N"])

    @C.setter
    def C(self, bint value):
        self._set_status(self.status_mask["C"], value)

    @Z.setter
    def Z(self, bint value):
        self._set_status(self.status_mask["Z"], value)

    @I.setter
    def I(self, bint value):
        self._set_status(self.status_mask["I"], value)

    @D.setter
    def D(self, bint value):
        self._set_status(self.status_mask["D"], value)

    @B.setter
    def B(self, bint value):
        self._set_status(self.status_mask["B"], value)

    @U.setter
    def U(self, bint value):
        self._set_status(self.status_mask["U"], value)

    @V.setter
    def V(self, bint value):
        self._set_status(self.status_mask["V"], value)

    @N.setter
    def N(self, bint value):
        self._set_status(self.status_mask["N"], value)

cdef class Registers:
    def __init__(self):
        self.program_counter = 0x0000    
        self.stack_pointer = 0x00
        self.accumulator = 0x00
        self.index_X = 0x00                
        self.index_Y = 0x00
        self.status = StatusRegister()

    @property
    def PC(self):
        return self.program_counter

    @property
    def SP(self):
        return self.stack_pointer

    @property
    def A(self):
        return self.accumulator

    @property
    def X(self):
        return self.index_X

    @property
    def Y(self):
        return self.index_Y

    @property
    def P(self):
        return self.status.value

    @PC.setter
    def PC(self, long program_counter):
        self.program_counter = <uint16_t> program_counter & 0xFFFF

    @SP.setter
    def SP(self, long stack_pointer):
        self.stack_pointer = <uint8_t> stack_pointer & 0xFF

    @A.setter
    def A(self, long accumulator):
        self.accumulator = accumulator & 0xFF

    @X.setter
    def X(self, long index_X):
        self.index_X = <uint8_t> index_X & 0xFF

    @Y.setter
    def Y(self, long index_Y):
        self.index_Y = <uint8_t> index_Y & 0xFF

    @P.setter
    def P(self, long status_value):
        self.status.value = <uint8_t> status_value & 0xFF
