from libc.stdint cimport uint8_t, uint16_t

from nes.mapper.mirror cimport *


cdef class Mapper:
    """
    Base class for NES cartridge mappers.
    
    Mappers handle address translation for bankswitching PRG and CHR ROM,
    as well as controlling mirroring modes. Different mapper numbers
    correspond to different bankswitching schemes.
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        self.PRG_banks = PRG_banks
        self.CHR_banks = CHR_banks

        self.reset()

    @staticmethod
    def instance(PRG_banks: uint8_t, CHR_banks: uint8_t):
        """Create a default Mapper instance (no bankswitching)."""
        return Mapper(PRG_banks, CHR_banks)

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        """Map a CPU read address to PRG ROM/RAM."""
        pass

    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        """Map a CPU write address to PRG ROM/RAM (for mappers with RAM)."""
        pass

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        """Map a PPU read address to CHR ROM/RAM."""
        pass

    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
        """Map a PPU write address to CHR RAM (for mappers without CHR ROM)."""
        pass

    cdef void reset(self):
        """Reset mapper state."""
        self.a12_suppress = False

    cdef uint8_t mirror(self):
        """Return the mirroring mode."""
        return HARDWARE

    cdef bint IRQ_state(self):
        """Check if IRQ is pending."""
        return False

    cdef void IRQ_clear(self):
        """Clear pending IRQ."""
        pass

    cdef void scanline(self):
        """Called on each PPU scanline (for scanline-based IRQs)."""
        pass

    cdef void a12_notify(self, uint16_t addr):
        """Notify the mapper of a PPU address-bus A12 transition.

        Base no-op. Mappers that clock an IRQ off PPU A12 (e.g. MMC3) override
        this. It is called from both the PPU CHR/nametable fetch path and the
        $2006 VRAM-address write path.
        """
        pass