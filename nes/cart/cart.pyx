from libc.stdint cimport uint8_t, uint16_t, UINT32_MAX

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class Header:
    """Base class for cartridge ROM header."""
    def __init__(self, bytes header_bytes) -> None:
        pass

cdef class Cartridge:
    """
    Base cartridge class handling PRG/CHR ROM and mapper functionality.
    
    Acts as the bridge between the system bus and the mapper, which handles
    address translation for bankswitching and mirroring.
    """
    def __init__(self, filename) -> None:
        pass

    cdef void connect_bus(self, CPUBus bus):
        """Connect the cartridge to the system bus."""
        self.bus = bus 

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

    cdef (bint, uint8_t) readByCPU(self, uint16_t addr):
        """
        Read a byte from CPU address space via mapper translation.
        
        Args:
            addr: 16-bit CPU address
            
        Returns:
            Tuple of (success, data)
        """
        cdef CPUReadMapping mapping = self.mapper.mapReadByCPU(addr)

        if mapping.success:
            if mapping.addr == UINT32_MAX:
                return (True, mapping.data)
            else:
                return (True, self.PRG_ROM_data[mapping.addr])
        else:
            return (False, mapping.data)   

    cdef bint writeByCPU(self, uint16_t addr, uint8_t data):
        """
        Write a byte to CPU address space via mapper translation.
        
        Args:
            addr: 16-bit CPU address
            data: 8-bit data to write
            
        Returns:
            True if write was handled by mapper, False otherwise
        """
        cdef CPUWriteMapping mapping = self.mapper.mapWriteByCPU(addr, data)

        if mapping.success:
            if mapping.addr == UINT32_MAX:
                return True
            else:
               self.PRG_ROM_data[mapping.addr] = data
               return True
        else:
            return False 

    cdef (bint, uint8_t) readByPPU(self, uint16_t addr):
        """
        Read a byte from PPU address space via mapper translation.
        
        Args:
            addr: 14-bit PPU address
            
        Returns:
            Tuple of (success, data)
        """
        cdef PPUReadMapping mapping = self.mapper.mapReadByPPU(addr)
        cdef uint8_t data = 0x00

        if mapping.success:
            if self.CHR_RAM_bytes > 0:
                data = self.CHR_RAM_data[mapping.addr]
            else:
                data = self.CHR_ROM_data[mapping.addr]
        return (mapping.success, data)

    cdef bint writeByPPU(self, uint16_t addr, uint8_t data):
        """
        Write a byte to PPU address space via mapper translation.
        
        Args:
            addr: 14-bit PPU address
            data: 8-bit data to write
            
        Returns:
            True if write was handled by mapper, False otherwise
        """
        cdef PPUWriteMapping mapping = self.mapper.mapWriteByPPU(addr)

        if mapping.success:
            if self.CHR_RAM_bytes > 0:
                self.CHR_RAM_data[mapping.addr] = data
            else:
                self.CHR_ROM_data[mapping.addr] = data
        return mapping.success