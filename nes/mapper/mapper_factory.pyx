from nes.mapper.impl.mapper_nrom cimport MapperNROM
from nes.mapper.impl.mapper_mmc1 cimport MapperMMC1
from nes.mapper.impl.mapper_uxrom cimport MapperUxROM
from nes.mapper.impl.mapper_ines003 cimport MapperINES003
from nes.mapper.impl.mapper_mmc3 cimport MapperMMC3
from nes.mapper.impl.mapper_mmc5 cimport MapperMMC5
from nes.mapper.impl.mapper_gxrom cimport MapperGxROM
from nes.mapper.impl.mapper_axrom cimport MapperAxROM
from nes.mapper.impl.mapper_colordreams cimport MapperColorDreams
from nes.mapper.impl.mapper_bnrom cimport MapperBNROM
from nes.mapper.impl.mapper_vrc2a cimport MapperVRC2a
from nes.mapper.impl.mapper_action53 cimport MapperAction53
from nes.mapper.impl.mapper_cprom cimport MapperCPROM
from nes.mapper.impl.mapper_mmc2 cimport MapperMMC2
from nes.mapper.impl.mapper_mmc4 cimport MapperMMC4
from nes.mapper.impl.mapper_rambo1 cimport MapperRambo1
from nes.mapper.impl.mapper_fme7 cimport MapperFME7
from nes.mapper.impl.mapper_078 cimport Mapper078
from nes.mapper.impl.mapper_118 cimport Mapper118
from nes.mapper.impl.mapper_180 cimport Mapper180


mappers = {
    "000": MapperNROM,
    "001": MapperMMC1,
    "002": MapperUxROM,
    "003": MapperINES003,
    "004": MapperMMC3,
    "005": MapperMMC5,
    "007": MapperAxROM,
    "009": MapperMMC2,
    "010": MapperMMC4,
    "011": MapperColorDreams,
    "013": MapperCPROM,
    "022": MapperVRC2a,
    "028": MapperAction53,
    "034": MapperBNROM,
    "064": MapperRambo1,
    "066": MapperGxROM,
    "069": MapperFME7,
    "078": Mapper078,
    "118": Mapper118,
    "180": Mapper180,
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