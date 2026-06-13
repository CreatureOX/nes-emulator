import pickle

from nes.file_loader import FileLoader
from nes.state cimport State


K_x = 0
K_z = 1
K_a = 2
K_s = 3
K_UP = 4
K_DOWN = 5
K_LEFT = 6
K_RIGHT = 7

cdef class Console:
    """
    Main NES console emulator class.
    
    Orchestrates the CPU, PPU, APU, and cartridge components to provide
    a complete NES system emulation. Handles power-up, reset, clocking,
    input control, and save/load state operations.
    """
    def __init__(self, filename: str) -> None:
        cart = FileLoader.load(filename)
        self.bus = CPUBus(cart)
        self.cpu_debugger = CPUDebugger(self.bus)
        self.ppu_debugger = PPUDebugger(self.bus.ppu)
        self.cartridge_debugger = CartridgeDebugger(self.bus.cartridge)

    cpdef void power_up(self):
        """Initialize the console as if power was just applied."""
        self.bus.power_up()

    cpdef void reset(self):
        """Reset the console as if the reset button was pressed."""
        self.bus.reset()

    cpdef void clock(self):
        """
        Execute a single CPU instruction.
        
        CPU instructions take variable numbers of cycles. This method
        executes until the instruction completes, then returns.
        Uses a two-stage polling loop since some operations require
        multiple complete() checks within a single instruction.
        """
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        while True:
            self.bus.clock()
            if not self.bus.cpu.complete():
                break

    cpdef void frame(self):
        """
        Execute a single video frame (262 scanlines).
        
        NES displays 262 scanlines per frame:
        - Scanlines 0-239: Visible rendering
        - Scanline 240: Post-render idle line
        - Scanlines 241-260: VBLANK period
        - Scanline 261: Pre-render idle line
        """
        # Execute until frame rendering is complete
        while True:
            self.bus.clock()
            if self.bus.ppu.frame_complete:
                break
        # Execute until CPU cycle is complete
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        # Reset frame flag for next frame
        self.bus.ppu.frame_complete = False

    cpdef void run(self):
        """Run a complete frame for rendering."""
        self.bus.run_frame()

    cpdef void control(self, list pressed):
        """
        Update controller input state.
        
        Args:
            pressed: List of 8 boolean values representing button states.
                     Indices: 0=X, 1=Z, 2=A, 3=S, 4=UP, 5=DOWN, 6=LEFT, 7=RIGHT
        """
        # Clear the controller state byte
        self.bus.controller[0] = 0x00
        # Set bits for each pressed button (active low in hardware)
        if pressed[K_x]:
            self.bus.controller[0] |= 0x80
        if pressed[K_z]:
            self.bus.controller[0] |= 0x40
        if pressed[K_a]:
            self.bus.controller[0] |= 0x20
        if pressed[K_s]:
            self.bus.controller[0] |= 0x10
        if pressed[K_UP]:
            self.bus.controller[0] |= 0x08
        if pressed[K_DOWN]:
            self.bus.controller[0] |= 0x04
        if pressed[K_LEFT]:
            self.bus.controller[0] |= 0x02
        if pressed[K_RIGHT]:
            self.bus.controller[0] |= 0x01

    cpdef void save_state(self, str archive_path):
        """Serialize complete console state to a file."""
        cdef State state

        with open(archive_path, "wb") as file:
            state = State(self.bus)
            data = pickle.dump(state, file)

    cpdef void load_state(self, str archive_path):
        """Restore console state from a serialized file."""
        cdef State state

        with open(archive_path, "rb") as file:
            state = pickle.load(file)
            state.load_to(self.bus)