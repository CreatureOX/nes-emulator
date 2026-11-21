from libc.stdint cimport uint8_t

import cython
import numpy as np
cimport numpy as np

from nes.cpu.cpu_state cimport CPUState
from nes.ppu.ppu_state cimport PPUState
from nes.cart.cart_state cimport CartridgeState
from nes.bus.bus cimport CPUBus


cdef object _freeze(object value):
    '''Convert a mapper snapshot field into a picklable value.

    Cython's __reduce_cython__() emits numpy memoryviews and C arrays as
    list/tuple fields. Memoryviews cannot be pickled, so they are wrapped
    with their bytes payload and dtype/shape to be rebuilt on load.
    '''
    if isinstance(value, np.ndarray):
        return ('nd', value.tobytes(), str(value.dtype), value.shape)
    if isinstance(value, (memoryview, bytearray)):
        return ('mv', bytes(value))
    if type(value).__name__ == '_memoryviewslice':
        return ('mv', bytes(value))
    if isinstance(value, list):
        return [_freeze(item) for item in value]
    if isinstance(value, tuple):
        return tuple(_freeze(item) for item in value)
    return value


cdef object _thaw(object value):
    '''Rebuild a frozen mapper snapshot field for __setstate_cython__().'''
    if isinstance(value, tuple):
        if len(value) == 4 and value[0] == 'nd':
            return np.frombuffer(value[1], dtype=np.dtype(value[2])).reshape(value[3]).copy()
        if len(value) == 2 and value[0] == 'mv':
            return bytearray(value[1])
        return tuple(_thaw(item) for item in value)
    if isinstance(value, list):
        return [_thaw(item) for item in value]
    return value


cdef object _mapper_snapshot(CPUBus bus):
    '''Capture the active mapper's internal registers for persistence.'''
    cdef object mapper = bus.cartridge.mapper
    cdef tuple reduce_tuple = mapper.__reduce_cython__()
    # __reduce_cython__() is (rebuild_fn, (cls, id, init_state), fields) for
    # __init__-based mappers, or (rebuild_fn, (cls, id, cinit_state)) when a
    # __cinit__ exists. The field payload is the last element either way.
    return _freeze(reduce_tuple[-1])


cdef void _mapper_restore(CPUBus bus, object snapshot):
    '''Restore the active mapper's internal registers in place.'''
    cdef object mapper = bus.cartridge.mapper
    cdef object fields = _thaw(snapshot)
    mapper.__setstate_cython__(fields)


