import PySimpleGUI as gui
import pygame
import os
from numpy import uint16, void, swapaxes
from cartridge import Cartridge
from bus import CPUBus

class Emulator:
    menu_def = [
        ['File', ['Open File','Exit']],
        ['Debug', ['Hex Viewer',]],
        ['Help', ['About',]],
    ]
    
    screen_layout = [[gui.Graph(key="SCREEN", canvas_size=(240,256), graph_bottom_left=(0,0), graph_top_right=(500,500), background_color='BLACK')]]
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
    ]

    layout = [
        [gui.Menu(menu_def)],
        [
            gui.Column(screen_layout,size=(512,500)), 
            gui.Column(utils_layout,size=(512,500))
        ],
    ]

    cart: Cartridge
    bus: CPUBus

    def __init__(self) -> None:
        self.window = gui.Window('NES Emulator', self.layout, size = (1024, 500), resizable = True).Finalize()
        os.environ['SDL_WINDOWID'] = str(self.window['SCREEN'].TKCanvas.winfo_id())
        os.environ['SDL_VIDEODRIVER'] = 'windib'
        self.gameScreen = pygame.display.set_mode((240, 256))
        self.gameClock = pygame.time.Clock()
        self.fps = 30
        pygame.display.init()

    def drawRAM(self, start_addr: uint16, end_addr: uint16) -> void:
        self.window['HEX'].Update(self.bus.cpu.toHex(start=start_addr, end=end_addr))
        
    def drawCPU(self) -> void:
        self.window["N"].Update(text_color='RED' if self.bus.cpu.status & self.bus.cpu.FLAGS.N > 0 else 'WHITE')
        self.window["V"].Update(text_color='RED' if self.bus.cpu.status & self.bus.cpu.FLAGS.V > 0 else 'WHITE')
        self.window["-"].Update(text_color='RED' if self.bus.cpu.status & self.bus.cpu.FLAGS.U > 0 else 'WHITE')
        self.window["B"].Update(text_color='RED' if self.bus.cpu.status & self.bus.cpu.FLAGS.B > 0 else 'WHITE')
        self.window["D"].Update(text_color='RED' if self.bus.cpu.status & self.bus.cpu.FLAGS.D > 0 else 'WHITE')
        self.window["I"].Update(text_color='RED' if self.bus.cpu.status & self.bus.cpu.FLAGS.I > 0 else 'WHITE')
        self.window["Z"].Update(text_color='RED' if self.bus.cpu.status & self.bus.cpu.FLAGS.Z > 0 else 'WHITE')
        self.window["PC"].Update("PC: ${PC:04X}".format(PC=self.bus.cpu.pc))
        self.window["A"].Update("A: ${a:02X}".format(a=self.bus.cpu.a))
        self.window["X"].Update("X: ${x:02X}".format(x=self.bus.cpu.x))
        self.window["Y"].Update("Y: ${y:02X}".format(y=self.bus.cpu.y))
        self.window["SP"].Update("SP: ${stkp:04X}".format(stkp=self.bus.cpu.stkp))

    def drawCode(self, delta: int = 10) -> void:
        start, end = max(self.bus.cpu.pc- delta, 0x0000), self.bus.cpu.pc + delta
        asm = self.bus.cpu.toReadable(start, end)
        self.window['READABLE'].Update("")
        for addr, inst in asm.items():
            self.window['READABLE'].print(inst, text_color="CYAN" if addr == self.bus.cpu.pc else 'WHITE')  

    def openFile(self) -> bool:
        filename = gui.popup_get_file('file to open', file_types=(("NES Files","*.nes"),), no_window=True)
        if filename is None or filename == '':
            return False
        self.cart = Cartridge(filename)
        self.bus = CPUBus(self.cart)
        self.bus.cpu.reset()
        self.window.TKroot.title('NES Emulator ' + filename)
        self.drawCPU()
        self.drawCode()
        return True

    def openHexViewer(self) -> bool:
        if self.cart is None:
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
                hexcode = self.bus.cpu.toHex(int(values["START ADDR"], 16), int(values["END ADDR"], 16) )
                window["HEX"].Update(hexcode)
        window.close()
        return True
        
    def clock(self) -> bool:
        if self.cart is None:
            gui.popup("Please load nes file!")
            return False
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        while True:
            self.bus.clock()
            if not self.bus.cpu.complete():
                break
        self.drawCPU()
        self.drawCode()    
        surf = pygame.surfarray.make_surface(swapaxes(self.bus.ppu.getScreen().rgb.astype('uint8'), 0, 1))
        self.gameScreen.blit(surf, (0,0))
        pygame.display.flip()
        return True

    def frame(self) -> bool:
        if self.cart is None:
            gui.popup("Please load nes file!")
            return False
            
        while True:
            self.bus.clock()
            if self.bus.ppu.frame_complete:
                break
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        self.bus.ppu.frame_complete = False
        self.drawCPU()
        self.drawCode()    
        surf = pygame.surfarray.make_surface(swapaxes(self.bus.ppu.getScreen().rgb.astype('uint8'), 0, 1))
        self.gameScreen.blit(surf, (0,0))
        pygame.display.flip()
        return True

    def run(self) -> bool:
        gameLoop = True
        while gameLoop:
            pygame.event.pump()
            self.gameClock.tick(self.fps)
            while True:
                self.bus.clock()
                if self.bus.ppu.frame_complete:
                    break
            self.bus.ppu.frame_complete = False
            surf = pygame.surfarray.make_surface(swapaxes(self.bus.ppu.getScreen().rgb.astype('uint8'), 0, 1))
            self.gameScreen.blit(surf, (0,0))
            pygame.display.flip()
        return True

    def reset(self) -> bool:
        if self.cart is None:
            gui.popup("Please load nes file!")
            return False
        self.bus.reset()
        self.drawCPU()
        self.drawCode()
        return True   

    def emulate(self) -> None:
        while True:
            event, values = self.window.read()
            success = True
            if event in (None, 'Exit'):
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
                success = self.run()
            elif event == 'Reset':
                success = self.reset()
            elif event == 'About':
                gui.popup('Nes Emulator\nVersion: 0\nAuthor: CreatureOX\n')
            if not success:
                continue   
        self.window.close()

emu = Emulator()
emu.emulate()