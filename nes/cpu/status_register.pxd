from libc.stdint cimport uint32_t

cdef extern from "status_register.h":
    ctypedef union StatusUnion:
        uint32_t value

cdef class StatusRegister:
    cdef StatusUnion c_status