cdef object _apu_snapshot(CPUBus bus):
    '''Capture every APU runtime field that evolves between register writes.

    Constants derived at power-up (sample rate, filter coefficients) and the
    output sample queue are excluded; everything that changes the chip's
    execution,IRQ timing or waveform phase is included.
    '''
    cdef APU2A03 apu = bus.apu
    return {
        'sample_pos': apu.sample_pos,
        'next_sample': apu.next_sample,
        'blip_level': apu.blip_level,
        'last_dac': apu.last_dac,
        'blip_buf': [apu.blip_buf[i] for i in range(64)],
        'pulse_duty': [apu.pulse_duty[i] for i in range(2)],
        'pulse_volume': [apu.pulse_volume[i] for i in range(2)],
        'pulse_constant': [apu.pulse_constant[i] for i in range(2)],
        'pulse_env_period': [apu.pulse_env_period[i] for i in range(2)],
        'pulse_env_divider': [apu.pulse_env_divider[i] for i in range(2)],
        'pulse_env_decay': [apu.pulse_env_decay[i] for i in range(2)],
        'pulse_env_start': [apu.pulse_env_start[i] for i in range(2)],
        'pulse_timer': [apu.pulse_timer[i] for i in range(2)],
        'pulse_period': [apu.pulse_period[i] for i in range(2)],
        'pulse_step': [apu.pulse_step[i] for i in range(2)],
        'pulse_sweep_enabled': [apu.pulse_sweep_enabled[i] for i in range(2)],
        'pulse_sweep_period': [apu.pulse_sweep_period[i] for i in range(2)],
        'pulse_sweep_negate': [apu.pulse_sweep_negate[i] for i in range(2)],
        'pulse_sweep_shift': [apu.pulse_sweep_shift[i] for i in range(2)],
        'pulse_sweep_divider': [apu.pulse_sweep_divider[i] for i in range(2)],
        'pulse_sweep_reload': [apu.pulse_sweep_reload[i] for i in range(2)],
        'pulse_sweep_mute': [apu.pulse_sweep_mute[i] for i in range(2)],
        'channel_enabled': [apu.channel_enabled[i] for i in range(4)],
        'length_counter': [apu.length_counter[i] for i in range(4)],
        'length_halt': [apu.length_halt[i] for i in range(4)],
        'length_reload_pending': [apu.length_reload_pending[i] for i in range(4)],
        'length_reload_prev': [apu.length_reload_prev[i] for i in range(4)],
        'length_new_halt': [apu.length_new_halt[i] for i in range(4)],
        'tri_linear_reload': apu.tri_linear_reload,
        'tri_linear_counter': apu.tri_linear_counter,
        'tri_reload_flag': apu.tri_reload_flag,
        'tri_step': apu.tri_step,
        'tri_timer': apu.tri_timer,
        'tri_period': apu.tri_period,
        'noise_shift': apu.noise_shift,
        'noise_mode': apu.noise_mode,
        'noise_index': apu.noise_index,
        'noise_timer': apu.noise_timer,
        'noise_constant': apu.noise_constant,
        'noise_volume': apu.noise_volume,
        'noise_env_period': apu.noise_env_period,
        'noise_env_divider': apu.noise_env_divider,
        'noise_env_decay': apu.noise_env_decay,
        'noise_env_start': apu.noise_env_start,
        'frame_mode': apu.frame_mode,
        'frame_irq_inhibit': apu.frame_irq_inhibit,
        'frame_irq_flag': apu.frame_irq_flag,
        'frame_cycle': apu.frame_cycle,
        'frame_reset_delay': apu.frame_reset_delay,
        'cycle_parity': apu.cycle_parity,
        'dmc_request_kind': apu.dmc_request_kind,
        'dmc_irq_enable': apu.dmc_irq_enable,
        'dmc_loop': apu.dmc_loop,
        'dmc_rate': apu.dmc_rate,
        'dmc_addr': apu.dmc_addr,
        'dmc_addr_load': apu.dmc_addr_load,
        'dmc_len': apu.dmc_len,
        'dmc_len_load': apu.dmc_len_load,
        'dmc_buffer': apu.dmc_buffer,
        'dmc_shift': apu.dmc_shift,
        'dmc_bits': apu.dmc_bits,
        'dmc_timer': apu.dmc_timer,
        'dmc_period': apu.dmc_period,
        'dmc_silence': apu.dmc_silence,
        'dmc_transfer_delay': apu.dmc_transfer_delay,
        'dmc_disable_delay': apu.dmc_disable_delay,
        'dmc_irq_flag': apu.dmc_irq_flag,
        'dmc_output': apu.dmc_output,
        'last_output': apu.last_output,
        'hp1_last_input': apu.hp1_last_input,
        'hp1_last_output': apu.hp1_last_output,
        'hp2_last_input': apu.hp2_last_input,
        'hp2_last_output': apu.hp2_last_output,
        'lp_last_output': apu.lp_last_output,
    }


