import FreeSimpleGUI as sg
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
import ctypes
from gui.freesimplegui.audio_output import AudioOutput

from pathlib import Path

current_dir = Path(__file__).resolve().parent.parent
project_dir = current_dir.parent

if project_dir not in sys.path:
    sys.path.insert(0, str(project_dir))

from nes.console import Console


VERSION = "0.0.1"
AUTHOR = "CreatureOX"

class EmulatorWindow(BaseView):
    __TITLE = "NES Emulator"

    __MENU_LAYOUT = [
        ['File', ['Open', 'Save', 'Load', 'Reset', 'Screenshot', 'Exit']],
        ['Config', ['Keymap']],
        ['Debug', ['CPU','PPU','Disassembler','NES File Viewer']],
        ['Help', ['About',]],
    ]

    __SIZE = ( 800, 600 )

    __RESIZABLE = True

    __FINALIZE = True
     
    def __init__(self):
        super().__init__(title = self.__TITLE,
                         size = self.__SIZE,
                         return_keyboard_events = False,  # Disable keyboard events to fix menu function
                         resizable = self.__RESIZABLE,
                         finalize = self.__FINALIZE)
        self.__lock = Lock()
        self.__stop = Event()

        # File Tab
        self._events["Open"] = self.__run
        self._events["Reset"] = self.__reset
        self._events["Screenshot"] = self.__capture_screenshot
        self._events["Save"] = self.__open_nes_file_hint
        self._events["Load"] = self.__open_nes_file_hint

        # Config Tab
        self._events["Keymap"] = self.__open_keymap

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
            [ sg.Menu(self.__MENU_LAYOUT) ],
            [ sg.Column(screen_layout, expand_x = True, expand_y = True) ],
        ]

    def __open_nes_file_hint(self, values) -> None:
        sg.popup("Please select a nes file!")

    def __switch_to_english_input(self):
        user32 = ctypes.WinDLL('user32', use_last_error = True)
        user32.LoadKeyboardLayoutW("00000409", 1)

    def _after_open(self) -> None:
        # bind Graph (key = "SCREEN") with pygame window
        os.environ['SDL_WINDOWID'] = str(self._window['-SCREEN-'].TKCanvas.winfo_id())

        # Minimal pygame initialization
        pygame.display.quit()  # Quit any existing display
        pygame.display.init()  # Reinitialize display
        
        # Start with a default size, will be updated in the game loop
        self.__game_screen = pygame.display.set_mode((640, 480), pygame.RESIZABLE)

        # Initialize pygame font and event handling
        pygame.font.init()
        
        self.__switch_to_english_input()
        # Prepare audio output (will be created when a ROM is opened)
        self._audio = None
        
    def _before_exit(self, values = None) -> None:
        self.__stop.set()
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
        
        # run .nes file
        self.__console = Console(file_path)
        self.__console.power_up()

        # Initialize audio output for this run; use bus.apu if available.
        try:
            self._audio = AudioOutput(sample_rate=44100, chunk_size=1024, max_queue=16)
            self._audio.play_test_tone(frequency=440.0, duration=0.4, volume=0.4)
        except Exception:
            self._audio = None

        # update emulator window title
        filename_with_extension = os.path.basename(file_path)
        self.filename, extension = os.path.splitext(filename_with_extension)
        self._window.TKroot.title('NES: ' + self.filename)

        # bind events about console
        self._events["CPU"] = CPUDebugWindow(self.__console).open
        self._events["PPU"] = PPUDebugWindow(self.__console).open
        self._events["Disassembler"] = DisassemblerWindow(self.__console).open
        self._events["NES File Viewer"] = NesFileWindow(self.__console).open

        self._events["Save"] = self.__save
        self._events["Load"] = self.__load  

        return True
    
    def __save(self, values):
        if not os.path.exists("./saves"):
            os.mkdir("./saves")
        archive_name = "./saves/{filename}-{id}.sav".format(filename = self.filename, id = int(time.time()))
        self.__console.save_state(archive_name)

    def __load(self, values):
        archive_path = sg.popup_get_file('File to open', file_types = (("NES Archives", "*.sav"),), no_window = True)
        if archive_path is None or archive_path == '':
            sg.popup("Invalid .sav file path!")
            return
        self.__console.load_state(archive_path)

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
        
        # Wait a bit for the game to initialize and enable rendering
        frames_waited = 0
        MAX_WAIT_FRAMES = 300  # Wait up to 5 seconds at 60fps
        
        last_canvas_width, last_canvas_height = 640, 480
        
        while not self.__stop.is_set():              
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
            
            # Get keyboard state using cross-platform method
            control_inputs = [
                get_key_state(keyboard['SELECT']),
                get_key_state(keyboard['START']),
                get_key_state(keyboard['B']),
                get_key_state(keyboard['A']),
                get_key_state(keyboard['UP']),
                get_key_state(keyboard['DOWN']),
                get_key_state(keyboard['LEFT']),
                get_key_state(keyboard['RIGHT'])
            ]
            
            self.__console.control(control_inputs)
            
            self.__console.run()
            
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

            # Generate and enqueue audio for this frame from the bus APU
            try:
                if getattr(self, '_audio', None) is not None:
                    apu = getattr(self.__console.bus, 'apu', None)
                    if apu is not None:
                        samples = apu.drain_samples()
                        if isinstance(samples, np.ndarray) and samples.dtype == np.int16 and samples.size > 0:
                            self._audio.enqueue(samples)
            except Exception:
                pass
            clock.tick(60)  # Limit to 60 FPS for smooth gameplay
            frames_waited += 1

    def __run(self, values) -> None:
        success = self.__open_file()
        if not success:
            return
        async_runnable = Thread(target = self.__run_file)
        async_runnable.start()

    def __capture_screenshot(self, values) -> None:
        image_data = np.array(self.__console.bus.ppu.screen())

        if not os.path.exists("./screenshots"):
            os.mkdir("./screenshots")
        screenshot_path = "./screenshots/{}.jpg".format(str(int(time.time())))

        image = Image.fromarray(image_data)
        image.save(screenshot_path)

    def __reset(self, values) -> None:
        self.__console.reset()
    
    def __show_about(self, values) -> None:
        sg.popup(f'Nes Emulator\nVersion: {VERSION}\nAuthor: {AUTHOR}\n')
    
    def __open_keymap(self, values) -> None:
        # Open keyboard settings in a separate thread to avoid blocking main window
        keymap_window = KeyboardSettingWindow()
        keymap_window.open()

if __name__ == "__main__":
    emulator_window = EmulatorWindow()
    emulator_window.open()