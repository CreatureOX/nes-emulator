from libc.stdint cimport uint32_t

cdef class StatusRegister:
    """6502 P register as eight independent C-level flag fields.

    Each flag is a ``cdef public bint`` so CPU hot-path reads/writes compile
    to direct struct accesses instead of Python property calls. The packed
    ``value`` view is reconstructed on demand for PHP/PLP and save states.
    """
    cdef public bint flag_C
    cdef public bint flag_Z
    cdef public bint flag_I
    cdef public bint flag_D
    cdef public bint flag_B
    cdef public bint flag_U
    cdef public bint flag_V
    cdef public bint flag_N