cdef void _apu_restore(CPUBus bus, object snap):
    cdef APU2A03 apu = bus.apu
    cdef int i
    apu.sample_pos = snap['sample_pos']
    apu.next_sample = snap['next_sample']
    apu.blip_level = snap['blip_level']
    apu.last_dac = snap['last_dac']
    for i in range(64):
        apu.blip_buf[i] = snap['blip_buf'][i]
    for i in range(2):
        apu.pulse_duty[i] = snap['pulse_duty'][i]
        apu.pulse_volume[i] = snap['pulse_volume'][i]
        apu.pulse_constant[i] = snap['pulse_constant'][i]
        apu.pulse_env_period[i] = snap['pulse_env_period'][i]
        apu.pulse_env_divider[i] = snap['pulse_env_divider'][i]
        apu.pulse_env_decay[i] = snap['pulse_env_decay'][i]
        apu.pulse_env_start[i] = snap['pulse_env_start'][i]
        apu.pulse_timer[i] = snap['pulse_timer'][i]
        apu.pulse_period[i] = snap['pulse_period'][i]
        apu.pulse_step[i] = snap['pulse_step'][i]
        apu.pulse_sweep_enabled[i] = snap['pulse_sweep_enabled'][i]
        apu.pulse_sweep_period[i] = snap['pulse_sweep_period'][i]
        apu.pulse_sweep_negate[i] = snap['pulse_sweep_negate'][i]
        apu.pulse_sweep_shift[i] = snap['pulse_sweep_shift'][i]
        apu.pulse_sweep_divider[i] = snap['pulse_sweep_divider'][i]
        apu.pulse_sweep_reload[i] = snap['pulse_sweep_reload'][i]
        apu.pulse_sweep_mute[i] = snap['pulse_sweep_mute'][i]
    for i in range(4):
        apu.channel_enabled[i] = snap['channel_enabled'][i]
        apu.length_counter[i] = snap['length_counter'][i]
        apu.length_halt[i] = snap['length_halt'][i]
        apu.length_reload_pending[i] = snap['length_reload_pending'][i]
        apu.length_reload_prev[i] = snap['length_reload_prev'][i]
        apu.length_new_halt[i] = snap['length_new_halt'][i]
    apu.tri_linear_reload = snap['tri_linear_reload']
    apu.tri_linear_counter = snap['tri_linear_counter']
    apu.tri_reload_flag = snap['tri_reload_flag']
    apu.tri_step = snap['tri_step']
    apu.tri_timer = snap['tri_timer']
    apu.tri_period = snap['tri_period']
    apu.noise_shift = snap['noise_shift']
    apu.noise_mode = snap['noise_mode']
    apu.noise_index = snap['noise_index']
    apu.noise_timer = snap['noise_timer']
    apu.noise_constant = snap['noise_constant']
    apu.noise_volume = snap['noise_volume']
    apu.noise_env_period = snap['noise_env_period']
    apu.noise_env_divider = snap['noise_env_divider']
    apu.noise_env_decay = snap['noise_env_decay']
    apu.noise_env_start = snap['noise_env_start']
    # noise_output is derived from the LFSR bit and the envelope each cycle.
    # Rebuild it from the restored inputs instead of storing a value whose
    # phase can lag one clock behind the shift register it came from.
    apu.noise_output = 0 if (apu.noise_shift & 0x01) else \
        (apu.noise_volume if apu.noise_constant else apu.noise_env_decay)
    apu.frame_mode = snap['frame_mode']
    apu.frame_irq_inhibit = snap['frame_irq_inhibit']
    apu.frame_irq_flag = snap['frame_irq_flag']
    apu.frame_cycle = snap['frame_cycle']
    apu.frame_reset_delay = snap['frame_reset_delay']
    apu.cycle_parity = snap['cycle_parity']
    apu.dmc_request_kind = snap['dmc_request_kind']
    apu.dmc_irq_enable = snap['dmc_irq_enable']
    apu.dmc_loop = snap['dmc_loop']
    apu.dmc_rate = snap['dmc_rate']
    apu.dmc_addr = snap['dmc_addr']
    apu.dmc_addr_load = snap['dmc_addr_load']
    apu.dmc_len = snap['dmc_len']
    apu.dmc_len_load = snap['dmc_len_load']
    apu.dmc_buffer = snap['dmc_buffer']
    apu.dmc_shift = snap['dmc_shift']
    apu.dmc_bits = snap['dmc_bits']
    apu.dmc_timer = snap['dmc_timer']
    apu.dmc_period = snap['dmc_period']
    apu.dmc_silence = snap['dmc_silence']
    apu.dmc_transfer_delay = snap['dmc_transfer_delay']
    apu.dmc_disable_delay = snap['dmc_disable_delay']
    apu.dmc_irq_flag = snap['dmc_irq_flag']
    apu.dmc_output = snap['dmc_output']
    apu.last_output = snap['last_output']
    apu.hp1_last_input = snap['hp1_last_input']
    apu.hp1_last_output = snap['hp1_last_output']
    apu.hp2_last_input = snap['hp2_last_input']
    apu.hp2_last_output = snap['hp2_last_output']
    apu.lp_last_output = snap['lp_last_output']


