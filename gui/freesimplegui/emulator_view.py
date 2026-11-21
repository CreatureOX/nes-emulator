import FreeSimpleGUI as sg
import sys
import os
import ctypes
import ctypes.wintypes
from gui.freesimplegui.base_view import BaseView
from gui.freesimplegui.keyboard_setting_view import KeyboardSettingWindow
from gui.freesimplegui.keyboard_manager import keyboard_manager
from gui.freesimplegui.cpu_debug_view import CPUDebugWindow
from gui.freesimplegui.ppu_debug_view import PPUDebugWindow
from gui.freesimplegui.disassembler_view import DisassemblerWindow
from gui.freesimplegui.nes_file_view import NesFileWindow

from threading import Thread, Event, Lock
import pygame
import numpy as np
import os
import cv2
from PIL import Image
import time
import sys
import json
import pickle
import ctypes
from gui.freesimplegui.audio_output import AudioOutput

from pathlib import Path
import toml

current_dir = Path(__file__).resolve().parent.parent
project_dir = current_dir.parent

if project_dir not in sys.path:
    sys.path.insert(0, str(project_dir))

from nes.console import Console
from nes.region import NTSC, PAL, DENDY

try:
    _pyproject = toml.load(project_dir / "pyproject.toml")
    APP_NAME = _pyproject["project"]["name"]
    VERSION = _pyproject["project"]["version"]
    AUTHOR = _pyproject["project"]["authors"][0]["name"]
except Exception:
    APP_NAME = "FanNes"
    VERSION = "0.0.1"
    AUTHOR = "Unknown"

def get_resource_path(relative_path):
    if getattr(sys, 'frozen', False):
        base_path = sys._MEIPASS
    else:
        base_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    return os.path.join(base_path, relative_path)


_unique_seq = 0


def _unique_path(directory: str, prefix: str, extension: str) -> str:
    """Build a collision-free path from a millisecond stamp and a sequence.

    The monotonic counter guarantees uniqueness even for calls in the same
    millisecond; an existence check also protects against a reused stamp
    across a process restart.
    """
    global _unique_seq
    _unique_seq += 1
    stamp = int(time.time() * 1000)
    candidate = os.path.join(
        directory, '{}-{}-{}.{}'.format(prefix, stamp, _unique_seq, extension))
    while os.path.exists(candidate):
        _unique_seq += 1
        candidate = os.path.join(
            directory, '{}-{}-{}.{}'.format(prefix, stamp, _unique_seq, extension))
    return candidate


