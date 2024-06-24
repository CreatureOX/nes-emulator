from libc.stdint cimport uint8_t, uint16_t, uint32_t


cdef class Mapper:
    cdef str mapper_no

    cdef uint8_t PRGBanks
    cdef uint8_t CHRBanks

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t)
    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t, uint8_t)
    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t)
    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t)

    cdef void reset(self)

    cdef uint8_t mirror(self)

    cdef bint irqState(self)
    cdef void irqClear(self)
    
    cdef void scanline(self)

cdef class MapperNROM(Mapper):
    pass

cdef class MapperMMC1(Mapper):
    cdef uint8_t CHRBankSelect4Lo
    cdef uint8_t CHRBankSelect4Hi
    cdef uint8_t CHRBankSelect8

    cdef uint8_t PRGBankSelect16Lo
    cdef uint8_t PRGBankSelect16Hi
    cdef uint8_t PRGBankSelect32

    cdef uint8_t loadRegister
    cdef uint8_t loadRegisterCount
    cdef uint8_t controlRegister

    cdef uint8_t mirrormode

    cdef uint8_t[:] RAMStatic

cdef class MapperUxROM(Mapper):
    cdef uint8_t PRGBankSelectLo
    cdef uint8_t PRGBankSelectHi

cdef class MapperINES003(Mapper):
    cdef uint8_t CHRBankSelect

cdef class MapperMMC3(Mapper):
    cdef uint8_t targetRegister
    cdef bint PRGBankMode
    cdef bint CHRInversion
    cdef uint8_t mirrormode

    cdef uint32_t[8] register
    cdef uint32_t[8] CHRBank
    cdef uint32_t[4] PRGBank

    cdef bint IRQActive
    cdef bint IRQEnable
    cdef bint IRQUpdate
    cdef uint16_t IRQCounter
    cdef uint16_t IRQReload

    cdef uint8_t[:] RAMStatic

cdef class MapperGxROM(Mapper):
    cdef uint8_t CHRBankSelect
    cdef uint8_t PRGBankSelect