cdef object _bus_snapshot(CPUBus bus):
    '''Capture bus-owned routed signals and timing counters.'''
    cdef ClockDivider divider = bus.divider
    cdef object dma_fields = bus.dma.__reduce_cython__()
    cdef list dma_list = list(dma_fields[-1])
    # Field 1 is the CPUBus back-reference; drop it so pickling the snapshot
    # does not drag in the whole console, and rebind it on restore instead.
    dma_list[1] = None
    return {
        'divider_dot': divider.dot,
        'divider_cpu_cycle': divider.cpu_cycle,
        'divider_phase': divider.phase,
        'divider_cpu_tick_edge': divider.cpu_tick_edge,
        'divider_phi2_edge': divider.phi2_edge,
        'open_bus': bus.open_bus,
        'dmc_dma_request': bus.dmc_dma_request,
        'joy1_buttons': bus.joy1.buttons,
        'joy1_shift': bus.joy1.shift,
        'joy2_buttons': bus.joy2.buttons,
        'joy2_shift': bus.joy2.shift,
        # A snapshot can land mid-OAM/DMC transfer. The DMA controller's
        # page/addr/data, pending flags and DMC request latch travel with the
        # divider phase that drives its tick.
        'dma_fields': _freeze(tuple(dma_list)),
    }


cdef void _bus_restore(CPUBus bus, object snap):
    cdef ClockDivider divider = bus.divider
    cdef list dma_list = list(_thaw(snap['dma_fields']))
    divider.dot = snap['divider_dot']
    divider.cpu_cycle = snap['divider_cpu_cycle']
    # cpu_tick_edge / phi2_edge are read by bus.clock() on the very next dot
    # before advance() publishes new ones, so rebuild them from the phase.
    # The phase is dot % cycle_dots in every grid. A save may load under a
    # different region, so derive it from the dot instead of the saved value:
    # folding the old phase into a new grid leaves it misaligned by a dot.
    divider.phase = divider.dot % divider.cycle_dots
    divider._update_edges()
    bus.open_bus = snap['open_bus']
    bus.dmc_dma_request = snap['dmc_dma_request']
    bus.joy1.buttons = snap['joy1_buttons']
    bus.joy1.shift = snap['joy1_shift']
    bus.joy2.buttons = snap['joy2_buttons']
    bus.joy2.shift = snap['joy2_shift']
    dma_list[1] = bus  # rebind the CPUBus back-reference
    bus.dma.__setstate_cython__(tuple(dma_list))


@cython.auto_pickle(True)
cdef class State:
    """
    Serializable state container for save/load functionality.

    Bundles CPU, PPU, cartridge, mapper, APU and bus state into a single
    object that can be pickled for persistence. Mapper fields are frozen
    into picklable containers because Cython memoryviews cannot be pickled.
    """
    def __init__(self, CPUBus bus) -> None:
        self.cpu_state = CPUState(bus.cpu)
        self.ppu_state = PPUState(bus.ppu)
        self.cartridge_state = CartridgeState(bus.cartridge)
        self.mapper_snapshot = _mapper_snapshot(bus)
        self.apu_snapshot = _apu_snapshot(bus)
        self.bus_snapshot = _bus_snapshot(bus)

    cdef void load_to(self, CPUBus bus):
        """Restore saved state to the console components."""
        self.cpu_state.load_to(bus.cpu)
        self.ppu_state.load_to(bus.ppu)
        self.cartridge_state.load_to(bus.cartridge)
        _mapper_restore(bus, self.mapper_snapshot)
        _apu_restore(bus, self.apu_snapshot)
        _bus_restore(bus, self.bus_snapshot)
