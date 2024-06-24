from mapper cimport MapperNROM, MapperMMC1, MapperUxROM, MapperINES003, MapperMMC3, MapperGxROM


mappers = {
    "000": MapperNROM,
    "001": MapperMMC1,
    "002": MapperUxROM,
    "003": MapperINES003,
    "004": MapperMMC3,
    "066": MapperGxROM,
}

cdef class MapperFactory:
    @staticmethod
    cdef Mapper of(int mapper_no):
        mapper_name = "{:03d}".format(mapper_no)
        return <Mapper> mappers[mapper_name]
