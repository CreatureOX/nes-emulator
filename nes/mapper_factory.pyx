from mapper_nrom cimport MapperNROM
from mapper_mmc1 cimport MapperMMC1
from mapper_uxrom cimport MapperUxROM
from mapper_ines003 cimport MapperINES003
from mapper_mmc3 cimport MapperMMC3
from mapper_gxrom cimport MapperGxROM


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
