import pickle
import os
import hashlib
from collections import deque

from nes.file_loader import FileLoader
from nes.state cimport State

# Save files are ``MAGIC + 1-byte version + 32-byte sha256 + pickle payload``.
# A version bump or checksum mismatch is rejected instead of feeding a corrupt
# pickle to the loader.
_SAVE_MAGIC = b"FANNESS1"
_SAVE_VERSION = 1


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
        self.filename = filename
        # Rewind is opt-in; disabled until enable_rewind() is called.
        self._rewind_buffer = deque()
        self._rewind_interval = 0
        self._frame_counter = 0
        self.REWIND_MAX_FRAMES = 120
        self.cpu_debugger = CPUDebugger(self.bus)
        self.ppu_debugger = PPUDebugger(self.bus.ppu)
        self.cartridge_debugger = CartridgeDebugger(self.bus.cartridge)

    cpdef void power_up(self):
        """Initialize the console as if power was just applied."""
        self.bus.power_up()

    cpdef void reset(self):
        """Reset the console as if the reset button was pressed."""
        self.bus.reset()
        self.clear_rewind()

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
        """Run a complete frame for rendering, sampling rewind snapshots."""
        self.bus.run_frame()
        if self._rewind_interval > 0:
            self._frame_counter += 1
            if self._frame_counter >= self._rewind_interval:
                self._frame_counter = 0
                self._rewind_buffer.append(State(self.bus))
                while len(self._rewind_buffer) > self.REWIND_MAX_FRAMES:
                    self._rewind_buffer.popleft()

    cpdef void control(self, list pressed):
        '''
        Update controller input state.
        
        Args:
            pressed: List of 8 boolean values representing button states.
                     Indices: 0=X, 1=Z, 2=A, 3=S, 4=UP, 5=DOWN, 6=LEFT, 7=RIGHT
        '''
        buttons = 0x00
        # Set bits for each pressed button (active low in hardware)
        if pressed[K_x]:
            buttons |= 0x80
        if pressed[K_z]:
            buttons |= 0x40
        if pressed[K_a]:
            buttons |= 0x20
        if pressed[K_s]:
            buttons |= 0x10
        if pressed[K_UP]:
            buttons |= 0x08
        if pressed[K_DOWN]:
            buttons |= 0x04
        if pressed[K_LEFT]:
            buttons |= 0x02
        if pressed[K_RIGHT]:
            buttons |= 0x01
        self.bus.joy1.buttons = buttons

    cpdef void save_state(self, str archive_path):
        """Serialize complete console state to a versioned, checked file."""
        cdef State state
        cdef bytes payload

        state = State(self.bus)
        payload = pickle.dumps(state, protocol=pickle.HIGHEST_PROTOCOL)
        header = _SAVE_MAGIC + bytes([_SAVE_VERSION]) + hashlib.sha256(payload).digest()
        with open(archive_path, "wb") as file:
            file.write(header)
            file.write(payload)

    cpdef void load_state(self, str archive_path):
        """Restore console state, rejecting corrupt or incompatible files."""
        cdef State state
        cdef bytes header
        cdef bytes payload

        with open(archive_path, "rb") as file:
            raw = file.read()
        header = raw[:len(_SAVE_MAGIC) + 1 + 32]
        if len(header) < len(_SAVE_MAGIC) + 33 or header[:len(_SAVE_MAGIC)] != _SAVE_MAGIC:
            raise ValueError("Not a FanNes save file")
        if header[len(_SAVE_MAGIC)] != _SAVE_VERSION:
            raise ValueError("Unsupported save version")
        payload = raw[len(header):]
        if hashlib.sha256(payload).digest() != header[len(_SAVE_MAGIC) + 1:]:
            raise ValueError("Save file checksum mismatch")
        state = pickle.loads(payload)
        state.load_to(self.bus)
        # A loaded save starts a new timeline; stale snapshots no longer apply.
        self.clear_rewind()

    cdef str _battery_path(self, str path):
        """Resolve an explicit path or default to <rom basename>.sav."""
        if path:
            return path
        base = os.path.splitext(self.filename)[0]
        return base + ".sav"

    cpdef bint save_battery(self, str path = ""):
        """Write battery-backed SRAM to disk. Return False if none/absent."""
        cdef object ram = self.bus.battery_ram()
        if ram is None:
            return False
        with open(self._battery_path(path), "wb") as file:
            file.write(ram)
        return True

    cpdef bint load_battery(self, str path = ""):
        """Load battery-backed SRAM from disk. Return False if missing."""
        cdef str battery_path = self._battery_path(path)
        if not os.path.exists(battery_path):
            return False
        with open(battery_path, "rb") as file:
            self.bus.load_battery_ram(file.read())
        return True

    cpdef void enable_rewind(self, int interval = 10, int max_frames = 120):
        '''Enable periodic snapshots: one State every `interval` frames.

        A smaller interval rewinds more precisely but uses more memory; each
        snapshot holds full CPU/PPU/cartridge data (~650 KB).
        '''
        self._rewind_interval = interval if interval > 0 else 10
        self.REWIND_MAX_FRAMES = max_frames if max_frames > 0 else 120
        self.clear_rewind()

    cpdef bint rewind(self):
        '''Restore the most recent snapshot. Return False if none buffered.'''
        cdef State state
        if len(self._rewind_buffer) == 0:
            return False
        state = self._rewind_buffer.pop()
        state.load_to(self.bus)
        return True

    cpdef void clear_rewind(self):
        '''Discard all buffered snapshots.'''
        self._rewind_buffer.clear()
        self._frame_counter = 0