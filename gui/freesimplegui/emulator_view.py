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

    __SIZE = ( 256 + 20, 240 + 20 )

    __RESIZABLE = True

    __FINALIZE = True
     
    def __init__(self):
        super().__init__(title = self.__TITLE,
                         size = self.__SIZE,
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
        self._events["Keymap"] = KeyboardSettingWindow().open

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
                         canvas_size = (256, 240), 
                         graph_bottom_left = (0, 0), 
                         graph_top_right = (256, 240), 
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
        os.environ['SDL_VIDEODRIVER'] = 'windib'
        os.environ['SDL_WINDOWID'] = str(self._window['-SCREEN-'].TKCanvas.winfo_id())

        # init pygame settings
        self.__game_screen = pygame.display.set_mode((256, 240), pygame.RESIZABLE)
        # self.__game_clock = pygame.time.Clock()
        # self.__fps = 60

        pygame.display.init()

        self.__switch_to_english_input()
        
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

    def __resize(self, original_image: np.ndarray) -> np.ndarray:
        with self.__lock:
            for event in pygame.event.get():
                if event.type == pygame.VIDEORESIZE:
                    self.cur_w, self.cur_h = event.w, event.h
                    self.__game_screen = pygame.display.set_mode((event.w, event.h), pygame.RESIZABLE)
            resized_image = cv2.resize(original_image, (self.cur_h, self.cur_w))
        return resized_image   
    
    def __run_file(self) -> None:
        while not self.__stop.is_set():              
            pressed = pygame.key.get_pressed()
            with open(KeyboardSettingWindow.keyboard_setting_path) as keyboard_setting:
                keyboard = json.load(keyboard_setting)
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
            resized_image = self.__resize(original_image)
            surf = pygame.surfarray.make_surface(resized_image)
            self.__game_screen.blit(surf, (0, 0))
            pygame.display.flip()

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
