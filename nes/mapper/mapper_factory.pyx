from nes.mapper.mapper_nrom cimport MapperNROM
from nes.mapper.mapper_mmc1 cimport MapperMMC1
from nes.mapper.mapper_uxrom cimport MapperUxROM
from nes.mapper.mapper_ines003 cimport MapperINES003
from nes.mapper.mapper_mmc3 cimport MapperMMC3
from nes.mapper.mapper_gxrom cimport MapperGxROM


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
