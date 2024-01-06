from libc.stdint cimport uint8_t, uint16_t, uint32_t

from mirror cimport *


cdef class Mapper:
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

cdef class Mapper000(Mapper):
    pass

cdef class Mapper001(Mapper):
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

cdef class Mapper002(Mapper):
    cdef uint8_t PRGBankSelectLo
    cdef uint8_t PRGBankSelectHi

cdef class Mapper003(Mapper):
    cdef uint8_t CHRBankSelect

cdef class Mapper004(Mapper):
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
      
cdef class Mapper066(Mapper):
    cdef uint8_t CHRBankSelect
    cdef uint8_t PRGBankSelect
