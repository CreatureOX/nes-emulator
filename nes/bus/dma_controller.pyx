'''
2A03 DMA unit: OAM sprite DMA and DMC sample-byte DMA.

This device owns the shared get/put cadence, the halt and alignment stall
cycles, and the latched APU request. The CPUBus is only a signal router: it
forwards $4014 writes, APU request levels and CPU reads here, and clocks this
unit on CPU-cycle edges. No chip state is kept on the bus.

Ref: Mesen2 Core/NES/NesCpu.cpp (ProcessPendingDma); NESdev wiki "DMA";
dbhq-uk/6502 NesBus.RunDma / ApuChannels.DmcChannel.
'''

from libc.stdint cimport uint8_t, uint16_t, uint64_t


cdef class DmaController:
    '''
    First-class DMA device with its own stall cadence.

    State owned: the OAM copy page/offset/data, the get/put pairing, the
    latched DMC request and its age in CPU cycles, and the flags that extend
    a DMC sequence past the end of an OAM copy. Timing model: both 2A03 DMA
    units share one get/put cadence; a standalone DMC fetch stalls the CPU for
    3 or 4 CPU cycles by advancing three PPU dots per stall cycle.

    Interfaces: the bus supplies CPU reads/writes and propagates interrupt
    levels, the APU drives the dmc_dma_request signal line on the bus, and
    ClockDivider supplies the CPU-cycle parity. The CPU is never clocked while
    this device owns the bus.

    Ref: Mesen2 Core/NES/NesCpu.cpp (ProcessPendingDma); NESdev wiki "DMA";
    dbhq-uk/6502 NesBus.RunDma / ApuChannels.DmcChannel.
    '''
    def __init__(self, CPUBus bus):
        '''Bind the signal router and start with no transfer in flight.'''
        self.bus = bus
        self.reset()

    cpdef void reset(self):
        '''Return every DMA latch and cadence flag to the power-up state.

        The APU-driven request line itself belongs to the bus and is cleared
        by CPUBus.reset / CPUBus.power_up, not here.
        '''
        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00
        self.dma_dummy = True
        self.dma_transfer = False
        self.dma_write_pending = False
        self.oam_dmc_running = False
        self.oam_dmc_need_halt = False
        self.oam_dmc_need_dummy = False
        self.request_armed = False
        self.armed_cycles = 0
        self.dmc_oam_tail_pending = False

    cdef void on_cpu_cycle(self):
        '''Latch the APU request line at the START of each CPU cycle.

        Sampling happens BEFORE the APU is clocked, so a request raised by
        this cycle's APU tick only becomes visible on the next cycle.
        armed_cycles counts the CPU cycles the latch has been asserted; the
        read path uses it to tell a fresh request from an older one. This is
        the DMA unit's own stall cadence, not a bus-wide age flag.

        Ref: Mesen2 Core/NES/NesCpu.cpp (ProcessPendingDma).
        '''
        self.request_armed = self.bus.dmc_dma_request
        if self.request_armed:
            self.armed_cycles += 1
        else:
            self.armed_cycles = 0

    cdef bint may_halt_on_read(self, bint operand_fetch):
        '''Decide whether a CPU read must be delayed by a DMC sample fetch.

        Only CPU reads trigger it: readOnly reads are the debugger's passive
        disassembly, an in-flight OAM DMA services its own reads, and a store's
        final cycle is a write, so a request armed there waits for the next
        read. The armed latch is this cycle's sample of the request line, and
        the live level is re-checked so a $4015 write that stops the channel
        meanwhile cancels the stall.

        Deferred operand reads. This CPU runs an instruction's addressing mode
        on its FINAL cycle, so operand bytes a real 6502 reads on cycles 2..N-1
        all arrive on the same cycle as the data access. A deferred operand
        read suppresses the transfer ONLY when the request was armed during
        THIS very cycle (armed_cycles == 1): such a request belongs to the
        instruction's own data access. An OLDER request belongs to one of the
        deferred operand fetches themselves, which really do read the bus on
        silicon, so halting there is correct.

        Ref: NESdev wiki "CPU memory access"; Mesen2 Core/NES/NesCpu.cpp
        (MemoryRead -> ProcessPendingDma).
        '''
        return (not self.dma_transfer
                and self.request_armed
                and self.bus.dmc_dma_request
                and not (operand_fetch and self.armed_cycles == 1))

    cdef bint active(self):
        '''True while either DMA unit owns the bus and the CPU stays halted.'''
        return self.dma_transfer or self.oam_dmc_running

    cdef void start_oam(self, uint8_t page):
        '''Latch a $4014 write and begin the 256-byte OAM copy.

        The halt cycle is the first CPU cycle after this write; dma_dummy
        starts the alignment prefix and dma_write_pending tracks whether a
        $2004 put is owed (see tick).
        '''
        self.dma_page = page
        self.dma_addr = 0x00
        self.dma_transfer = True
        self.dma_dummy = True
        self.dma_write_pending = False

    cdef void halt_cycle(self, uint16_t dummy_addr, bint do_dummy_read):
        '''Burn one CPU cycle with the CPU halted (a DMA stall cycle).

        Mirrors the non-CPU half of CPUBus.clock(): three PPU dots, then the
        APU and the interrupt lines on the CPU-cycle dot. The APU keeps
        running through any DMA halt, which is what keeps the DMC rate timer
        and therefore the sample's byte-to-byte period continuous. The CPU
        itself is not clocked, so the instruction that triggered the stall
        simply takes that many extra cycles.

        When do_dummy_read is set the cycle ends with a read of dummy_addr
        whose result is discarded: on hardware the halted CPU's address is
        what sits on the bus, so the side effects of that address fire an
        extra time (Mesen2 ProcessPendingDma).
        '''
        cdef long long dot
        self.bus.divider.advance()
        self.bus.ppu.clock()
        self.bus.divider.advance()
        self.bus.ppu.clock()
        self.bus.divider.advance()
        self.bus.ppu.clock()
        self.bus.apu.clock(1)
        dot = <long long>self.bus.divider.dot
        self.bus.propagate_lines(dot)
        if do_dummy_read:
            self.bus.read(dummy_addr, False)

    cdef void run_dmc_dma(self, uint16_t cpu_read_addr):
        '''Halt the CPU and run a DMC sample-byte DMA.

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
        i.e. against the cycle that just ran. This unit counts differently:
        at the loop head `ClockDivider.cpu_cycle` is the cycle that is ABOUT
        to run, one past the halt cycle Mesen2's CycleCount names. The two
        parities are therefore opposite, and the fetch waits for an ODD
        value of `ClockDivider.cpu_cycle` -- the same cycle Mesen2's even
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
        '''
        cdef bint internal_reg_read = (cpu_read_addr & 0xFFE0) == 0x4000
        cdef bint skip_first_input_clock = False
        cdef bint skip_dummy_reads = (cpu_read_addr == 0x4016
                                      or cpu_read_addr == 0x4017)
        if internal_reg_read:
            # Mesen2's skipFirstInputClock: with /OE asserted for the whole
            # DMA, a DMC sample address that shares the CPU's register number
            # hides the halt cycle's dummy read, so the controller never sees
            # it and loses no bit.
            skip_first_input_clock = ((self.bus.apu.dmc_read_addr() & 0x1F)
                                       == (cpu_read_addr & 0x1F))
        self.bus.dmc_dma_request = False
        self.request_armed = False
        cdef int dmc_len = 1
        cdef bint fixed_length = (self.bus.apu.dmc_dma_request_kind() == 2
                                  and not self.dmc_oam_tail_pending)
        # Initial halt cycle (dummy read of the CPU's address).
        self.halt_cycle(cpu_read_addr, not skip_first_input_clock)
        cdef bint need_dummy = True
        while True:
            # The fetch runs on the first parity-allowed cycle after the
            # pending dummy read has been consumed; every other cycle is an
            # alignment dummy that reads the CPU's address again.
            if (not need_dummy
                    and ((fixed_length and dmc_len >= 3)
                         or (not fixed_length
                             and self.bus.divider.cpu_cycle % 2 == 1))):
                # Fetch cycle: read the sample byte and deliver it.
                self.halt_cycle(0, False)
                self.bus.apu.dmc_deliver(
                    self.bus.read(self.bus.apu.dmc_read_addr(), False))
                self.dmc_oam_tail_pending = False
                return
            # Alignment cycle: another dummy read of the CPU's address.
            self.halt_cycle(cpu_read_addr, not skip_dummy_reads)
            dmc_len += 1
            need_dummy = False

    cdef void tick(self, uint64_t cpu_cycle):
        '''Run one CPU cycle of the shared OAM / DMC get-put cadence.

        Both 2A03 DMA units share one get/put cadence: DMA can only read
        ("get") on one cycle type and write ("put") on the other. Reads land
        on ODD cpu cycles and $2004 writes on EVEN ones. The CPU is halted for
        the whole sequence, but the PPU and APU keep running and the interrupt
        lines keep being propagated, so a device IRQ raised mid-transfer is
        seen the moment the CPU resumes.

        Alignment prefix: 1 halt cycle when the $4014 write fell on an odd
        cpu cycle (first read at W+2, total 513 cycles) and 2 cycles -- halt
        plus one alignment cycle -- when it fell on an even one (first read at
        W+3, total 514). The prefix waits for an EVEN cycle, and the transfer
        itself reads on odd / writes on even. Getting this backwards cost a
        full CPU cycle of halt on one parity and made 4-irq_and_dma's dly=526
        row fire an instruction late. Ref: Mesen2 Core/NES/NesCpu.cpp
        (ProcessPendingDma); NESdev wiki "DMA" (Cadence).

        DMC DMA interaction (NESdev wiki "DMA", "DMC DMA during OAM DMA"):
        when both units want the bus on the same cycle the DMC get wins and
        the OAM DMA is paused. Every no-operation cycle (halt, DMC dummy,
        alignment) is free -- it overlaps useful work of the other unit:
          * a DMC DMA that collides in the middle of the copy costs 2 cycles:
            1 for the DMC get, then 1 for OAM to re-align to a get;
          * one that schedules on the second-to-last put costs 1: its halt
            and dummy cycles ride the last read/put pair;
          * one that schedules on the last put costs 3: after the DMA its
            dummy and alignment cycles are still owed.
        Mesen2 models this by keeping the DMC request inside the OAM loop
        (`while(_dmcDmaRunning || _spriteDmaTransfer)`); this is the same
        state machine.
        '''
        cdef bint dmc_ready = (self.oam_dmc_running
                               and not self.oam_dmc_need_halt
                               and not self.oam_dmc_need_dummy)
        if (self.request_armed and self.bus.dmc_dma_request
                and not self.oam_dmc_running):
            # A request armed before this cycle joins the running OAM DMA
            # instead of stalling the CPU afterwards. It is picked up here,
            # at the top of its first cycle, so this cycle's branch above
            # already saw "not ready" -- exactly Mesen2's ordering.
            self.oam_dmc_running = True
            self.oam_dmc_need_halt = True
            self.oam_dmc_need_dummy = True
            self.bus.dmc_dma_request = False
            self.request_armed = False
        if self.dma_dummy:
            # Alignment prefix: wait for an even (put) cycle.
            if cpu_cycle % 2 == 0:
                self.dma_dummy = False
        elif cpu_cycle % 2 == 1:
            # Get cycle: the DMC's sample fetch has priority over the OAM
            # copy's read.
            if dmc_ready:
                self.bus.apu.dmc_deliver(
                    self.bus.read(self.bus.apu.dmc_read_addr(), False))
                self.oam_dmc_running = False
                # No OAM byte was read this cycle, so no $2004 write is owed:
                # the next put cycle realigns instead.
                self.dma_write_pending = False
            elif self.dma_transfer:
                self.dma_data = self.bus.read(
                    (self.dma_page << 8) | self.dma_addr, False)
                self.dma_write_pending = True
        else:
            # Put cycle: only write if a read is waiting to be put.
            if self.dma_transfer and self.dma_write_pending:
                self.bus.write(0x2004, self.dma_data)
                self.dma_addr += 1
                self.dma_write_pending = False
                if self.dma_addr == 0x00:
                    # DMA complete, reset transfer state.
                    self.dma_transfer = False
                    self.dmc_oam_tail_pending = True
                    # A DMC DMA already in flight keeps the shared get/put
                    # cadence going: re-arming the OAM alignment prefix here
                    # would insert idle cycles the reference RunDma loop
                    # never has.
                    if not self.oam_dmc_running:
                        self.dma_dummy = True
        # One of the DMC DMA's setup cycles is absorbed by this cycle (halt
        # first, then dummy). OAM DMA's own halt/alignment/read/write cycle
        # above does double duty.
        if self.oam_dmc_need_halt:
            self.oam_dmc_need_halt = False
        elif self.oam_dmc_need_dummy:
            self.oam_dmc_need_dummy = False
