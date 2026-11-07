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
        self.dma_write_pending = False
        self.oam_dmc_running = False
        self.oam_dmc_need_halt = False
        self.oam_dmc_need_dummy = False

        self.dmc_dma_request = False
        self.dmc_dma_armed = False
        self.dmc_dma_armed_prev = False
        self.dmc_oam_tail_pending = False

        self.cpu = CPU6502(self)
        self.ppu = PPU2C02(self)
        self.apu = APU2A03()
        # Let the DMC channel DMA-fetch samples from CPU memory.
        self.apu.bus_ref = self
        self.cartridge = cartridge
        self.cartridge.connect_bus(self)
        self.ppu.connectCartridge(self.cartridge)
        # CPU data-bus open bus: the last value driven onto the bus. Reads of
        # undriven space ($4000-$4014 write-only APU, $4018-$40FF unmapped,
        # unmapped PRG) return it; every real read/write refreshes it. See read().
        self.open_bus = 0x00

    cdef void _dma_halt_cycle(self, uint16_t dummy_addr, bint do_dummy_read):
        """Burn one CPU cycle with the CPU halted (a DMA stall cycle).

        Mirrors the non-CPU half of clock(): three PPU dots, then the APU and
        the interrupt lines on the CPU-cycle dot. The APU keeps running
        through any DMA halt, which is what keeps the DMC rate timer -- and
        therefore the sample's byte-to-byte period -- continuous. The CPU
        itself is not clocked, so the instruction that triggered the stall
        simply takes that many extra cycles.

        When do_dummy_read is set the cycle ends with a read of dummy_addr
        whose result is discarded: on hardware the halted CPU's address is what
        sits on the bus, so the side effects of that address fire an extra
        time (Mesen2 ProcessPendingDma).
        """
        self.nSystemClockCounter += 1
        self.ppu.clock()
        self.nSystemClockCounter += 1
        self.ppu.clock()
        self.nSystemClockCounter += 1
        self.ppu.clock()
        self.apu.clock(1)
        self.cpu.set_nmi_line(self.ppu.nmi_line)
        self.cpu.set_irq_line(
            (self.cartridge.mapper.IRQ_state() != 0)
            or self.apu.irq_level()
        )
        if do_dummy_read:
            self.read(dummy_addr, False)

    cdef void _run_dmc_dma(self, uint16_t cpu_read_addr):
        """Halt the CPU and run a DMC sample-byte DMA.

        Port of Mesen2 NesCpu::ProcessPendingDma for the DMC-only case (no
        OAM DMA in flight, no abort). The transfer is

          * one halt cycle, whose dummy read targets the address the CPU was
            about to read;
          * alignment dummy cycles -- also reading the CPU's address -- until
            the cycle parity allows the fetch;
          * the fetch cycle, which reads the DMC's sample address and hands
            the byte to the APU.

        The request is consumed here, so the dummy/fetch reads below cannot
        re-enter this function.

        Dummy-read count. The halt cycle plus the alignment cycles give 2 or
        3 extra reads of the CPU's address, and the CPU is stalled for 3 or 4
        cycles -- exactly the "2-3 extra $2007 reads" that blargg's
        dmc_dma_during_read4 measures. Mesen2 consumes its pending
        _needDummyRead on the FIRST cycle of the alignment loop, whatever that
        cycle's parity is, and only then may the fetch run; the fetch itself
        is the first EVEN CycleCount after that. Doing it any other way costs
        one dummy read too many, which shifts the VRAM pointer one byte too
        far and lands blargg's corruption on the wrong iteration.

        Parity. Mesen2 fetches on an EVEN CycleCount (`getCycle =
        (CycleCount & 1) == 0`), tested before the next cycle is started --
        i.e. against the cycle that just ran. This bus counts differently: at
        the loop head `nSystemClockCounter // 3` is the cycle that is ABOUT
        to run, one past the halt cycle Mesen2's CycleCount names. The two
        parities are therefore opposite, and the fetch waits for an ODD
        value of `nSystemClockCounter // 3` -- the same cycle Mesen2's even
        CycleCount selects.

        Stolen-cycle count. A reload of the 1-byte sample buffer is asked for
        on a put cycle: dbhq-uk/6502's DmcChannel sets `_fetchFrom = cycle +
        2` when the output unit empties the buffer, so halt, dummy, alignment
        and fetch take four cycles. A load is asked for on a get (`_fetchFrom
        = writeCycle + 3/4` always picks an even cycle), so its fetch lands
        on the next get and the CPU read's parity decides between three and
        four cycles. The exception is the first standalone fetch after an OAM
        DMA ends: the DMC sequence at the tail of the copy is still sharing
        OAM's cadence, so the next get -- not a fixed count -- ends it.
        Ref: dbhq-uk/6502 NesBus.RunDma / ApuChannels.DmcChannel;
        NESdev wiki "DMA" (DMC DMA during OAM DMA).

        Dummy reads at $4016/$4017. Mesen2 skips the alignment dummy reads
        when the CPU was reading a controller register: on an NES only the
        FIRST dummy read has side effects, so a controller loses exactly ONE
        bit per DMA instead of one per dummy cycle. The halt cycle's read
        still happens -- that is what makes blargg's dma_4016_read count 07
        instead of 08 on the iteration where the DMA lands on the $4016 read.
        """
        cdef bint internal_reg_read = (cpu_read_addr & 0xFFE0) == 0x4000
        cdef bint skip_first_input_clock = False
        cdef bint skip_dummy_reads = (cpu_read_addr == 0x4016
                                      or cpu_read_addr == 0x4017)
        if internal_reg_read:
            # Mesen2's skipFirstInputClock: with /OE asserted for the whole
            # DMA, a DMC sample address that shares the CPU's register number
            # hides the halt cycle's dummy read, so the controller never sees
            # it and loses no bit.
            skip_first_input_clock = ((self.apu.dmc_read_addr() & 0x1F)
                                       == (cpu_read_addr & 0x1F))
        self.dmc_dma_request = False
        self.dmc_dma_armed = False
        cdef int dmc_len = 1
        cdef bint fixed_length = (self.apu.dmc_dma_request_kind() == 2
                                  and not self.dmc_oam_tail_pending)
        # Initial halt cycle (dummy read of the CPU's address).
        self._dma_halt_cycle(cpu_read_addr, not skip_first_input_clock)
        cdef bint need_dummy = True
        while True:
            # The fetch runs on the first parity-allowed cycle after the
            # pending dummy read has been consumed; every other cycle is an
            # alignment dummy that reads the CPU's address again.
            if (not need_dummy
                    and ((fixed_length and dmc_len >= 3)
                         or (not fixed_length
                             and (self.nSystemClockCounter // 3) % 2 == 1))):
                # Fetch cycle: read the sample byte and deliver it.
                self._dma_halt_cycle(0, False)
                self.apu.dmc_deliver(
                    self.read(self.apu.dmc_read_addr(), False))
                self.dmc_oam_tail_pending = False
                return
            # Alignment cycle: another dummy read of the CPU's address.
            self._dma_halt_cycle(cpu_read_addr, not skip_dummy_reads)
            dmc_len += 1
            need_dummy = False

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
        # DMC sample-byte DMA (Mesen2 NesCpu::ProcessPendingDma): when the APU
        # has requested a sample fetch, the CPU is halted at its next read
        # cycle and the transfer runs first, so the read the CPU attempted is
        # delayed by the stall (3 cycles, or 4 -- see _run_dmc_dma). Only CPU
        # reads trigger it: readOnly reads are the debugger's passive
        # disassembly, an in-flight OAM DMA services its own reads here, and
        # Mesen2's MemoryWrite likewise never calls ProcessPendingDma -- a
        # store's final cycle is a write, so a request armed there waits for
        # the next read. The armed flag is this cycle's sample of the request
        # (taken in clock() before the APU ran, so a request raised now halts
        # the NEXT read cycle); the live request is re-checked so a $4015
        # write that stops the channel in the meantime cancels the stall.
        #
        # Deferred operand reads and the age test. This CPU runs an
        # instruction's addressing mode on its FINAL cycle, so operand bytes
        # that a real 6502 reads on cycles 2..N-1 all arrive here, on the same
        # cycle as the data access. Mesen2 has no such compression (each
        # operand fetch is its own MemoryRead, and any of them may halt), so
        # the placement is reproduced by an age test on the request: a
        # deferred operand read suppresses the transfer ONLY when the request
        # was armed during THIS very cycle. Such a request belongs to the
        # instruction's own data access -- the one bus cycle that exists at
        # the same dot on silicon (the data read of an LDA/LDX/..., or, for a
        # store, the following opcode fetch, since a store never halts on its
        # write) -- and halting on the operand read instead would fire the
        # transfer a cycle early and put its dummy reads on the instruction
        # stream, stripping dma_2007_read's extra $2007 reads. An OLDER request
        # belongs to one of the deferred operand fetches themselves: on
        # silicon those cycles really do read the bus, so halting there is
        # correct -- the dummy reads hit the instruction stream exactly as
        # they do on hardware, and a store's write is still delayed by the
        # full stall (Mesen2 adds the whole transfer before the CPU's own
        # cycle; the instruction grows by 3-4 cycles either way).
        # Ref: NESdev wiki "CPU memory access" (per-cycle bus activity);
        # Mesen2 Core/NES/NesCpu.cpp (MemoryRead -> ProcessPendingDma).
        if (not readOnly and not self.dma_transfer
                and self.dmc_dma_armed and self.dmc_dma_request
                and not (self.cpu.operand_fetch and not self.dmc_dma_armed_prev)):
            self._run_dmc_dma(addr)
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
            port = addr & 0x0001
            d0 = 1 if (self.controller_state[port] & 0x80) > 0 else 0
            data = ((addr >> 8) & 0xE0) | d0
            self.controller_state[port] = (
                (self.controller_state[port] << 1) | 1) & 0xFF
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
            # Sprite DMA - copy 256 bytes from page to PPU OAM. The halt cycle
            # is the first CPU cycle after this write; dma_dummy starts the
            # alignment prefix and dma_write_pending tracks whether a $2004
            # put is owed (see clock()).
            self.dma_page = data
            self.dma_addr = 0x00
            self.dma_transfer = True
            self.dma_dummy = True
            self.dma_write_pending = False
        elif 0x4016 <= addr <= 0x4017:
            # Controller strobe - reset shift counters
            self.controller_state[addr & 0x0001] = self.controller[addr & 0x0001]
        # A write drives the data bus with `data`, so the open bus takes that
        # value -- the next undriven read will see it. Ref: NESdev wiki
        # "CPU memory map" (open bus).
        self.open_bus = data

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
        self.dma_write_pending = False
        self.oam_dmc_running = False
        self.oam_dmc_need_halt = False
        self.oam_dmc_need_dummy = False
        self.dmc_dma_request = False
        self.dmc_dma_armed = False
        self.dmc_dma_armed_prev = False
        self.dmc_oam_tail_pending = False
        self.open_bus = 0x00

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
        self.dma_write_pending = False
        self.oam_dmc_running = False
        self.oam_dmc_need_halt = False
        self.oam_dmc_need_dummy = False
        self.dmc_dma_request = False
        self.dmc_dma_armed = False
        self.dmc_dma_armed_prev = False
        self.dmc_oam_tail_pending = False
        self.open_bus = 0x00

    cpdef void clock(self):
        """
        Clock the system - advances one CPU cycle.
        
        The PPU runs 3x faster than the CPU (3 PPU cycles per CPU cycle).
        OAM DMA (sprite DMA) transfers take 512 cycles (256 bytes read + 256
        bytes written) plus a 1-2 cycle alignment prefix, during which the CPU
        is halted but the PPU/APU and interrupt lines keep running.
        NMI is generated at start of VBLANK when enabled.
        The APU is clocked on the same cycle the CPU samples its interrupt
        lines, so an APU frame/DMC IRQ is recognized without a one-cycle lag.
        """
        cdef uint8_t cycles = 0
        cdef unsigned long long cpu_cycle = 0
        cdef bint dmc_ready = False

        # Always clock the PPU (runs at 3x CPU speed)
        self.ppu.clock()
        cdef bint is_cpu_cycle = (self.nSystemClockCounter % 3 == 1)
        # Clock the APU on the SAME CPU cycle the CPU samples its interrupt
        # lines, so a frame/DMC IRQ raised by the APU this cycle is recognised
        # at phi2 of that cycle instead of one cycle late. The mapper line
        # already had this property because ppu.clock() runs above; only the
        # APU path was shifted.
        if is_cpu_cycle:
            # Sample the DMC DMA request BEFORE clocking the APU: a fetch the
            # APU asks for during this cycle must not halt this cycle's own
            # read. Mesen2 reaches the same ordering by calling
            # ProcessPendingDma before StartCpuCycle clocks the APU.
            # The previous cycle's sample is kept alongside: read() uses the
            # pair to tell a request armed THIS cycle from an older one.
            self.dmc_dma_armed_prev = self.dmc_dma_armed
            self.dmc_dma_armed = self.dmc_dma_request
            self.apu.clock(1)
        # A1: propagate the /NMI and /IRQ line levels from the devices to the
        # CPU every tick. The CPU edge-detects NMI and level-samples IRQ; both
        # are serviced only at instruction boundaries, never injected
        # mid-instruction. The mapper holds its /IRQ line asserted until the
        # game acknowledges it (MMC3 $E000) -- the bus no longer force-clears
        # it on service, matching real hardware level-triggered behaviour.
        # APU frame/DMC IRQs are level-triggered /IRQ sources too; OR them in
        # with the mapper's line so the CPU actually sees them.
        self.cpu.set_nmi_line(self.ppu.nmi_line)
        self.cpu.set_irq_line(
            (self.cartridge.mapper.IRQ_state() != 0)
            or self.apu.irq_level()
        )
        # S3 (phase calibration): a CPU cycle spans three PPU dots. The 6502
        # samples its interrupt inputs at phi2, i.e. the MIDDLE dot of the
        # three (dots 1,4,7,...), not the first. Clocking the CPU on
        # `counter % 3 == 0` observed the bus one dot too early, which pushed
        # NMI recognition a full CPU cycle off for 7.nmi_timing's align1
        # subtests. Sampling on `% 3 == 1` puts the observation point at the
        # middle dot, matching hardware.
        if is_cpu_cycle:
            # This is a CPU cycle
            cpu_cycle = <unsigned long long>(self.nSystemClockCounter // 3)
            if self.dma_transfer or self.oam_dmc_running:
                # OAM DMA (and any DMC DMA that collided with it) runs here.
                #
                # Both 2A03 DMA units share one get/put cadence: DMA can only
                # read ("get") on one cycle type and write ("put") on the
                # other. Reads land on ODD cpu cycles and $2004 writes on EVEN
                # ones. The CPU is halted for the whole sequence (cpu.clock()
                # is not called), but the PPU and APU keep running and the
                # interrupt lines keep being propagated, so a device IRQ
                # raised mid-transfer is seen the moment the CPU resumes (see
                # CPU6502.clock's stall-aware poll reference).
                #
                # Alignment prefix: 1 halt cycle when the $4014 write fell on
                # an odd cpu cycle (first read at W+2, total 513 cycles) and 2
                # cycles -- halt + one alignment cycle -- when it fell on an
                # even one (first read at W+3, total 514). The prefix waits for
                # an EVEN cycle, and the transfer itself reads on odd / writes
                # on even. Getting this backwards cost a full CPU cycle of halt
                # on one parity and made 4-irq_and_dma's dly=526 row fire an
                # instruction late. Ref: Mesen2 Core/NES/NesCpu.cpp
                # (ProcessPendingDma); NESdev wiki "DMA" (Cadence).
                #
                # DMC DMA interaction (NESdev wiki "DMA", "DMC DMA during OAM
                # DMA"): when both units want the bus on the same cycle the DMC
                # get wins and the OAM DMA is paused. The two units otherwise
                # share cycles, and every no-operation cycle (halt, DMC dummy,
                # alignment) is free -- it overlaps useful work of the other
                # unit:
                #   * a DMC DMA that collides in the middle of the copy costs
                #     2 cycles: 1 for the DMC get, then 1 for OAM to re-align
                #     to a get (its $2004 put slot loses its data);
                #   * one that schedules on the second-to-last put costs 1: its
                #     halt and dummy cycles ride the last read/put pair and the
                #     get lands on the first cycle after the DMA;
                #   * one that schedules on the last put costs 3: after the DMA
                #     its dummy and alignment cycles are still owed, and only
                #     then does the get happen (past the end of the copy).
                # Mesen2 models this by keeping the DMC request inside the OAM
                # loop (`while(_dmcDmaRunning || _spriteDmaTransfer)`); the code
                # below is the same state machine.
                dmc_ready = (self.oam_dmc_running
                             and not self.oam_dmc_need_halt
                             and not self.oam_dmc_need_dummy)
                if (self.dmc_dma_armed and self.dmc_dma_request
                        and not self.oam_dmc_running):
                    # A request armed before this cycle joins the running OAM
                    # DMA instead of stalling the CPU afterwards. It is picked
                    # up here, at the top of its first cycle, so this cycle's
                    # branch above already saw "not ready" -- exactly Mesen2's
                    # ordering (StartDmcTransfer during cycle N, first
                    # needHalt consumed on N+1).
                    self.oam_dmc_running = True
                    self.oam_dmc_need_halt = True
                    self.oam_dmc_need_dummy = True
                    self.dmc_dma_request = False
                    self.dmc_dma_armed = False
                if self.dma_dummy:
                    # Alignment prefix: wait for an even (put) cycle.
                    if cpu_cycle % 2 == 0:
                        self.dma_dummy = False
                elif cpu_cycle % 2 == 1:
                    # Get cycle: the DMC's sample fetch has priority over the
                    # OAM copy's read.
                    if dmc_ready:
                        self.apu.dmc_deliver(
                            self.read(self.apu.dmc_read_addr(), False))
                        self.oam_dmc_running = False
                        # No OAM byte was read this cycle, so no $2004 write
                        # is owed: the next put cycle realigns instead.
                        self.dma_write_pending = False
                    elif self.dma_transfer:
                        self.dma_data = self.read(
                            (self.dma_page << 8) | self.dma_addr, False)
                        self.dma_write_pending = True
                else:
                    # Put cycle: only write if a read is waiting to be put.
                    if self.dma_transfer and self.dma_write_pending:
                        self.write(0x2004, self.dma_data)
                        self.dma_addr += 1
                        self.dma_write_pending = False
                        if self.dma_addr == 0x00:
                            # DMA complete, reset transfer state
                            self.dma_transfer = False
                            self.dmc_oam_tail_pending = True
                            # A DMC DMA already in flight keeps the shared
                            # get/put cadence going: re-arming the OAM
                            # alignment prefix here would insert idle cycles
                            # the reference RunDma loop never has.
                            if not self.oam_dmc_running:
                                self.dma_dummy = True
                # One of the DMC DMA's setup cycles is absorbed by this cycle
                # (halt first, then dummy). OAM DMA's own halt/alignment/
                # read/write cycle above does double duty.
                if self.oam_dmc_need_halt:
                    self.oam_dmc_need_halt = False
                elif self.oam_dmc_need_dummy:
                    self.oam_dmc_need_dummy = False
            else:
                # Normal CPU instruction execution
                self.cpu.clock()

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