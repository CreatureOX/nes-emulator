from libc.stdint cimport uint32_t

cdef extern from "status_register.h":
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
    """状态寄存器的Cython包装类，使用掩码操作而不是位字段"""
    
    def __init__(self):
        """初始化状态寄存器为0"""
        self.c_status.value = 0
    
    cdef StatusUnion get_union(self):
        return self.c_status
    
    cdef void set_union(self, StatusUnion val):
        self.c_status = val
    
    @property
    def bits(self):
        """返回自己，支持 .bits.C, .bits.Z 等访问方式"""
        return self
    
    @property
    def value(self):
        return self.c_status.value
    
    @value.setter
    def value(self, uint32_t val):
        self.c_status.value = val
    
    @property
    def C(self):
        return (self.c_status.value >> 0) & 1
    
    @C.setter  
    def C(self, val):
        if val:
            self.c_status.value |= 0x01
        else:
            self.c_status.value &= ~0x01
    
    @property
    def Z(self):
        return (self.c_status.value >> 1) & 1
    
    @Z.setter
    def Z(self, val):
        if val:
            self.c_status.value |= 0x02
        else:
            self.c_status.value &= ~0x02
    
    @property
    def I(self):
        return (self.c_status.value >> 2) & 1
    
    @I.setter
    def I(self, val):
        if val:
            self.c_status.value |= 0x04
        else:
            self.c_status.value &= ~0x04
    
    @property
    def D(self):
        return (self.c_status.value >> 3) & 1
    
    @D.setter
    def D(self, val):
        if val:
            self.c_status.value |= 0x08
        else:
            self.c_status.value &= ~0x08
    
    @property
    def B(self):
        return (self.c_status.value >> 4) & 1
    
    @B.setter
    def B(self, val):
        if val:
            self.c_status.value |= 0x10
        else:
            self.c_status.value &= ~0x10
    
    @property
    def U(self):
        return (self.c_status.value >> 5) & 1
    
    @U.setter
    def U(self, val):
        if val:
            self.c_status.value |= 0x20
        else:
            self.c_status.value &= ~0x20
    
    @property
    def V(self):
        return (self.c_status.value >> 6) & 1
    
    @V.setter
    def V(self, val):
        if val:
            self.c_status.value |= 0x40
        else:
            self.c_status.value &= ~0x40
    
    @property
    def N(self):
        return (self.c_status.value >> 7) & 1
    
    @N.setter
    def N(self, val):
        if val:
            self.c_status.value |= 0x80
        else:
            self.c_status.value &= ~0x80
