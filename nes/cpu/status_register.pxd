from libc.stdint cimport uint32_t, uint8_t

cdef extern from "status_register.h":
    ctypedef union StatusUnion:
        uint32_t value

cdef class StatusRegister:
    cdef StatusUnion c_status
    
    cdef StatusUnion get_union(self)
    cdef void set_union(self, StatusUnion val)