import FreeSimpleGUI as sg
from gui.freesimplegui.base_view import BaseView
from gui.freesimplegui.keyboard_setting_view import KeyboardSettingWindow
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
import platform

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

    # NES resolution
    NES_WIDTH = 256
    NES_HEIGHT = 240
    ASPECT_RATIO = NES_WIDTH / NES_HEIGHT
    
    # NES Emulator window size
    __SIZE = (NES_WIDTH + 20, NES_HEIGHT + 20)

    __RESIZABLE = True
    __FINALIZE = True
     
    def __init__(self):
        super().__init__(title = self.__TITLE,
                         size = self.__SIZE,
                         resizable = self.__RESIZABLE,
                         finalize = self.__FINALIZE)
        self.__lock = Lock()
        self.__stop = Event()
        self.__system = platform.system()
        self.__height_scale = 1.0
        self.__graph_width = self.NES_WIDTH
        self.__graph_height = self.NES_HEIGHT

        # File Tab
        self._events["Open"] = self.__run
        self._events["Reset"] = self.__reset
        self._events["Screenshot"] = self.__capture_screenshot
        self._events["Save"] = self.__open_nes_file_hint
        self._events["Load"] = self.__open_nes_file_hint

        # Config Tab
        self._events["Keymap"] = KeyboardSettingWindow().open

        # DEBUG Tab
        self._events["CPU"] = self.__open_nes_file_hint
        self._events["PPU"] = self.__open_nes_file_hint
        self._events["Disassembler"] = self.__open_nes_file_hint
        self._events["NES File Viewer"] = self.__open_nes_file_hint    

        # Help Tab
        self._events["About"] = self.__show_about

        self._last_gui_focus_time = 0
        self._focus_protect_seconds = 1.0

    def _layout(self):
        screen_layout = [
            [
                sg.Graph(key = "-SCREEN-", 
                         canvas_size = (self.NES_WIDTH, self.NES_HEIGHT), 
                         graph_bottom_left = (0, 0), 
                         graph_top_right = (self.NES_WIDTH, self.NES_HEIGHT), 
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
        if self.__system != 'Windows':
            return
        user32 = ctypes.WinDLL('user32', use_last_error = True)
        user32.LoadKeyboardLayoutW("00000409", 1)

    def _after_open(self) -> None:
        # bind Graph (key = "SCREEN") with pygame window, auto resized
        self._window['-SCREEN-'].bind('<Configure>', 'Configure')
        self._events["-SCREEN-Configure"] = self.__on_graph_resize
        
        if self.__system == 'Windows':
            os.environ['SDL_VIDEODRIVER'] = 'windows'
            os.environ['SDL_WINDOWID'] = str(self._window['-SCREEN-'].TKCanvas.winfo_id())
        elif self.__system == 'Darwin':
            os.environ['SDL_VIDEODRIVER'] = 'cocoa'

        # set pygame environment variables
        pygame.display.init()
        self.__game_screen = pygame.display.set_mode((self.NES_WIDTH, self.NES_HEIGHT), pygame.RESIZABLE)
        pygame.display.set_caption('NES Emulator')

        # self.__switch_to_english_input()
        
    def __on_graph_resize(self, event):
        graph_height = self._window['-SCREEN-'].TKCanvas.winfo_height()
        self.__height_scale = graph_height / self.NES_HEIGHT
        scaled_width = int(self.NES_WIDTH * self.__height_scale)

        self.__graph_width = scaled_width
        self.__graph_height = graph_height
        self._window['-SCREEN-'].change_coordinates(
            graph_bottom_left=(0, 0),
            graph_top_right=(scaled_width, graph_height)
        )
        
        self.__update_pygame_window()
        return True

    def _before_exit(self, values = None) -> None:
        self.__stop.set()

    def __open_file(self) -> bool:
        file_path = sg.popup_get_file('File to open', file_types = (("NES Files", "*.nes"),), no_window = True)
        if file_path is None or file_path == '':
            sg.popup("Invalid .nes file path!")
            return False
        
        # run .nes file
        self.__console = Console(file_path)
        self.__console.power_up()

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

    def __update_pygame_window(self):
        # get -SCREEN- current resolution
        try:
            graph_width = self._window['-SCREEN-'].TKCanvas.winfo_width()
            graph_height = self._window['-SCREEN-'].TKCanvas.winfo_height()
        except Exception as e:
            return
        if graph_width <= 0 or graph_height <= 0:
            return
        
        # calculate the position
        x = (graph_width - self.__graph_width) / 2
        y = 0
        
        # update pygame window position and size
        if self.__system == 'Windows':
            pygame_window = pygame.display.get_wm_info()['window']
            ctypes.windll.user32.MoveWindow(
                pygame_window, 
                int(x), 
                int(y), 
                self.__graph_width, 
                self.__graph_height, 
                True
            )
    
    def __run_file(self) -> None:
        self.__on_graph_resize(None)

        pygame_window = None
        if self.__system == 'Windows':
            try:
                pygame_window = pygame.display.get_wm_info()['window']
            except Exception:
                pygame_window = None

        # 启动时切换一次焦点
        if self.__system == 'Windows' and pygame_window:
            ctypes.windll.user32.SetForegroundWindow(pygame_window)

        while not self.__stop.is_set():
            self._window.TKroot.update()
            gui_event, gui_values = self._window.read(timeout=0)
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.__stop.set()

            # 不再每帧切换焦点
            # ...其余代码不变...

            with open(KeyboardSettingWindow.keyboard_setting_path) as keyboard_setting:
                keyboard = json.load(keyboard_setting)
            pressed = pygame.key.get_pressed()
            self.__console.control([
                pressed[keyboard['SELECT']],
                pressed[keyboard['START']],
                pressed[keyboard['B']],
                pressed[keyboard['A']],
                pressed[keyboard['UP']],
                pressed[keyboard['DOWN']],
                pressed[keyboard['LEFT']],
                pressed[keyboard['RIGHT']]
            ]) 
            self.__console.run()
            original_image = np.swapaxes(self.__console.bus.ppu.screen(), 0, 1)
            surf = pygame.surfarray.make_surface(original_image)

            target_size = self.__game_screen.get_size()
            scaled_surf = pygame.transform.smoothscale(surf, target_size)
            self.__game_screen.blit(scaled_surf, (0, 0))

            pygame.display.flip()
            self.__update_pygame_window()

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

if __name__ == "__main__":
    emulator_window = EmulatorWindow()
    emulator_window.open()