'''
CPU bus: address decoding, signal routing and clock-edge dispatch.

The bus owns no chip phase. ClockDivider publishes the PPU-dot / CPU-cycle /
phi2 edges, DmaController owns the DMA stall cadence, and the CPU, PPU and
APU keep their own state. Only the APU's DMC request line and the CPU
data-bus open-bus latch are held here as routed signals.

Ref: NESdev wiki "CPU memory map".
'''

from nes.apu.apu import APU2A03


cdef class CPUBus:
    '''
    Signal router connecting the CPU, PPU, APU, cartridge and DMA unit.

    State owned: the 2 KiB CPU RAM mirror, the APU-driven DMC request line,
    the CPU data-bus open-bus latch and the master clock divider. The two
    Joypad devices own their own button latches and shift registers. Timing
    model: clock() advances one PPU dot; the divider decides which chips see
    an edge. Interfaces: read()/write() decode the CPU address space,
    propagate_lines() drives the /NMI and /IRQ signal lines, and
    DmaController is clocked on CPU-cycle edges.
    '''
    def __init__(self, Cartridge cartridge) -> None:
        '''Bind the devices and start with a clean signal state.'''
        self.ram = [0x00] * 2 * 1024
        self.joy1 = Joypad()
        self.joy2 = Joypad()
        self.divider = ClockDivider()
        self.dmc_dma_request = False

        self.cpu = CPU6502(self)
        self.ppu = PPU2C02(self)
        self.apu = APU2A03()
        # Let the DMC channel DMA-fetch samples from CPU memory.
        self.apu.bus_ref = self
        self.cartridge = cartridge
        self.cartridge.connect_bus(self)
        self.ppu.connectCartridge(self.cartridge)
        self.dma = DmaController(self)
        # CPU data-bus open bus: the last value driven onto the bus.
        self.open_bus = 0x00

    cdef void propagate_lines(self, long long dot):
        '''Drive the /NMI and /IRQ levels into the CPU on every PPU dot.

        The PPU drives /NMI as a pure level and never reaches into the CPU;
        the CPU edge-detects it only on phi2. The mapper holds /IRQ asserted
        until the game acknowledges it (MMC3 $E000), and APU frame/DMC IRQs
        are level sources too, so both are OR-ed in here rather than cleared
        on service. dot timestamps the signal for the CPU's poll margins.

        Ref: NESdev wiki "CPU interrupts".
        '''
        self.cpu.set_nmi_line(self.ppu.nmi_line)
        self.cpu.set_irq_line(
            (self.cartridge.mapper.IRQ_state() != 0)
            or self.apu.irq_level(),
            dot
        )
        if self.divider.phi2_edge:
            self.cpu.on_phi2(dot)

    cpdef uint8_t read(self, uint16_t addr, bint readOnly):
        '''
        Read a byte from the system bus.

        Memory map:
        - $0000-$1FFF: 2KB RAM with mirroring (repeated every 8KB)
        - $2000-$3FFF: PPU registers with mirroring (repeated every 8 bytes)
        - $4015: APU status register
        - $4016-$4017: Controller I/O registers
        - $4020-$FFFF: Cartridge space (PRG ROM/RAM)
        '''
        cdef Joypad pad
        # A pending DMC sample fetch stalls this read before the address is
        # decoded. The DMA unit owns the age test and the stall cadence; see
        # DmaController.may_halt_on_read.
        if not readOnly and self.dma.may_halt_on_read(self.cpu.operand_fetch):
            self.dma.run_dmc_dma(addr)
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
            # Controller registers - shift data out serially.
            #
            # Only D0 is driven by the standard NES controller; the upper bits
            # (5-7) are undriven and float to the OPEN BUS, which on a read of
            # $4016/$4017 is the address's most-significant byte (0x40) left on
            # the data lines. blargg's cpu_exec_space test executes code
            # straight out of I/O space, so a read of $4016 must return 0x40
            # (RTI) when no button is pressed -- bits 5-7 must be 0x40, not 0.
            # Ref: NESdev wiki "Standard controller" (the top bits retain the
            # address MSB; Paperboy relies on reads returning exactly $40/$41).
            if (addr & 0x0001) == 0:
                pad = self.joy1
            else:
                pad = self.joy2
            data = ((addr >> 8) & 0xE0) | pad.read()
        else:
            # Undriven CPU reads: write-only APU registers ($4000-$4014) and the
            # unmapped APU range ($4018-$40FF) -- and any other unmapped space --
            # leave the data bus floating, so the CPU samples the OPEN BUS, the
            # last value driven onto it. This is what lets code executed from I/O
            # space (blargg cpu_exec_space_apu / _ppuio) see the opcode/operand
            # a previous read left behind (e.g. the JMP operand byte that becomes
            # the RTI opcode at $40XX). Ref: NESdev wiki "CPU memory map" (open
            # bus); Mesen2 Core/NES/CpuMemoryManager.cpp (ReadOnly).
            data = self.open_bus
        # Track the CPU data-bus open bus on every real (non-debugger) read;
        # passive debugger disassembly reads (readOnly=True) must not perturb it.
        if not readOnly:
            self.open_bus = data
        return data

    cpdef void write(self, uint16_t addr, uint8_t data):
        '''
        Write a byte to the system bus.

        Memory map:
        - $0000-$1FFF: 2KB RAM with mirroring
        - $2000-$3FFF: PPU registers with mirroring
        - $4000-$4013: APU registers
        - $4014: Sprite DMA register
        - $4015-$4017: APU and controller registers
        - $4020-$FFFF: Cartridge space
        '''
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
            # Sprite DMA - the DMA unit owns the 256-byte copy and its halt
            # cadence; the bus only routes the register write.
            self.dma.start_oam(data)
        elif addr == 0x4016:
            # Controller strobe - latch port 1's button byte. $4017 is the
            # APU frame-counter write, decoded by the APU branch above.
            self.joy1.strobe()
        # A write drives the data bus with `data`, so the open bus takes that
        # value -- the next undriven read will see it. Ref: NESdev wiki
        # "CPU memory map" (open bus).
        self.open_bus = data

    cpdef void reset(self):
        '''Reset all components, the clock divider and the DMA unit.'''
        self.cartridge.reset()
        self.cpu.reset()
        self.ppu.reset()
        self.apu.reset()
        self.divider.reset()
        self.dmc_dma_request = False
        self.dma.reset()
        self.open_bus = 0x00

    cpdef void power_up(self):
        '''Initialize all components as if power was just applied.'''
        self.cartridge.reset()
        self.cpu.power_up()
        self.ppu.reset()
        self.apu.power_up()
        self.divider.reset()
        self.dmc_dma_request = False
        self.dma.reset()
        self.open_bus = 0x00

    cpdef void clock(self):
        '''
        Advance one PPU dot and dispatch the edges published by ClockDivider.

        The PPU runs 3x faster than the CPU (3 PPU dots per CPU cycle).
        OAM DMA (sprite DMA) transfers take 512 CPU cycles (256 bytes read +
        256 bytes written) plus a 1-2 CPU-cycle alignment prefix, during which
        the CPU is halted but the PPU/APU and interrupt lines keep running. The
        APU is clocked on the same CPU cycle the CPU samples its interrupt
        lines, so an APU frame/DMC IRQ is recognized without a one-CPU-cycle
        lag.
        '''
        cdef unsigned long long cpu_cycle = 0
        cdef long long dot = <long long>self.divider.dot

        # Always clock the PPU (runs at 3x CPU speed)
        self.ppu.clock()
        cdef bint is_cpu_cycle = self.divider.cpu_tick_edge
        # The DMA unit latches the APU request BEFORE the APU is clocked, so a
        # fetch asked for during this cycle does not halt this cycle's own read.
        if is_cpu_cycle:
            self.dma.on_cpu_cycle()
            self.apu.clock(1)
        self.propagate_lines(dot)
        # S3 (phase calibration): a CPU cycle spans three PPU dots. The 6502
        # samples its interrupt inputs at phi2, i.e. the MIDDLE dot of the
        # three (dots 1,4,7,...), not the first. ClockDivider's cpu_tick_edge
        # flag (phase == 1) puts the observation point at the middle dot,
        # matching hardware; sampling on phase == 0 pushed NMI recognition a
        # full CPU cycle off for 7.nmi_timing's align1 subtests.
        if is_cpu_cycle:
            cpu_cycle = <unsigned long long>self.divider.cpu_cycle
            if self.dma.active():
                # Either DMA unit owns the bus this cycle; the CPU stays halted.
                self.dma.tick(cpu_cycle)
            else:
                # Normal CPU instruction execution
                self.cpu.clock(dot)

        self.divider.advance()

    cpdef void run_frame(self):
        '''Execute a complete video frame.

        The PPU fully owns its cycle/scanline bookkeeping (including the
        odd-frame idle-dot skip). The bus merely clocks the system until the
        PPU reports the frame is complete — it must never write ppu.cycle.
        '''
        self.ppu.frame_complete = False
        while not self.ppu.frame_complete:
            self.clock()
