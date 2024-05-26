cdef class Op:
    cdef public str name
    cdef public object operate
    cdef public object addrmode
    cdef public int cycles
