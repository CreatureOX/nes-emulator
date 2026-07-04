from libc.stdint cimport uint32_t

cdef extern from "status_register.h" nogil:
    ctypedef union StatusUnion:
        uint32_t value
    
    cdef int STATUS_CARRY
    cdef int STATUS_ZERO
    cdef int STATUS_INTERRUPT
    cdef int STATUS_DECIMAL
    cdef int STATUS_BREAK
    cdef int STATUS_UNUSED
    cdef int STATUS_OVERFLOW
    cdef int STATUS_NEGATIVE

cdef class StatusRegister:
    """
    MOS 6502 Processor Status Register.
    
    8-bit register with individual flag bits:
    - C (Carry): Set after arithmetic operations
    - Z (Zero): Set when result is zero
    - I (Interrupt): Interrupt disable flag
    - D (Decimal): Decimal mode (NES unused)
    - B (Break): Break command flag
    - U (Unused): Always set
    - V (Overflow): Set after signed arithmetic
    - N (Negative): Set when result is negative
    """
    
    def __init__(self):
        """Initialize status register to 0x20 (U bit always set)."""
        self.c_status.value = 0
    
    cdef StatusUnion get_union(self):
        return self.c_status
    
    cdef void set_union(self, StatusUnion val):
        self.c_status = val
    
    @property
    def bits(self):
        """Returns self, supports .bits.C, .bits.Z access"""
        return self
    
    @property
    def value(self):
        return self.c_status.value
    
    @value.setter
    def value(self, uint32_t val):
        self.c_status.value = val
    
    @property
    def C(self):
        """Carry flag - bit 0."""
        return (self.c_status.value >> 0) & 1
    
    @C.setter  
    def C(self, val):
        if val:
            self.c_status.value |= 0x01
        else:
            self.c_status.value &= ~0x01
    
    @property
    def Z(self):
        """Zero flag - bit 1."""
        return (self.c_status.value >> 1) & 1
    
    @Z.setter
    def Z(self, val):
        if val:
            self.c_status.value |= 0x02
        else:
            self.c_status.value &= ~0x02
    
    @property
    def I(self):
        """Interrupt disable flag - bit 2."""
        return (self.c_status.value >> 2) & 1
    
    @I.setter
    def I(self, val):
        if val:
            self.c_status.value |= 0x04
        else:
            self.c_status.value &= ~0x04
    
    @property
    def D(self):
        """Decimal mode flag - bit 3 (unused on NES)."""
        return (self.c_status.value >> 3) & 1
    
    @D.setter
    def D(self, val):
        if val:
            self.c_status.value |= 0x08
        else:
            self.c_status.value &= ~0x08
    
    @property
    def B(self):
        """Break command flag - bit 4."""
        return (self.c_status.value >> 4) & 1
    
    @B.setter
    def B(self, val):
        if val:
            self.c_status.value |= 0x10
        else:
            self.c_status.value &= ~0x10
    
    @property
    def U(self):
        """Unused flag (always 1) - bit 5."""
        return (self.c_status.value >> 5) & 1
    
    @U.setter
    def U(self, val):
        if val:
            self.c_status.value |= 0x20
        else:
            self.c_status.value &= ~0x20
    
    @property
    def V(self):
        """Overflow flag - bit 6."""
        return (self.c_status.value >> 6) & 1
    
    @V.setter
    def V(self, val):
        if val:
            self.c_status.value |= 0x40
        else:
            self.c_status.value &= ~0x40
    
    @property
    def N(self):
        """Negative flag - bit 7."""
        return (self.c_status.value >> 7) & 1
    
    @N.setter
    def N(self, val):
        if val:
            self.c_status.value |= 0x80
        else:
            self.c_status.value &= ~0x80