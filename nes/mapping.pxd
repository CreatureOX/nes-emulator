from libc.stdint cimport uint8_t, uint32_t


cdef class CPUReadMapping:
    cdef bint success
    cdef uint32_t addr
    cdef uint8_t data

cdef class CPUWriteMapping:
    cdef bint success
    cdef uint32_t addr

cdef class PPUReadMapping:
    cdef bint success
    cdef uint32_t addr

cdef class PPUWriteMapping:
    cdef bint success
    cdef uint32_t addr
