from nes.apu.apu import APU2A03

cdef class CPUBus:
    """
    Main system bus connecting CPU, PPU, APU, and cartridge components.
    
    Handles memory-mapped I/O, DMA transfers, and clock synchronization
    between the various NES components.
    """
    def __init__(self, Cartridge cartridge) -> None:
        self.ram = [0x00] * 2 * 1024
        self.controller = [0x00,0x00]
        self.controller_state = [0x00,0x00]
        self.nSystemClockCounter = 0

        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00

        self.dma_dummy = True
        self.dma_transfer = False

        self.cpu = CPU6502(self)
        self.ppu = PPU2C02(self)
        self.apu = APU2A03()
        # Let the DMC channel DMA-fetch samples from CPU memory.
        self.apu.bus_ref = self
        self.cartridge = cartridge
        self.cartridge.connect_bus(self)
        self.ppu.connectCartridge(self.cartridge)

    cpdef uint8_t read(self, uint16_t addr, bint readOnly):
        """
        Read a byte from the system bus.
        
        Memory map:
        - $0000-$1FFF: 2KB RAM with mirroring (repeated every 8KB)
        - $2000-$3FFF: PPU registers with mirroring (repeated every 8 bytes)
        - $4015: APU status register
        - $4016-$4017: Controller I/O registers
        - $4020-$FFFF: Cartridge space (PRG ROM/RAM)
        """
        # Try cartridge space first
        success, data = self.cartridge.readByCPU(addr)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            # 2KB RAM at $0000-$07FF, mirrored every 8KB
            data = self.cpu.ram[addr & 0x07FF]
        elif 0x2000 <= addr <= 0x3FFF:
            # PPU registers at $2000-$2007, mirrored every 8 bytes
            data = self.ppu.readByCPU(addr & 0x0007, readOnly)
        elif addr == 0x4015:
            # APU status register
            data = self.apu.readByCPU(addr)
        elif 0x4016 <= addr <= 0x4017:
            # Controller registers - shift data out serially
            data = 1 if (self.controller_state[addr & 0x0001] & 0x80) > 0 else 0
            self.controller_state[addr & 0x0001] <<= 1
        return data

    cpdef void write(self, uint16_t addr, uint8_t data):
        """
        Write a byte to the system bus.
        
        Memory map:
        - $0000-$1FFF: 2KB RAM with mirroring
        - $2000-$3FFF: PPU registers with mirroring
        - $4000-$4013: APU registers
        - $4014: Sprite DMA register
        - $4015-$4017: APU and controller registers
        - $4020-$FFFF: Cartridge space
        """
        # Try cartridge space first
        success = self.cartridge.writeByCPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            # RAM area
            self.cpu.ram[addr & 0x07FF] = data
        elif 0x2000 <= addr <= 0x3FFF:
            # PPU registers
            self.ppu.writeByCPU(addr & 0x0007, data)
        elif 0x4000 <= addr <= 0x4013 or addr == 0x4015 or addr == 0x4017:
            # APU registers
            self.apu.writeByCPU(addr, data)
        elif addr == 0x4014:
            # Sprite DMA - copy 256 bytes from page to PPU OAM
            self.dma_page = data
            self.dma_addr = 0x00
            self.dma_transfer = True
        elif 0x4016 <= addr <= 0x4017:
            # Controller strobe - reset shift counters
            self.controller_state[addr & 0x0001] = self.controller[addr & 0x0001]

    cpdef void reset(self):
        """Reset all components and DMA state."""
        self.cartridge.reset()
        self.cpu.reset()
        self.ppu.reset()
        self.apu.reset()
        self.nSystemClockCounter = 0
        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00
        self.dma_dummy = True
        self.dma_transfer = False

    cpdef void power_up(self):
        """Initialize all components as if power was just applied."""
        self.cartridge.reset()
        self.cpu.power_up()
        self.ppu.reset()
        self.apu.power_up()
        self.nSystemClockCounter = 0
        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00
        self.dma_dummy = True
        self.dma_transfer = False

    cpdef void clock(self):
        """
        Clock the system - advances one CPU cycle.
        
        The PPU runs 3x faster than the CPU (3 PPU cycles per CPU cycle).
        DMA transfers take 512 cycles (256 bytes read + 256 bytes write).
        NMI is generated at start of VBLANK when enabled.
        """
        cdef uint8_t cycles = 0
        cdef unsigned long long cpu_cycle = 0

        # Always clock the PPU (runs at 3x CPU speed)
        self.ppu.clock()
        # A1: propagate the /NMI and /IRQ line levels from the devices to the
        # CPU every tick. The CPU edge-detects NMI and level-samples IRQ; both
        # are serviced only at instruction boundaries, never injected
        # mid-instruction. The mapper holds its /IRQ line asserted until the
        # game acknowledges it (MMC3 $E000) -- the bus no longer force-clears
        # it on service, matching real hardware level-triggered behaviour.
        # (When APU frame/DMC IRQ lands, OR its level in here.)
        self.cpu.set_nmi_line(self.ppu.nmi_line)
        self.cpu.set_irq_line(self.cartridge.mapper.IRQ_state())
        # S3 (phase calibration): a CPU cycle spans three PPU dots. The 6502
        # samples its interrupt inputs at phi2, i.e. the MIDDLE dot of the
        # three (dots 1,4,7,...), not the first. Clocking the CPU on
        # `counter % 3 == 0` observed the bus one dot too early, which pushed
        # NMI recognition a full CPU cycle off for 7.nmi_timing's align1
        # subtests. Sampling on `% 3 == 1` puts the observation point at the
        # middle dot, matching hardware.
        if self.nSystemClockCounter % 3 == 1:
            # This is a CPU cycle
            cpu_cycle = <unsigned long long>(self.nSystemClockCounter // 3)
            if self.dma_transfer:
                # OAM DMA transfer: takes 512 cycles (2 per byte transferred)
                if self.dma_dummy:
                    # Odd cycle of dummy read - wait
                    if cpu_cycle % 2 == 1:
                        self.dma_dummy = False
                else:
                    # Even cycle: read byte from PRG ROM
                    if cpu_cycle % 2 == 0:
                        self.dma_data = self.read((self.dma_page << 8) | self.dma_addr, False)
                    else:
                        # Odd cycle: write byte to PPU OAM ($2004)
                        self.write(0x2004, self.dma_data)
                        self.dma_addr += 1
                        if self.dma_addr == 0x00:
                            # DMA complete, reset transfer state
                            self.dma_transfer = False
                            self.dma_dummy = True
            else:
                # Normal CPU instruction execution
                self.cpu.clock()
            # Clock APU (1 CPU cycle)
            self.apu.clock(1)

        self.nSystemClockCounter += 1

    cpdef void run_frame(self):
        """Execute a complete video frame.

        The PPU fully owns its cycle/scanline bookkeeping (including the
        odd-frame idle-dot skip). The bus merely clocks the system until the
        PPU reports the frame is complete — it must never write ppu.cycle.
        """
        self.ppu.frame_complete = False
        while not self.ppu.frame_complete:
            self.clock()