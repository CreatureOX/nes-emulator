import PySimpleGUI as gui
import pygame
import os
from numpy import uint16, uint8, swapaxes
from threading import Thread, Event
from PIL import Image, ImageTk
import pyximport; pyximport.install()

from console import Console
from cpu import C, Z, I, D, B, U, V, N


class Emulator:
    menu_def = [
        ['File', ['Open File','Exit']],
        ['Debug', ['Hex Viewer','PatternTable0','PatternTable1']],
        ['Help', ['About',]],
    ]
    
    screen_layout = [[gui.Graph(key="SCREEN", canvas_size=(256,240), graph_bottom_left=(0,0), graph_top_right=(256,240), background_color='BLACK')]]
    utils_layout = [
        [gui.Button('Clock'),gui.Button('Frame'),gui.Button('Reset'),gui.Button('Run'),],
        [
            gui.Text("STATUS: ",size=(8,1),text_color='WHITE'),
            gui.Text("N",key="N",size=(1,1),text_color='WHITE'),
            gui.Text("V",key="V",size=(1,1),text_color='WHITE'),
            gui.Text("-",key="-",size=(1,1),text_color='WHITE'),
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
        [gui.Multiline(key="READABLE", size=(128,10), background_color='BLUE', disabled=True)],
        [
            gui.Image(key="P0", size=(128,128), background_color='BLACK'),
            gui.Image(key="P1", size=(128,128), background_color='BLACK')
        ]
    ]

    layout = [
        [gui.Menu(menu_def)],
        [
            gui.Column(screen_layout,size=(512,500)), 
            gui.Column(utils_layout,size=(512,500))
        ],
    ]

    console: Console

    def __init__(self) -> None:
        self.window = gui.Window('NES Emulator', self.layout, size = (1024, 500), resizable = True).Finalize()
        os.environ['SDL_WINDOWID'] = str(self.window['SCREEN'].TKCanvas.winfo_id())
        os.environ['SDL_VIDEODRIVER'] = 'windib'
        self.gameScreen = pygame.display.set_mode((256, 240))
        self.gameClock = pygame.time.Clock()
        self.fps = 60
        pygame.display.init()

    def drawRAM(self, start_addr: uint16, end_addr: uint16) -> None:
        self.window['HEX'].Update(self.console.bus.cpu.toHex(start=start_addr, end=end_addr))
        
    def drawCPU(self) -> None:
        self.window["N"].Update(text_color='RED' if self.console.bus.cpu.status & N > 0 else 'WHITE')
        self.window["V"].Update(text_color='RED' if self.console.bus.cpu.status & V > 0 else 'WHITE')
        self.window["-"].Update(text_color='RED' if self.console.bus.cpu.status & U > 0 else 'WHITE')
        self.window["B"].Update(text_color='RED' if self.console.bus.cpu.status & B > 0 else 'WHITE')
        self.window["D"].Update(text_color='RED' if self.console.bus.cpu.status & D > 0 else 'WHITE')
        self.window["I"].Update(text_color='RED' if self.console.bus.cpu.status & I > 0 else 'WHITE')
        self.window["Z"].Update(text_color='RED' if self.console.bus.cpu.status & Z > 0 else 'WHITE')
        self.window["PC"].Update("PC: ${PC:04X}".format(PC=self.console.bus.cpu.pc))
        self.window["A"].Update("A: ${a:02X}".format(a=self.console.bus.cpu.a))
        self.window["X"].Update("X: ${x:02X}".format(x=self.console.bus.cpu.x))
        self.window["Y"].Update("Y: ${y:02X}".format(y=self.console.bus.cpu.y))
        self.window["SP"].Update("SP: ${stkp:04X}".format(stkp=self.console.bus.cpu.stkp))

    def drawCode(self, delta: int = 10) -> None:
        start, end = max(self.console.bus.cpu.pc- delta, 0x0000), self.console.bus.cpu.pc + delta
        asm = self.console.bus.cpu.toReadable(start, end)
        self.window['READABLE'].Update("")
        for addr, inst in asm.items():
            self.window['READABLE'].print(inst, text_color="CYAN" if addr == self.console.bus.cpu.pc else 'WHITE')  

    def drawPatternTable(self) -> None:
        p0_img = ImageTk.PhotoImage(image=Image.fromarray(uint8(self.console.bus.ppu.getPatternTable(0,0))))
        self.window['P0'].update(data=p0_img)
        p1_img = ImageTk.PhotoImage(image=Image.fromarray(uint8(self.console.bus.ppu.getPatternTable(1,0))))
        self.window['P1'].update(data=p1_img)

    def openFile(self) -> bool:
        filename = gui.popup_get_file('file to open', file_types=(("NES Files","*.nes"),), no_window=True)
        if filename is None or filename == '':
            return False
        self.console = Console(filename)
        self.console.reset()
        self.window.TKroot.title('NES Emulator ' + filename)
        self.drawCPU()
        self.drawCode()
        return True

    def openHexViewer(self) -> bool:
        if self.console is None:
            gui.popup("Please load nes file!")
            return False
        layout = [
            [
                gui.Text("start address: "), gui.InputText(default_text="0x0000", key="START ADDR", size=(8,1)), 
                gui.Text("end address: "), gui.InputText(default_text="0xFFFF", key="END ADDR", size=(8,1)),
                gui.Button("Disassemble"),
            ],
            [gui.Multiline(key="HEX", size=(80,10), background_color='BLUE', text_color='WHITE', disabled=True)]
        ]
        window = gui.Window("Hex Viewer", layout)
        while True:
            event, values = window.read()
            if event in (None, 'Exit'):
                break
            elif event == "Disassemble":
                hexcode = self.console.bus.cpu.toHex(int(values["START ADDR"], 16), int(values["END ADDR"], 16))
                window["HEX"].Update(hexcode)
        window.close()
        return True
        
    def clock(self) -> bool:
        if self.console is None:
            gui.popup("Please load nes file!")
            return False
        self.console.clock()
        self.drawCPU()
        self.drawCode()    
        surf = pygame.surfarray.make_surface(self.console.bus.ppu.getScreen())
        self.gameScreen.blit(surf, (0,0))
        pygame.display.flip()
        return True

    def frame(self) -> bool:
        if self.console is None:
            gui.popup("Please load nes file!")
            return False
        self.console.frame()
        self.drawCPU()
        self.drawCode()    
        self.drawPatternTable()
        n = swapaxes(self.console.bus.ppu.getScreen(), 0, 1)
        surf = pygame.surfarray.make_surface(n)
        self.gameScreen.blit(surf, (0,0))
        pygame.display.flip()
        return True

    def run(self, stop: Event) -> bool:
        while not stop.is_set():
            self.console.bus.controller[0] = 0x00
            for event in pygame.event.get():
                if event.type == pygame.KEYDOWN:
                    if event.key == pygame.K_x:
                        self.console.bus.controller[0] |= 0x80
                    elif event.key == pygame.K_z:
                        self.console.bus.controller[0] |= 0x40
                    elif event.key == pygame.K_a:
                        self.console.bus.controller[0] |= 0x20
                    elif event.key == pygame.K_s:
                        self.console.bus.controller[0] |= 0x10
                    if event.key == pygame.K_UP:
                        self.console.bus.controller[0] |= 0x08
                    elif event.key == pygame.K_DOWN:
                        self.console.bus.controller[0] |= 0x04
                    elif event.key == pygame.K_LEFT:
                        self.console.bus.controller[0] |= 0x02
                    elif event.key == pygame.K_RIGHT:
                        self.console.bus.controller[0] |= 0x01
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
        self.drawCPU()
        self.drawCode()
        return True   

    def patternTable(self,i) -> bool:
        Image.fromarray(uint8(self.console.bus.ppu.getPatternTable(i, 0))).show()
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
            elif event == 'Hex Viewer':
                success = self.openHexViewer()
            elif event == 'Clock':
                success = self.clock()
            elif event == 'Frame':
                success = self.frame()
            elif event == 'Run':
                #success = self.run()
                asyncRun = Thread(target=self.run, args=(stop,))
                asyncRun.start()
            elif event == 'PatternTable0':
                success = self.patternTable(0)
            elif event == 'PatternTable1':
                success = self.patternTable(1)
            elif event == 'Reset':
                success = self.reset()
            elif event == 'About':
                gui.popup('Nes Emulator\nVersion: 0\nAuthor: CreatureOX\n')
            if not success:
                continue      
        self.window.close()

emu = Emulator()
emu.emulate()