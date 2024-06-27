from mapper cimport Mapper


cdef class MapperFactory:
    @staticmethod
    cdef Mapper of(int mapper_no)
