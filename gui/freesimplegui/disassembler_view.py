import FreeSimpleGUI as sg
from gui.freesimplegui.base_view import BaseView


class DisassemblerWindow(BaseView):
    __TITLE = "Disassembler"
    
    def __init__(self, console):
        super().__init__(title = self.__TITLE)
        self.__console = console
        self._events["Disassemble"] = self.__disassemble

    def _layout(self):
        return [
            [
                sg.Text("start address: "), 
                sg.InputText(default_text = "0x0000", key = "-START_ADDR-", size = ( 8, 1 )), 
                sg.Text("end address: "), 
                sg.InputText(default_text = "0xFFFF", key = "-END_ADDR-", size = ( 8, 1 )),
                sg.Button("Disassemble"),
            ],
            [
                sg.Multiline(key = "HEX", 
                             size = ( 55, 10 ), 
                             background_color = 'BLUE', 
                             text_color = 'WHITE', 
                             disabled = True)
            ]
        ]

    def __disassemble(self, values) -> None:
        start_addr = int(values["-START_ADDR-"], 16)
        end_addr = int(values["-END_ADDR-"], 16)
        self._window['HEX'].Update(self.__console.cpu_debugger.ram(start_addr, end_addr))
