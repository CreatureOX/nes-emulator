import PySimpleGUI as gui
import pygame
import os
from numpy import uint16, uint8, swapaxes
from threading import Thread, Event
from PIL import Image, ImageTk
import pyximport; pyximport.install()

from console import Console


class Emulator:
    menu_def = [
        ['File', ['Open File','Exit']],
        ['Debug', ['CPU','PPU','Hex Viewer']],
        ['Help', ['About',]],
    ]

    cpu_debug_layout = [
        [gui.Button('Clock'),gui.Button('Frame'),gui.Button('Reset'),gui.Button('Run'),],
        [
            gui.Text("STATUS: ",size=(8,1),text_color='WHITE'),
            gui.Text("N",key="N",size=(1,1),text_color='WHITE'),
            gui.Text("V",key="V",size=(1,1),text_color='WHITE'),
            gui.Text("B",key="B",size=(1,1),text_color='WHITE'),
            gui.Text("D",key="D",size=(1,1),text_color='WHITE'),
            gui.Text("I",key="I",size=(1,1),text_color='WHITE'),
            gui.Text("Z",key="Z",size=(1,1),text_color='WHITE'),
        ],
        [
            gui.Text("PC: $0x0000",key="PC",size=(11,1)),
            gui.Text("A: $0x00",key="A",size=(8,1)),
            gui.Text("X: $0x00",key="X",size=(8,1)),
            gui.Text("Y: $0x00",key="Y",size=(8,1)),
            gui.Text("SP: $0x0000",key="SP",size=(10,1)),
        ],
        [gui.Multiline(key="READABLE", size=(50,10), background_color='BLUE', disabled=True)],
    ]

    ppu_debug_layout = [
        [gui.Graph(key="PATTERN_0", canvas_size=(128,128), graph_bottom_left=(0,0), graph_top_right=(128,128))],
        [gui.Graph(key="PATTERN_1", canvas_size=(128,128), graph_bottom_left=(0,0), graph_top_right=(128,128))],
    ]
    
    hex_viewer_layout = [
        [
            gui.Text("start address: "), gui.InputText(default_text="0x0000", key="START ADDR", size=(8,1)), 
            gui.Text("end address: "), gui.InputText(default_text="0xFFFF", key="END ADDR", size=(8,1)),
            gui.Button("Disassemble"),
        ],
        [gui.Multiline(key="HEX", size=(50,10), background_color='BLUE', text_color='WHITE', disabled=True)]
    ]
    
    screen_layout = [
        [gui.Graph(key="SCREEN", canvas_size=(256,240), graph_bottom_left=(0,0), graph_top_right=(256,240), background_color='BLACK')]
    ]

    layout = [
        [gui.Menu(menu_def)],
        [gui.Column(screen_layout)],
    ]

    console: Console

    def __init__(self) -> None:
        self.window = gui.Window('NES Emulator', self.layout, size = (256, 240), resizable = True).Finalize()
        os.environ['SDL_WINDOWID'] = str(self.window['SCREEN'].TKCanvas.winfo_id())
        os.environ['SDL_VIDEODRIVER'] = 'windib'
        self.gameScreen = pygame.display.set_mode((256, 240))
        self.gameClock = pygame.time.Clock()
        self.fps = 60
        pygame.display.init()

    def openCPUDebug(self) -> bool:
        cpu_debug_window = gui.Window('CPU DEBUG', self.cpu_debug_layout)
        while True:
            event, values = cpu_debug_window.read()
            if event in (None, 'Exit'):
                break
            else:
                self.drawCPUStatus(cpu_debug_window)
                self.drawCPURegisters(cpu_debug_window)
        cpu_debug_window.close()
        return True

    def openPPUDebug(self) -> bool:
        ppu_debug_window = gui.Window('PPU DEBUG', self.ppu_debug_layout)
        while True:
            event, values = ppu_debug_window.read()
            if event in (None, 'Exit'):
                break
            else:
                self.drawPatternTable(ppu_debug_window)
        return True

    def openHexViewer(self) -> bool:
        if self.console is None:
            gui.popup("Please load nes file!")
            return False
        hex_viewer_window = gui.Window("Hex Viewer", self.hex_viewer_layout)
        while True:
            event, values = hex_viewer_window.read()
            if event in (None, 'Exit'):
                break
            else:
                self.drawRAM(hex_viewer_window, int(values["START ADDR"], 16), int(values["END ADDR"], 16))
        hex_viewer_window.close()
        return True
            
    def drawCPUStatus(self, window) -> None:
        status_info = self.console.cpu_status_info() 
        window["N"].Update(text_color='RED' if status_info["N"] else 'WHITE')
        window["V"].Update(text_color='RED' if status_info["V"] else 'WHITE')
        window["B"].Update(text_color='RED' if status_info["B"] else 'WHITE')
        window["D"].Update(text_color='RED' if status_info["D"] else 'WHITE')
        window["I"].Update(text_color='RED' if status_info["I"] else 'WHITE')
        window["Z"].Update(text_color='RED' if status_info["Z"] else 'WHITE')

    def drawCPURegisters(self, window) -> None:
        registers_info = self.console.cpu_registers_info()
        window["PC"].Update("PC: ${PC:04X}".format(PC=registers_info["PC"]))
        window["A"].Update("A: ${a:02X}".format(a=registers_info["A"]))
        window["X"].Update("X: ${x:02X}".format(x=registers_info["X"]))
        window["Y"].Update("Y: ${y:02X}".format(y=registers_info["Y"]))
        window["SP"].Update("SP: ${stkp:04X}".format(stkp=registers_info["SP"]))        

    def drawCode(self, window, delta: int = 10) -> None:
        start, end = max(self.console.bus.cpu.pc- delta, 0x0000), self.console.bus.cpu.pc + delta
        asm = self.console.cpu_code_readable(start, end)
        window['READABLE'].Update("")
        for addr, inst in asm.items():
            window['READABLE'].print(inst, text_color="CYAN" if addr == self.console.cpu_pc() else 'WHITE') 

    def drawPatternTable(self, window) -> None:
        patternTable0 = ImageTk.PhotoImage(image=Image.fromarray(self.console.ppu_pattern_table(0,0)))
        window['PATTERN_0'].update(data=patternTable0)
        patternTable1 = ImageTk.PhotoImage(image=Image.fromarray(self.console.ppu_pattern_table(1,0)))
        window['PATTERN_1'].update(data=patternTable1) 

    def drawRAM(self, window, start_addr: uint16, end_addr: uint16) -> None:
        window['HEX'].Update(self.console.cpu_ram(start=start_addr, end=end_addr))

    def openFile(self) -> bool:
        filename = gui.popup_get_file('file to open', file_types=(("NES Files","*.nes"),), no_window=True)
        if filename is None or filename == '':
            return False
        self.console = Console(filename)
        self.console.reset()
        self.window.TKroot.title('NES Emulator ' + filename)
        return True

    def clock(self) -> bool:
        if self.console is None:
            gui.popup("Please load nes file!")
            return False
        self.console.clock() 
        surf = pygame.surfarray.make_surface(self.console.bus.ppu.getScreen())
        self.gameScreen.blit(surf, (0,0))
        pygame.display.flip()
        return True

    def frame(self) -> bool:
        if self.console is None:
            gui.popup("Please load nes file!")
            return False
        self.console.frame()
        n = swapaxes(self.console.bus.ppu.getScreen(), 0, 1)
        surf = pygame.surfarray.make_surface(n)
        self.gameScreen.blit(surf, (0,0))
        pygame.display.flip()
        return True

    def run(self, stop: Event) -> bool:
        while not stop.is_set():
            pressed = pygame.key.get_pressed()
            self.console.control([
                pressed[pygame.K_x],pressed[pygame.K_z],pressed[pygame.K_a],pressed[pygame.K_s],
                pressed[pygame.K_UP],pressed[pygame.K_DOWN],pressed[pygame.K_LEFT],pressed[pygame.K_RIGHT]
            ]) 
            self.gameClock.tick(self.fps)
            self.console.run()
            n = swapaxes(self.console.bus.ppu.getScreen(), 0, 1)
            surf = pygame.surfarray.make_surface(n)
            #surf = pygame.surfarray.make_surface(self.bus.ppu.getScreen())
            self.gameScreen.blit(surf, (0,0))
            pygame.display.flip()
        return True

    def reset(self) -> bool:
        if self.console is None:
            gui.popup("Please load nes file!")
            return False
        self.console.reset()
        return True   

    def emulate(self) -> None:
        stop = Event()
        while True:
            event, values = self.window.read()
            success = True
            if event in (None, 'Exit'):
                stop.set()
                break
            elif event == 'Open File':
                success = self.openFile()
                asyncRun = Thread(target=self.run, args=(stop,))
                asyncRun.start()
            elif event == 'Clock':
                success = self.clock()
            elif event == 'Frame':
                success = self.frame()
            elif event == 'CPU':
                success = self.openCPUDebug()
            elif event == 'PPU':
                success = self.openPPUDebug()
            elif event == 'Hex Viewer':
                success = self.openHexViewer()
            elif event == 'Reset':
                success = self.reset()
            elif event == 'About':
                gui.popup('Nes Emulator\nVersion: 0\nAuthor: CreatureOX\n')  
            if not success:
                continue      
        self.window.close()

emu = Emulator()
emu.emulate()