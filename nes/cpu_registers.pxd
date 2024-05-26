from libc.stdint cimport uint8_t, uint16_t

cdef class StatusRegister:
    cdef uint8_t value
    cdef dict status_mask

    cdef void _set_status(self, uint8_t, bint)
    cdef bint _get_status(self, uint8_t)

cdef class Registers:
    cdef public uint16_t program_counter    
    cdef public uint8_t stack_pointer
    cdef public uint8_t accumulator
    cdef public uint8_t index_X
    cdef public uint8_t index_Y
    cdef public StatusRegister status
