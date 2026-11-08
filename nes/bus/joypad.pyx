'''
Standard NES controller port: button latch and serial shift register.

A write to $4016 latches the current button byte into the shift register;
each read of $4016/$4017 returns bit 7 of that register on D0 and shifts a
1 into the low bit, so the eight button states come out in A,B,Select,Start,
Up,Down,Left,Right order and later reads return 1. The upper data-bus bits
are not driven by this device: they keep the address MSB from the open bus
and are combined by CPUBus.read().

Ref: NESdev wiki "Standard controller"; Mesen2 Core/NES/ControlManager.cpp.
'''


cdef class Joypad:
    '''
    One controller port, held by the bus as a first-class device.

    State owned: the live button byte written by the front end and the shift
    register that serializes it. The bus only routes the $4016 strobe and the
    $4016/$4017 reads; it keeps no controller state of its own.
    '''
    def __init__(self):
        '''Start with no buttons held and an empty shift register.'''
        self.reset()

    cpdef void reset(self):
        '''Return the button latch and shift register to the power-up state.'''
        self.buttons = 0x00
        self.shift = 0x00

    cdef void strobe(self):
        '''Latch the live button byte into the shift register ($4016 write).'''
        self.shift = self.buttons

    cdef uint8_t read(self):
        '''Return D0 for one $4016/$4017 read and advance the shift register.

        Shifting in a 1 (rather than 0) makes all reads after the eighth
        return 1, which is what a standard NES controller does on hardware.
        '''
        cdef uint8_t d0 = 1 if (self.shift & 0x80) > 0 else 0
        self.shift = ((self.shift << 1) | 1) & 0xFF
        return d0