class EmulatorWindow(BaseView):
    __TITLE = APP_NAME

    # Top-level menus carry no '&' mnemonic: Alt + arrow keys navigate them
    # through Tk's native menubar handling. Child items keep their mnemonics.
    __MENU_LAYOUT = [
        ['File', ['&Open', '&Save', '&Load', '&Reset', 'Screenshot', 'Exit']],
        ['Config', ['&Keymap', '&Region', ['&NTSC', '&PAL', '&Dendy']]],
        ['Emulation', ['&Rewind', '&Fast Forward', '&Fullscreen', '&CRT Filter']],
        ['Debug', ['&CPU', '&PPU', '&Disassembler', '&NES File Viewer']],
        ['Help', ['&About',]],
    ]

    # Single source of truth for every menu item's keyboard affordance:
    # event name -> (menu mnemonic, global bind key, displayed hint).
    # The mnemonic is a letter inside the label; Tk underlines it so a key
    # press selects the item even after the menu grabbed the keyboard. Top
    # levels have no mnemonic (Alt+arrows navigate them), child items do.
    # A None bind key means no root binding: Region, CRT Filter, CPU and PPU
    # are menu-only, while Rewind and Fast Forward stay polled in the render
    # loop (Backspace/Space). F11/F12 bind as bare function keys; letters as
    # Alt+letter. A None hint hides the right-aligned accelerator column.
    __SHORTCUTS = {
        'Open': ('o', 'o', 'Alt+O'),
        'Save': ('s', 's', 'Alt+S'),
        'Load': ('l', 'l', 'Alt+L'),
        'Reset': ('r', 'r', 'Alt+R'),
        'Screenshot': ('t', 'F12', 'F12'),
        'Exit': ('x', 'q', 'Alt+Q'),
        'Keymap': ('m', 'm', 'Alt+M'),
        'NTSC': ('n', None, None),
        'PAL': ('p', None, None),
        'Dendy': ('d', None, None),
        'Rewind': ('r', None, 'Backspace'),
        'Fast Forward': ('f', None, 'Space'),
        'Fullscreen': ('l', 'F11', 'F11'),
        'CRT Filter': ('t', None, None),
        'CPU': ('c', None, None),
        'PPU': ('p', None, None),
        'Disassembler': ('i', 'i', 'Alt+I'),
        'NES File Viewer': ('v', 'v', 'Alt+V'),
        'About': ('a', 'a', 'Alt+A'),
    }

    # Region cascade: only concrete profiles are shown. Auto is an internal
    # state (-1) that follows the cartridge header and is reflected by
    # checking whichever profile actually took effect.
    __REGION_LABELS = {
        'NTSC': NTSC,
        'PAL': PAL,
        'Dendy': DENDY,
    }

    __SIZE = ( 800, 600 )

    __RESIZABLE = True

    __FINALIZE = True
     
    def __init__(self):
        super().__init__(title = self.__TITLE,
                         size = self.__SIZE,
                         return_keyboard_events = False,  # Disable keyboard events to fix menu function
                         resizable = self.__RESIZABLE,
                         finalize = self.__FINALIZE,
                         icon = get_resource_path('images/icon.png'))
        
        self.__lock = Lock()
        self.__stop = Event()
        self.__render_thread = None

        # Region override: -1 follows the cartridge header.
        self.__region = -1
        self.__current_rom = None

        # Emulation toggles (plain menu items flip these booleans)
        self.__fast_forward = False
        self.__fullscreen = False
        self.__crt_filter = False

        # File Tab
        self._events["Open"] = self.__run
        self._events["Reset"] = self.__reset
        self._events["Screenshot"] = self.__capture_screenshot
        self._events["Save"] = self.__open_nes_file_hint
        self._events["Load"] = self.__open_nes_file_hint

        # Emulation Tab
        self._events["Rewind"] = self.__rewind
        self._events["Fast Forward"] = self.__toggle_fast_forward
        self._events["Fullscreen"] = self.__toggle_fullscreen
        self._events["CRT Filter"] = self.__toggle_crt_filter

        # Config Tab
        self._events["Keymap"] = self.__open_keymap
        for label, region in self.__REGION_LABELS.items():
            self._events[label] = lambda values, r=region: self.__set_region(r)

        # DEBUG Tab
        self._events["CPU"] = self.__open_nes_file_hint
        self._events["PPU"] = self.__open_nes_file_hint
        self._events["Disassembler"] = self.__open_nes_file_hint
        self._events["NES File Viewer"] = self.__open_nes_file_hint    

        # Help Tab
        self._events["About"] = self.__show_about

    def _layout(self):
        screen_layout = [
            [
                sg.Graph(key = "-SCREEN-", 
                         canvas_size = (400, 300),  # Minimal size, will expand with window
                         graph_bottom_left = (0, 0), 
                         graph_top_right = (400, 300), 
                         background_color = 'BLACK', 
                         expand_x = True, 
                         expand_y = True)
            ]
        ]
        return [
            [ sg.Menu(self.__MENU_LAYOUT, key = '-MENU-') ],
            [ sg.Column(screen_layout, expand_x = True, expand_y = True) ],
        ]

    def __open_nes_file_hint(self, values) -> None:
        sg.popup("Please select a nes file!")

    def _after_open(self) -> None:
        icon_path = get_resource_path('images/icon.png')
        if os.path.exists(icon_path):
            with open(icon_path, 'rb') as f:
                icon_data = f.read()
            self._window.set_icon(icon_data)
        
        # bind Graph (key = "SCREEN") with pygame window
        os.environ['SDL_WINDOWID'] = str(self._window['-SCREEN-'].TKCanvas.winfo_id())

        # Minimal pygame initialization
        pygame.display.quit()  # Quit any existing display
        pygame.display.init()  # Reinitialize display
        
        # Start with a default size, will be updated in the game loop
        self.__game_screen = pygame.display.set_mode((640, 480), pygame.RESIZABLE)

        # Initialize pygame font and event handling
        pygame.font.init()
        
        # Prepare audio output (will be created when a ROM is opened)
        self._audio = None

        self.__setup_menu_labels()

    def __setup_menu_labels(self) -> None:
        """Cache submenus and label them with shortcut hints and toggle state.

        Changing a menu label leaves its command bound to the original event
        name, so neither the hints nor the ✓ marker affect event dispatch.
        """
        self.__submenus = {}
        try:
            menubar = self._window['-MENU-'].TKMenu
            for i in range(menubar.index('end') + 1):
                try:
                    top = menubar.entrycget(i, 'label')
                    if top not in ('File', 'Config', 'Emulation', 'Debug', 'Help'):
                        continue
                    menu_path = menubar.entrycget(i, 'menu')
                    menu = self._window.TKroot.nametowidget(menu_path)
                    self.__submenus[top] = menu
                    # Region is a nested cascade under Config; cache its
                    # child menu so the active-profile check can reach it.
                    if top == 'Config':
                        for j in range(menu.index('end') + 1):
                            try:
                                if menu.type(j) != 'cascade' or \
                                        menu.entrycget(j, 'label') != 'Region':
                                    continue
                                sub_path = menu.entrycget(j, 'menu')
                                self.__submenus['Region'] = \
                                    self._window.TKroot.nametowidget(sub_path)
                            except Exception:
                                continue
                except Exception:
                    continue
        except Exception:
            pass
        self.__refresh_menu_labels()
        # Relabeling strips the '&' that gave native menu accelerators, so
        # bind the advertised shortcuts on the Tk root explicitly (letters
        # with Alt, F11/F12 bare). Menu-only and polled items (Backspace/
        # Space) have no bind key and are skipped; they are reached through
        # their underline mnemonic.
        try:
            root = self._window.TKroot
            for event, (_mnemonic, key, _hint) in self.__SHORTCUTS.items():
                if key is None:
                    continue
                callback = lambda _e, name=event: \
                    self._window.write_event_value(name, None)
                # Tk accepts <Alt-o> for letters (normalizes to <Alt-Key-o>)
                # but silently ignores <Alt-1>; digits need the Key- token.
                # Function keys such as F12 bind bare, with no Alt modifier.
                if key.startswith('F') and key[1:].isdigit():
                    sequences = ('<' + key + '>',)
                elif key.isdigit():
                    sequences = ('<Alt-Key-' + key + '>',)
                else:
                    sequences = ('<Alt-' + key + '>', '<Alt-' + key.upper() + '>')
                for seq in sequences:
                    root.bind(seq, callback)
        except Exception:
            pass

    def __refresh_menu_labels(self) -> None:
        """Mark active toggles and show shortcuts as right-aligned accelerators.

        Tk renders the accelerator column at the menu's right edge, matching
        Mesen's layout. Rebuilt from a fixed item list each time so a ✓ from a
        prior toggle never accumulates; matching strips the marker.
        """
        toggles = {
            'Fast Forward': self.__fast_forward,
            'Fullscreen': self.__fullscreen,
            'CRT Filter': self.__crt_filter,
        }
        # Reflect the region actually in effect. In Auto mode __region is -1
        # and the console resolved it from the header; bus.region is public
        # and carries that resolved value, so the check lands on the profile
        # the ROM is really running under.
        console = getattr(self, '_EmulatorWindow__console', None)
        effective_region = getattr(console.bus, 'region', None) if console else None
        active_region = next(
            (label for label, r in self.__REGION_LABELS.items()
             if r == effective_region), None)
        for menu in self.__submenus.values():
            for i in range(menu.index('end') + 1):
                try:
                    plain = menu.entrycget(i, 'label').lstrip('\u2713 ')
                    if plain not in self.__SHORTCUTS:
                        continue
                    text = plain
                    if plain == active_region or toggles.get(plain, False):
                        text = '\u2713 ' + text
                    # Point the underline at the mnemonic inside the label.
                    # Once a menu owns the Tk grab, only its underline
                    # responds to keys; root Alt binds are swallowed. The
                    # offset accounts for a leading checkmark and space.
                    mnemonic = self.__SHORTCUTS[plain][0]
                    pos = text.lower().find(mnemonic.lower())
                    underline = pos if pos >= 0 else -1
                    hint = self.__SHORTCUTS[plain][2]
                    menu.entryconfig(i, label=text,
                                     accelerator=hint or '',
                                     underline=underline)
                except Exception:
                    continue

    def _before_exit(self, values = None) -> None:
        self.__stop.set()
        thread = self.__render_thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=2.0)
        # Flush battery-backed SRAM before leaving.
        try:
            if getattr(self, '_EmulatorWindow__console', None) is not None:
                self.__console.save_battery()
        except Exception:
            pass
        try:
            if getattr(self, '_audio', None) is not None:
                self._audio.stop()
        except Exception:
            pass

    def __open_file(self) -> bool:
        file_path = sg.popup_get_file('File to open', file_types = (("NES Files", "*.nes"),), no_window = True)
        if file_path is None or file_path == '':
            sg.popup("Invalid .nes file path!")
            return False
        # A freshly opened ROM returns to Auto: its header decides the
        # profile. A manual Region pick only overrides the current ROM and is
        # re-applied through __set_region, which reloads without calling here.
        self.__region = -1
        return self.__load_rom(file_path)

    def __load_rom(self, file_path) -> bool:
        """Bind a fresh console for file_path using the active region override."""
        # Flush the previous cartridge's battery RAM before switching ROMs.
        if getattr(self, '_EmulatorWindow__console', None) is not None:
            try:
                self.__console.save_battery()
            except Exception:
                pass

        # Stop the old audio thread before the new one reuses the same mixer
        # channel; otherwise the previous ROM's queued samples leak into the
        # new run and ignore mute/volume changes on the new object.
        try:
            if getattr(self, '_audio', None) is not None:
                self._audio.stop()
                self._audio = None
        except Exception:
            pass

        # Stop the previous render thread before swapping consoles. Both the
        # old and new loops read self.__console each frame; leaving the old one
        # alive drives the new ROM twice per tick (double speed, doubled audio).
        self.__stop_render_thread()

        # run .nes file with the active region override (-1 = header auto).
        self.__console = Console(file_path, self.__region)
        self.__console.power_up()
        self.__current_rom = file_path
        # Restore a matching .sav if one exists.
        try:
            self.__console.load_battery()
        except Exception:
            pass
        # Enable periodic rewind snapshots (one per 10 frames, ~2 s buffer).
        try:
            self.__console.enable_rewind(10, 120)
        except Exception:
            pass

        # Initialize audio output for this run; use bus.apu if available.
        try:
            self._audio = AudioOutput(sample_rate=44100, chunk_size=1024, max_queue=16)
            self._audio.play_test_tone(frequency=440.0, duration=0.4, volume=0.4)
        except Exception:
            self._audio = None

        # update emulator window title
        filename_with_extension = os.path.basename(file_path)
        self.filename, extension = os.path.splitext(filename_with_extension)
        self._window.TKroot.title(APP_NAME + ': ' + self.filename)

        # bind events about console
        self._events["CPU"] = CPUDebugWindow(self.__console).open
        self._events["PPU"] = PPUDebugWindow(self.__console).open
        self._events["Disassembler"] = DisassemblerWindow(self.__console).open
        self._events["NES File Viewer"] = NesFileWindow(self.__console).open

        self._events["Save"] = self.__save
        self._events["Load"] = self.__load

        # Auto mode resolves the profile from this ROM's header; move the ✓
        # to whichever profile the fresh console actually selected.
        self.__refresh_menu_labels()

        return True
    
    def __save(self, values):
        if not os.path.exists("./saves"):
            os.mkdir("./saves")
        archive_name = _unique_path("./saves", self.filename, "sav")
        self.__console.save_state(archive_name)

    def __load(self, values):
        archive_path = sg.popup_get_file('File to open', file_types = (("NES Archives", "*.sav"),), no_window = True)
        if archive_path is None or archive_path == '':
            sg.popup("Invalid .sav file path!")
            return
        try:
            self.__console.load_state(archive_path)
        except (ValueError, OSError, EOFError, pickle.UnpicklingError) as exc:
            sg.popup("Could not load save file!", str(exc))

    def __resize(self, original_image: np.ndarray, display_width: int, display_height: int) -> np.ndarray:
        """
        Resize image to fill the entire display.
        Returns the resized image ready to fill the screen.
        """
        # Resize to fill the entire display area
        resized_image = cv2.resize(original_image, (display_width, display_height), interpolation=cv2.INTER_LINEAR)
        
        return resized_image   
    
    def __run_file(self) -> None:
        # Initialize pygame clock for frame limiting
        clock = pygame.time.Clock()
        
        # Use Windows API for reliable key state detection
        import sys
        if sys.platform.startswith('win'):
            import ctypes
            user32 = ctypes.windll.user32
            
            # Map pygame key codes to virtual key codes
            pygame_to_vk = {
                pygame.K_1: 0x31, pygame.K_2: 0x32, pygame.K_3: 0x33, pygame.K_4: 0x34, pygame.K_5: 0x35,
                pygame.K_6: 0x36, pygame.K_7: 0x37, pygame.K_8: 0x38, pygame.K_9: 0x39, pygame.K_0: 0x30,
                pygame.K_q: 0x51, pygame.K_w: 0x57, pygame.K_e: 0x45, pygame.K_r: 0x52, pygame.K_t: 0x54,
                pygame.K_y: 0x59, pygame.K_u: 0x55, pygame.K_i: 0x49, pygame.K_o: 0x4F, pygame.K_p: 0x50,
                pygame.K_a: 0x41, pygame.K_s: 0x53, pygame.K_d: 0x44, pygame.K_f: 0x46, pygame.K_g: 0x47,
                pygame.K_h: 0x48, pygame.K_j: 0x4A, pygame.K_k: 0x4B, pygame.K_l: 0x4C,
                pygame.K_z: 0x5A, pygame.K_x: 0x58, pygame.K_c: 0x43, pygame.K_v: 0x56, pygame.K_b: 0x42,
                pygame.K_n: 0x4E, pygame.K_m: 0x4D,
                pygame.K_UP: 0x26, pygame.K_DOWN: 0x28, pygame.K_LEFT: 0x25, pygame.K_RIGHT: 0x27,
                pygame.K_BACKSPACE: 0x08,
                pygame.K_SPACE: 0x20,
            }
            
            def get_key_state(key_code):
                vk = pygame_to_vk.get(key_code)
                if vk is None:
                    return False
                return user32.GetAsyncKeyState(vk) & 0x8000 != 0
        else:
            # For non-Windows platforms, use pygame key detection
            def get_key_state(key_code):
                pressed = pygame.key.get_pressed()
                return pressed[key_code] if key_code < len(pressed) else False

        # Alt + letter drives menu shortcuts. While Alt is held, ignore the
        # mapped gamepad keys so a shortcut cannot also press a NES button.
        if sys.platform.startswith('win'):
            def alt_held():
                return user32.GetAsyncKeyState(0x12) & 0x8000 != 0  # VK_MENU
        else:
            def alt_held():
                pressed = pygame.key.get_pressed()
                return pressed[pygame.K_LALT] or pressed[pygame.K_RALT]

        # Wait a bit for the game to initialize and enable rendering
        frames_waited = 0
        MAX_WAIT_FRAMES = 300  # Wait up to 5 seconds at 60fps
        
        last_canvas_width, last_canvas_height = 640, 480
        rewind_held = False

        while not self.__stop.is_set():
            # Backspace rewinds one snapshot on the rising edge only.
            backspace = get_key_state(pygame.K_BACKSPACE)
            if backspace and not rewind_held:
                try:
                    self.__console.rewind()
                except Exception:
                    pass
            rewind_held = backspace

            # Get the actual canvas size from TKinter each frame
            try:
                canvas = self._window['-SCREEN-'].TKCanvas
                canvas_width = canvas.winfo_width()
                canvas_height = canvas.winfo_height()
                
                # Ensure we have valid dimensions
                if canvas_width < 100 or canvas_height < 100:
                    canvas_width, canvas_height = last_canvas_width, last_canvas_height
                else:
                    last_canvas_width, last_canvas_height = canvas_width, canvas_height
                    
                    # Resize pygame display to match canvas size
                    try:
                        current_size = self.__game_screen.get_size()
                        if current_size[0] != canvas_width or current_size[1] != canvas_height:
                            self.__game_screen = pygame.display.set_mode((canvas_width, canvas_height), pygame.RESIZABLE)
                    except:
                        self.__game_screen = pygame.display.set_mode((canvas_width, canvas_height), pygame.RESIZABLE)
            except:
                canvas_width, canvas_height = last_canvas_width, last_canvas_height
            
            # Get latest keyboard config from global keyboard manager (check every frame, supports real-time updates)
            keyboard = keyboard_manager.get_keyboard()
            
            # Console.control() indexes the eight physical NES buttons in
            # A, B, Select, Start, Up, Down, Left, Right order. The keyboard
            # config is keyed by button name, so reorder it explicitly here.
            # Suppress all gamepad input while Alt is down: menu shortcuts use
            # Alt + letter, and those letters may double as mapped game keys.
            suppress = alt_held()
            control_inputs = [
                (not suppress) and get_key_state(keyboard['A']),
                (not suppress) and get_key_state(keyboard['B']),
                (not suppress) and get_key_state(keyboard['SELECT']),
                (not suppress) and get_key_state(keyboard['START']),
                (not suppress) and get_key_state(keyboard['UP']),
                (not suppress) and get_key_state(keyboard['DOWN']),
                (not suppress) and get_key_state(keyboard['LEFT']),
                (not suppress) and get_key_state(keyboard['RIGHT'])
            ]
            
            # Fast forward runs several frames per display update and skips
            # the 60 FPS throttle. Holding Space is a temporary override;
            # the menu toggle stays latched until clicked again.
            space_held = get_key_state(pygame.K_SPACE)
            fast_forward = self.__fast_forward or space_held
            frames_per_tick = 4 if fast_forward else 1
            for _ in range(frames_per_tick):
                self.__console.control(control_inputs)
                self.__console.run()
            if getattr(self, '_audio', None) is not None:
                self._audio.set_muted(fast_forward)
            
            # Get screen data - ensure we get a copy, not just a view
            ppu_screen = self.__console.bus.ppu.screen()
            if ppu_screen is None:
                frames_waited += 1
                pygame.display.flip()
                clock.tick(60)
                continue
                
            original_image = np.array(ppu_screen, copy=True)
            
            # Check if screen is still black (all zeros)
            is_black = np.all(original_image == 0)
            if frames_waited < MAX_WAIT_FRAMES and is_black:
                frames_waited += 1
                pygame.display.flip()
                clock.tick(60)
                continue
            
            # Resize image to fill the entire display
            resized_image = self.__resize(original_image, canvas_width, canvas_height)

            # Optional CRT scanline shading on every other display row.
            if self.__crt_filter:
                for row in range(0, resized_image.shape[0], 2):
                    resized_image[row] = (resized_image[row] * 0.72).astype(np.uint8)
            
            # Clear the entire display with black background
            self.__game_screen.fill((0, 0, 0))
            
            # Ensure the array is in the right format for pygame surfarray
            resized_image = resized_image.astype(np.uint8)
            
            # Create surface from the resized image
            try:
                if len(resized_image.shape) == 2:
                    # Grayscale - convert to RGB
                    resized_image = np.stack([resized_image] * 3, axis=2)
                
                surf = pygame.surfarray.make_surface(np.transpose(resized_image, (1, 0, 2)))
            except:
                # Fallback: try direct surface creation
                surf = pygame.surfarray.make_surface(resized_image)
            
            # Blit the image to fill the entire screen
            self.__game_screen.blit(surf, (0, 0))
            pygame.display.flip()

            # Generate and enqueue audio for this frame from the bus APU.
            # Fast-forward still drains (so the APU's filter state keeps
            # advancing) but drops the samples: the mixer cannot play 4x
            # samples at 1x rate without pitch distortion or queue overflow.
            try:
                if getattr(self, '_audio', None) is not None:
                    apu = getattr(self.__console.bus, 'apu', None)
                    if apu is not None:
                        samples = apu.drain_samples()
                        if (not fast_forward and isinstance(samples, np.ndarray)
                                and samples.dtype == np.int16 and samples.size > 0):
                            self._audio.enqueue(samples)
            except Exception:
                pass
            if not fast_forward:
                clock.tick(60)  # Limit to 60 FPS for smooth gameplay
            frames_waited += 1

    def __stop_render_thread(self) -> None:
        """Signal the render loop to stop and wait for it to exit."""
        self.__stop.set()
        thread = self.__render_thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=2.0)
        # Re-arm for the next ROM; a join that timed out still sees the signal.
        self.__render_thread = None
        self.__stop.clear()

    def __start_render_thread(self) -> None:
        """Launch the render loop; the caller owns ROM loading."""
        self.__render_thread = Thread(target = self.__run_file, daemon = True)
        self.__render_thread.start()

    def __run(self, values) -> None:
        success = self.__open_file()
        if not success:
            return
        self.__start_render_thread()

    def __set_region(self, region: int) -> None:
        """Apply a region override and reload the current ROM with it."""
        self.__region = region
        if self.__current_rom is not None:
            # __load_rom rebuilds the console and moves the ✓ to bus.region,
            # which only reflects this override once the console exists.
            self.__load_rom(self.__current_rom)
            self.__start_render_thread()

    def __capture_screenshot(self, values) -> None:
        image_data = np.array(self.__console.bus.ppu.screen(), copy = True)

        # Apply the same scanline shading shown in the window so the
        # screenshot matches what the player sees when CRT Filter is on.
        if self.__crt_filter:
            for row in range(0, image_data.shape[0], 2):
                image_data[row] = (image_data[row] * 0.72).astype(np.uint8)

        if not os.path.exists("./screenshots"):
            os.mkdir("./screenshots")
        screenshot_path = _unique_path("./screenshots", "screenshot", "jpg")

        image = Image.fromarray(image_data)
        image.save(screenshot_path)

    def __reset(self, values) -> None:
        self.__console.reset()
    
    def __rewind(self, values) -> None:
        try:
            self.__console.rewind()
        except Exception:
            pass

    def __toggle_fast_forward(self, values) -> None:
        self.__fast_forward = not self.__fast_forward
        self.__refresh_menu_labels()

    def __toggle_fullscreen(self, values) -> None:
        self.__fullscreen = not self.__fullscreen
        try:
            self._window.TKroot.attributes('-fullscreen', self.__fullscreen)
        except Exception:
            pass
        self.__refresh_menu_labels()

    def __toggle_crt_filter(self, values) -> None:
        self.__crt_filter = not self.__crt_filter
        self.__refresh_menu_labels()

    def __show_about(self, values) -> None:
        sg.popup(f'{APP_NAME}\nVersion: {VERSION}\nAuthor: {AUTHOR}\n')
    
    def __open_keymap(self, values) -> None:
        # Open keyboard settings in a separate thread to avoid blocking main window
        keymap_window = KeyboardSettingWindow()
        keymap_window.open()

if __name__ == "__main__":
    emulator_window = EmulatorWindow()
    emulator_window.open()