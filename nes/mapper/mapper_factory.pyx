from nes.mapper.impl.mapper_nrom cimport MapperNROM
from nes.mapper.impl.mapper_mmc1 cimport MapperMMC1
from nes.mapper.impl.mapper_uxrom cimport MapperUxROM
from nes.mapper.impl.mapper_ines003 cimport MapperINES003
from nes.mapper.impl.mapper_mmc3 cimport MapperMMC3
from nes.mapper.impl.mapper_gxrom cimport MapperGxROM


mappers = {
    "000": MapperNROM,
    "001": MapperMMC1,
    "002": MapperUxROM,
    "003": MapperINES003,
    "004": MapperMMC3,
    "066": MapperGxROM,
}

cdef class MapperFactory:
    """
    Resolve an iNES mapper number to its implementation class.

    The `mappers` registry is the authoritative list of supported boards.
    """
    @staticmethod
    cdef Mapper of(int mapper_no):
        """Return the registered class, rejecting unsupported mapper numbers."""
        mapper_name = "{:03d}".format(mapper_no)
        if mapper_name not in mappers:
            raise ValueError("unsupported iNES mapper {:d}".format(mapper_no))
        return <Mapper> mappers[mapper_name]