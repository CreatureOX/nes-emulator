import PySimpleGUI as sg
from gui.pysimplegui.base_view import BaseView


class NesFileWindow(BaseView):
    __TITLE = "NES File Viewer"

    __TIMEOUT = 0

    def __init__(self, console):
        super().__init__(title = self.__TITLE,
                         timeout = self.__TIMEOUT)
        self.__console = console
        self._events["__TIMEOUT__"] = self.__update_cartridge_view
    
    def _layout(self):
        return [
            [
                sg.Text("PRG ROM: "), sg.Text(key = "-PRG_ROM_size-", size = (8, 1)),
                sg.Text("PRG RAM: "), sg.Text(key = "-PRG_RAM_size-", size = (8, 1)), 
            ],
            [
                sg.Text("CHR ROM: "), sg.Text(key = "-CHR_ROM_size-", size = (8, 1)),
                sg.Text("CHR RAM: "), sg.Text(key = "-CHR_RAM_size-", size = (8, 1)), 
            ],
            [
                sg.Text("Mapper No: "), sg.Text(key = "-mapper_no-", size = (8, 1)),
            ]
        ]

    def __update_cartridge_view(self, values) -> None:
        view_info = self.__console.cartridge_debugger.view()
        
        self._window["-PRG_ROM_size-"].Update(view_info["PRG ROM"])
        self._window["-PRG_RAM_size-"].Update(view_info["PRG RAM"])
        self._window["-CHR_ROM_size-"].Update(view_info["CHR ROM"])
        self._window["-CHR_RAM_size-"].Update(view_info["CHR RAM"])
        self._window["-mapper_no-"].Update(view_info["mapper no"]) 
