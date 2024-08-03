import PySimpleGUI as sg
from gui.pysimplegui.base_view import BaseView
from PIL import Image, ImageTk
import numpy as np


class PPUDebugWindow(BaseView):
    __TITLE = "PPU DEBUG"

    __TIMEOUT = 0

    def __init__(self, console):
        super().__init__(title = self.__TITLE,
                         timeout = self.__TIMEOUT)
        self.__console = console
        self._events["__TIMEOUT__"] = self.__update_PPU_debugger

    def _layout(self):
        return [
            [
                sg.Image(key = "-PATTERN_0-", size = ( 128, 128 )), 
                sg.Image(key = "-PATTERN_1-", size = ( 128, 128 ))
            ],
            [ 
                sg.Image(key = "-PALETTE-", size = ( 4 * 10, 16 * 10 )) 
            ],
        ]

    def __update_PPU_debugger(self, values) -> None:
        self.__update_pattern_tables()
        self.__update_palette(ratio = 10)

    def __update_pattern_tables(self) -> None:
        # numpy array to image
        pattern_table0_image = Image.fromarray(np.asarray(self.__console.ppu_debugger.pattern_table(0, 0)))
        pattern_table1_image = Image.fromarray(np.asarray(self.__console.ppu_debugger.pattern_table(1, 0)))

        # image to photo
        pattern_table0 = ImageTk.PhotoImage(image = pattern_table0_image)
        pattern_table1 = ImageTk.PhotoImage(image = pattern_table1_image)

        # update window by photo
        self._window['-PATTERN_0-'].Update(data = pattern_table0)
        self._window['-PATTERN_1-'].Update(data = pattern_table1) 

    def __update_palette(self, ratio: int = 1) -> None:
        palette_image = Image.fromarray(np.asarray(self.__console.ppu_debugger.palette()))

        # resize image
        resized_palette_image = palette_image.resize(( 16 * ratio, 4 * ratio ))

        # update window by photo
        palette = ImageTk.PhotoImage(image = resized_palette_image)
        self._window['-PALETTE-'].Update(data = palette)
