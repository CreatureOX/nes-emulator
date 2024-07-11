from nes.cart.cart cimport Cartridge


cdef class CartridgeDebugger:
    cdef Cartridge cartridge

    cpdef dict view(self)
