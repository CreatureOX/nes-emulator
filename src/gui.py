import PySimpleGUI as gui
import pygame
import os
import numpy as np
from threading import Thread, Event, Lock
from PIL import Image, ImageTk
import cv2
import pyximport; pyximport.install()

from console import Console


class Emulator:
    menu_def = [
        ['File', ['Open File','Exit']],
        ['Debug', ['CPU','PPU','Hex Viewer']],
        ['Help', ['About',]],
    ]
    
    screen_layout = [
        [gui.Graph(key="SCREEN", canvas_size=(256,240), graph_bottom_left=(0,0), graph_top_right=(256,240), background_color='BLACK', expand_x=True, expand_y=True)]
    ]

    layout = [
        [gui.Menu(menu_def)],
        [gui.Column(screen_layout, expand_x=True, expand_y=True)],
    ]

    console: Console = None

    def __init__(self) -> None:
        self.window = gui.Window('NES Emulator', self.layout, size = (256+20, 240+20), resizable = True, finalize=True)
        os.environ['SDL_WINDOWID'] = str(self.window['SCREEN'].TKCanvas.winfo_id())
        os.environ['SDL_VIDEODRIVER'] = 'windib'
        self.gameScreen = pygame.display.set_mode((256, 240), pygame.RESIZABLE)
        self.gameClock = pygame.time.Clock()
        self.fps = 60
        pygame.display.init()
        self.lock = Lock()

    def openCPUDebug(self) -> bool:
        def cpu_debug_layout():
            return [
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
        cpu_debug_window = gui.Window('CPU DEBUG', cpu_debug_layout())
        while True:
            event, values = cpu_debug_window.read(timeout=0)
            if event in (None, 'Exit'):
                break
            else:
                self.drawCPUStatus(cpu_debug_window)
                self.drawCPURegisters(cpu_debug_window)
                self.drawCode(cpu_debug_window)
        cpu_debug_window.close()
        return True

    def openPPUDebug(self) -> bool:
        def ppu_debug_layout():
            return [
                [gui.Image(key="PATTERN_0", size=(128,128)), gui.Image(key="PATTERN_1", size=(128,128))],
                [gui.Image(key="PALETTE", size=(4*10,16*10))],
            ]            
        ppu_debug_window = gui.Window('PPU DEBUG', ppu_debug_layout())
        while True:
            event, values = ppu_debug_window.read(timeout=0)
            if event in (None, 'Exit'):
                break
            else:
                self.drawPatternTable(ppu_debug_window)
                self.drawPalette(ppu_debug_window, 10)
        ppu_debug_window.close()
        return True

    def openHexViewer(self) -> bool:
        def hex_viewer_layout():
            return [
                [
                    gui.Text("start address: "), gui.InputText(default_text="0x0000", key="START ADDR", size=(8,1)), 
                    gui.Text("end address: "), gui.InputText(default_text="0xFFFF", key="END ADDR", size=(8,1)),
                    gui.Button("Disassemble"),
                ],
                [gui.Multiline(key="HEX", size=(55,10), background_color='BLUE', text_color='WHITE', disabled=True)]
            ]
        hex_viewer_window = gui.Window("Hex Viewer", hex_viewer_layout())
        while True:
            event, values = hex_viewer_window.read(timeout=1000)
            if event in (None, 'Exit'):
                break
            else:
                self.drawRAM(hex_viewer_window, int(values["START ADDR"], 16), int(values["END ADDR"], 16))
        hex_viewer_window.close()
        return True
            
    def drawCPUStatus(self, window) -> None:
        if not self.console:
            return
        status_info = self.console.cpu_status_info() 
        window["N"].Update(text_color='RED' if status_info["N"] else 'WHITE')
        window["V"].Update(text_color='RED' if status_info["V"] else 'WHITE')
        window["B"].Update(text_color='RED' if status_info["B"] else 'WHITE')
        window["D"].Update(text_color='RED' if status_info["D"] else 'WHITE')
        window["I"].Update(text_color='RED' if status_info["I"] else 'WHITE')
        window["Z"].Update(text_color='RED' if status_info["Z"] else 'WHITE')

    def drawCPURegisters(self, window) -> None:
        if not self.console:
            return
        registers_info = self.console.cpu_registers_info()
        window["PC"].Update("PC: ${PC:04X}".format(PC=registers_info["PC"]))
        window["A"].Update("A: ${a:02X}".format(a=registers_info["A"]))
        window["X"].Update("X: ${x:02X}".format(x=registers_info["X"]))
        window["Y"].Update("Y: ${y:02X}".format(y=registers_info["Y"]))
        window["SP"].Update("SP: ${stkp:04X}".format(stkp=registers_info["SP"]))        

    def drawCode(self, window, delta: int = 10) -> None:
        if not self.console:
            return
        start, end = max(self.console.cpu_pc() - delta, 0x0000), self.console.cpu_pc() + delta
        asm = self.console.cpu_code_readable(start, end)
        window['READABLE'].Update("")
        for addr, inst in asm.items():
            window['READABLE'].print(inst, text_color="CYAN" if addr == self.console.cpu_pc() else 'WHITE') 

    def drawPatternTable(self, window) -> None:
        if not self.console:
            return
        patternTable0 = ImageTk.PhotoImage(image=Image.fromarray(np.asarray(self.console.ppu_pattern_table(0))))
        window['PATTERN_0'].Update(data=patternTable0)
        patternTable1 = ImageTk.PhotoImage(image=Image.fromarray(np.asarray(self.console.ppu_pattern_table(1))))
        window['PATTERN_1'].Update(data=patternTable1) 
    
    def drawPalette(self, window, ratio: int = 1) -> None:
        if not self.console:
            return
        palette = Image.fromarray(np.asarray(self.console.ppu_palette()))
        resize_palette = palette.resize((16*ratio, 4*ratio))
        image = ImageTk.PhotoImage(image=resize_palette)
        window['PALETTE'].Update(data=image)

    def drawRAM(self, window, start_addr: np.uint16, end_addr: np.uint16) -> None:
        if not self.console:
            return
        window['HEX'].Update(self.console.cpu_ram(start_addr, end_addr))

    def openFile(self) -> bool:
        filename = gui.popup_get_file('file to open', file_types=(("NES Files","*.nes"),), no_window=True)
        if filename is None or filename == '':
            return False
        self.console = Console(filename)
        self.console.reset()
        self.window.TKroot.title('NES Emulator ' + filename)
        return True
    
    def resize(self, originalImage: np.ndarray) -> np.ndarray:
        with self.lock:
            for event in pygame.event.get():
                if event.type == pygame.VIDEORESIZE:
                    self.cur_w, self.cur_h = event.w, event.h
                    self.gameScreen = pygame.display.set_mode((event.w, event.h), pygame.RESIZABLE)
            resizedImage = cv2.resize(originalImage, (self.cur_h, self.cur_w))
        return resizedImage        

    def run(self, stop: Event) -> bool:
        while not stop.is_set():              
            pressed = pygame.key.get_pressed()
            self.console.control([
                pressed[pygame.K_x],pressed[pygame.K_z],pressed[pygame.K_a],pressed[pygame.K_s],
                pressed[pygame.K_UP],pressed[pygame.K_DOWN],pressed[pygame.K_LEFT],pressed[pygame.K_RIGHT]
            ]) 
            self.gameClock.tick(self.fps)
            self.console.run()
            originalImage = np.swapaxes(self.console.bus.ppu.getScreen(), 0, 1)
            resizedImage = self.resize(originalImage)
            surf = pygame.surfarray.make_surface(resizedImage)
            self.gameScreen.blit(surf, (0,0))
            pygame.display.flip()
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
            elif event == 'CPU':
                success = self.openCPUDebug()
            elif event == 'PPU':
                success = self.openPPUDebug()
            elif event == 'Hex Viewer':
                success = self.openHexViewer()
            elif event == 'About':
                gui.popup('Nes Emulator\nVersion: 0\nAuthor: CreatureOX\n')           
            if not success:
                continue      
        self.window.close()

emu = Emulator()
emu.emulate()