from libc.stdint cimport uint8_t, uint16_t, UINT32_MAX

import numpy as np

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class Header:
    """Base class for cartridge ROM header."""
    def __init__(self, bytes header_bytes) -> None:
        pass

cdef class CartridgeCPUPort:
    '''
    The cartridge's CPU address-space port ($4020-$FFFF and WRAM).

    Address translation lives in the mapper; this port owns the
    success/data contract the system bus uses to route a read.
    '''
    def __init__(self, Cartridge cart):
        '''Bind the port to the cartridge whose memory it maps.'''
        self.cart = cart

    cdef (bint, uint8_t) read(self, uint16_t addr):
        '''
        Read a byte from CPU address space via mapper translation.

        Args:
            addr: 16-bit CPU address

        Returns:
            Tuple of (success, data)
        '''
        cdef CPUReadMapping mapping = self.cart.mapper.map_cpu_read(addr)

        if mapping.success:
            if mapping.addr == UINT32_MAX:
                return (True, mapping.data)
            else:
                return (True, self.cart.PRG_ROM_data[mapping.addr])
        elif 0x6000 <= addr <= 0x7FFF:
            # WRAM window ($6000-$7FFF) when the mapper doesn't claim it.
            return (True, self.cart.wram[addr - 0x6000])
        else:
            return (False, mapping.data)

    cdef bint write(self, uint16_t addr, uint8_t data):
        '''
        Write a byte to CPU address space via mapper translation.

        Args:
            addr: 16-bit CPU address
            data: 8-bit data to write

        Returns:
            True if write was handled by mapper, False otherwise
        '''
        cdef CPUWriteMapping mapping = self.cart.mapper.map_cpu_write(addr, data)

        if mapping.success:
            if mapping.addr == UINT32_MAX:
                return True
            else:
               self.cart.PRG_ROM_data[mapping.addr] = data
               return True
        elif 0x6000 <= addr <= 0x7FFF:
            # WRAM window ($6000-$7FFF) when the mapper doesn't claim it.
            self.cart.wram[addr - 0x6000] = data
            return True
        else:
            return False

cdef class CartridgePPUPort:
    '''
    The cartridge's PPU address-space port (CHR ROM/RAM).

    Mirroring and bank selection stay in the mapper; this port only
    decodes the 14-bit PPU address into a CHR storage offset.
    '''
    def __init__(self, Cartridge cart):
        '''Bind the port to the cartridge whose memory it maps.'''
        self.cart = cart

    cdef (bint, uint8_t) read(self, uint16_t addr):
        '''
        Read a byte from PPU address space via mapper translation.

        Args:
            addr: 14-bit PPU address

        Returns:
            Tuple of (success, data)
        '''
        cdef PPUReadMapping mapping = self.cart.mapper.map_ppu_read(addr)
        cdef uint8_t data = 0x00

        if mapping.success:
            if self.cart.CHR_RAM_bytes > 0:
                data = self.cart.CHR_RAM_data[mapping.addr]
            else:
                data = self.cart.CHR_ROM_data[mapping.addr]
        return (mapping.success, data)

    cdef bint write(self, uint16_t addr, uint8_t data):
        '''
        Write a byte to PPU address space via mapper translation.

        Args:
            addr: 14-bit PPU address
            data: 8-bit data to write

        Returns:
            True if write was handled by mapper, False otherwise
        '''
        cdef PPUWriteMapping mapping = self.cart.mapper.map_ppu_write(addr)

        if mapping.success:
            if self.cart.CHR_RAM_bytes > 0:
                self.cart.CHR_RAM_data[mapping.addr] = data
            else:
                self.cart.CHR_ROM_data[mapping.addr] = data
        return mapping.success

cdef class Cartridge:
    """
    Base cartridge class handling PRG/CHR ROM and mapper functionality.

    Acts as the bridge between the system bus and the mapper, which handles
    address translation for bankswitching and mirroring.
    """
    def __cinit__(self, filename):
        '''Create both address-space ports before any __init__ runs.

        INesCart and Nes2Cart override __init__ without calling the
        base implementation, so __cinit__ is the only hook that runs
        for every cartridge subclass.
        '''
        self.cpu = CartridgeCPUPort(self)
        self.ppu = CartridgePPUPort(self)

    def __init__(self, filename) -> None:
        # WRAM window at $6000-$7FFF. NES carts rarely wire this range to
        # anything, but blargg's test framework (and many dev/homebrew ROMs)
        # report their result to the emulator by writing $6000 (status byte)
        # and a validity signature to $6001-$6003; the iNES header's PRG-RAM
        # flag is frequently absent even when the ROM relies on this RAM. Always
        # back the range so those writes are observable. Ref: blargg test
        # readme "Output at $6000".
        self.wram = np.zeros(8192, dtype=np.uint8)

    cdef void reset(self):
        """Reset the mapper state."""
        if self.mapper is None:
            return
        self.mapper.reset()

    cdef uint8_t mapper_no(self):
        """Return the mapper number."""
        pass

    @staticmethod
    def nes_version(header_bytes: bytes) -> int:
        """
        Detect NES ROM format version from header.

        Args:
            header_bytes: First 16 bytes of the ROM file

        Returns:
            2 for NES2.0 format, 1 for iNES format, 0 if not recognized
        """
        word = header_bytes[0:3].decode("UTF-8")
        is_ines_format = word == 'NES' and header_bytes[3] == 0x1A
        is_nes2_format = is_ines_format and header_bytes[7] & 0x0C == 0x08
        if is_nes2_format:
            return 2
        if is_ines_format:
            return 1
        return 0
