import PySimpleGUI as sg
from gui.pysimplegui.base_view import BaseView


class CPUDebugWindow(BaseView):
    __TITLE = "CPU DEBUG"
    
    __TIMEOUT = 0
    
    def __init__(self, console):
        super().__init__(title = self.__TITLE,
                         timeout = self.__TIMEOUT)
        self.__console = console
        self._events["__TIMEOUT__"] = self.__update_CPU_debugger

    def _layout(self):
        return [
            [
                sg.Text("STATUS: ",       size = (8, 1), text_color = 'WHITE'),
                sg.Text("N", key = "-N-", size = (1, 1), text_color = 'WHITE'),
                sg.Text("V", key = "-V-", size = (1, 1), text_color = 'WHITE'),
                sg.Text("B", key = "-B-", size = (1, 1), text_color = 'WHITE'),
                sg.Text("D", key = "-D-", size = (1, 1), text_color = 'WHITE'),
                sg.Text("I", key = "-I-", size = (1, 1), text_color = 'WHITE'),
                sg.Text("Z", key = "-Z-", size = (1, 1), text_color = 'WHITE'),
            ],
            [
                sg.Text("PC: $0x0000", key = "-PC-", size = (11, 1)),
                sg.Text("A: $0x00",    key = "-A-",  size = (8, 1)),
                sg.Text("X: $0x00",    key = "-X-",  size = (8, 1)),
                sg.Text("Y: $0x00",    key = "-Y-",  size = (8, 1)),
                sg.Text("SP: $0x0000", key = "-SP-", size = (10, 1)),
            ],
            [
                sg.Multiline(key = "-READABLE-", size = (50, 10), background_color = 'BLUE', disabled = True)
            ],
        ]

    def __update_CPU_debugger(self, values) -> None:
        self.__update_CPU_status()
        self.__update_CPU_registers()
        self.__update_running_code_context()

    def __update_CPU_status(self) -> None:
        status_info = self.__console.cpu_debugger.status()

        self._window["-N-"].Update(text_color = 'RED' if status_info["N"] else 'WHITE')
        self._window["-V-"].Update(text_color = 'RED' if status_info["V"] else 'WHITE')
        self._window["-B-"].Update(text_color = 'RED' if status_info["B"] else 'WHITE')
        self._window["-D-"].Update(text_color = 'RED' if status_info["D"] else 'WHITE')
        self._window["-I-"].Update(text_color = 'RED' if status_info["I"] else 'WHITE')
        self._window["-Z-"].Update(text_color = 'RED' if status_info["Z"] else 'WHITE')

    def __update_CPU_registers(self) -> None:
        registers_info = self.__console.cpu_debugger.registers()

        self._window["-PC-"].Update("PC: ${PC:04X}".format(PC = registers_info["PC"]))
        self._window["-A-"].Update("A: ${A:02X}".format(A = registers_info["A"]))
        self._window["-X-"].Update("X: ${X:02X}".format(X = registers_info["X"]))
        self._window["-Y-"].Update("Y: ${Y:02X}".format(Y = registers_info["Y"]))
        self._window["-SP-"].Update("SP: ${SP:04X}".format(SP = registers_info["SP"]))     

    def __update_running_code_context(self, delta: int = 10) -> None:
        current_addr = self.__console.cpu_debugger.PC()
        start_addr = max(current_addr - delta, 0x0000)
        end_addr = current_addr + delta
        
        # disassemble code
        asm = self.__console.cpu_debugger.to_asm(start_addr, end_addr)

        # refresh READABLE
        self._window['-READABLE-'].Update("")
        for addr, inst in asm.items():
            self._window['-READABLE-'].print(inst, text_color = "CYAN" if addr == self.__console.cpu_debugger.PC() else 'WHITE')
