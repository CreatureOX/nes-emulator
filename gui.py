import PySimpleGUI as gui
import pygame
import os
import numpy as np
from threading import Thread, Event, Lock
from PIL import Image, ImageTk
import cv2
import json
import pyximport; pyximport.install()

from console import Console


class Emulator:
    menu_def = [
        ['File', ['Open File','Reset','Exit']],
        ['Config', ['Keyboard']],
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

    keyboard_mapping = {
        '1':pygame.K_1,'2':pygame.K_2,'3':pygame.K_3,'4':pygame.K_4,'5':pygame.K_5,'6':pygame.K_6,'7':pygame.K_7,'8':pygame.K_8,'9':pygame.K_9,'0':pygame.K_0,
        'Q':pygame.K_q,'W':pygame.K_w,'E':pygame.K_e,'R':pygame.K_r,'T':pygame.K_t,'Y':pygame.K_y,'U':pygame.K_u,'I':pygame.K_i,'O':pygame.K_o,'P':pygame.K_p,
        'A':pygame.K_a,'S':pygame.K_s,'D':pygame.K_d,'F':pygame.K_f,'G':pygame.K_g,'H':pygame.K_h,'J':pygame.K_j,'K':pygame.K_k,'L':pygame.K_l,
        'Z':pygame.K_z,'X':pygame.K_x,'C':pygame.K_c,'V':pygame.K_v,'B':pygame.K_b,'N':pygame.K_n,'M':pygame.K_m,
        'UP':pygame.K_UP,'DOWN':pygame.K_DOWN,'LEFT':pygame.K_LEFT,'RIGHT':pygame.K_RIGHT,
    }

    console: Console = None

    def __init__(self) -> None:
        self.window = gui.Window('NES Emulator', self.layout, size = (256+20, 240+20), resizable = True, finalize=True)
        self.loadKeyboardSetting(filename = 'keyboard.json')
        os.environ['SDL_WINDOWID'] = str(self.window['SCREEN'].TKCanvas.winfo_id())
        os.environ['SDL_VIDEODRIVER'] = 'windib'
        self.gameScreen = pygame.display.set_mode((256, 240), pygame.RESIZABLE)
        self.gameClock = pygame.time.Clock()
        self.fps = 60
        pygame.display.init()
        self.lock = Lock()

    def saveKeyboardSetting(self, values, filename = None) -> bool:
        def validate_keyboard_setting(values) -> bool:
            setting = [
                values['UP'], values['DOWN'], values['LEFT'], values['RIGHT'],
                values['SELECT'], values['START'], values['B'], values['A'],
            ]
            if len(setting) != len(set(setting)):
                gui.popup('keyboard setting conflict!')
                return False
            for key in setting:
                if key not in self.keyboard_mapping.keys():
                    gui.popup('not support {}!'.format(key))
                    return False
            return True
        
        if not validate_keyboard_setting(values):
            return False
        self.keyboard = {
            'UP': self.keyboard_mapping[values['UP']],
            'DOWN': self.keyboard_mapping[values['DOWN']],
            'LEFT': self.keyboard_mapping[values['LEFT']],
            'RIGHT': self.keyboard_mapping[values['RIGHT']],
            'SELECT': self.keyboard_mapping[values['SELECT']],
            'START': self.keyboard_mapping[values['START']],
            'B': self.keyboard_mapping[values['B']],
            'A': self.keyboard_mapping[values['A']],
        }
        if filename:
            with open(filename, 'w') as keyboard_setting:
                json.dump(self.keyboard, keyboard_setting)
        return True

    def loadKeyboardSetting(self, filename = None):
        default_keyboard = {
            'UP': pygame.K_UP,
            'DOWN': pygame.K_DOWN,
            'LEFT': pygame.K_LEFT,
            'RIGHT': pygame.K_RIGHT,
            'SELECT': pygame.K_c,
            'START': pygame.K_v,
            'B': pygame.K_x,
            'A': pygame.K_z,
        } 
        if not filename or not os.path.exists(filename):
            self.keyboard = default_keyboard
            return
        with open(filename, 'r') as keyboard_setting:
            try:
                self.keyboard = json.load(keyboard_setting)
            except:
                self.keyboard = default_keyboard

    def openKeyboardSetting(self) -> bool:
        def getKey(name):
            return [k for k, v in self.keyboard_mapping.items() if v == self.keyboard[name]][0]
        
        def keyboard_setting_layout():
            return [
                [gui.Text("↑", size=(2,1)), gui.InputText(default_text=getKey("UP"), key="UP", size=(6,1)), gui.Text("SELECT", size=(7,1)), gui.InputText(default_text=getKey("SELECT"), key="SELECT", size=(6,1)),],
                [gui.Text("↓", size=(2,1)), gui.InputText(default_text=getKey("DOWN"), key="DOWN", size=(6,1)), gui.Text("  START", size=(7,1)), gui.InputText(default_text=getKey("START"), key="START", size=(6,1)),],
                [gui.Text("←", size=(2,1)), gui.InputText(default_text=getKey("LEFT"), key="LEFT", size=(6,1)), gui.Text("      B", size=(7,1)), gui.InputText(default_text=getKey("B"), key="B", size=(6,1)),],
                [gui.Text("→", size=(2,1)), gui.InputText(default_text=getKey("RIGHT"), key="RIGHT", size=(6,1)), gui.Text("      A", size=(7,1)), gui.InputText(default_text=getKey("A"), key="A", size=(6,1)),],
                [gui.Button("Apply", key="APPLY")],
            ]
        
        keyboard_setting_window = gui.Window('KEYBOARD', keyboard_setting_layout(), return_keyboard_events = True)
        while True:
            event, values = keyboard_setting_window.read()
            if event in (None, 'Exit'):
                break
            if event == 'APPLY':
                success = self.saveKeyboardSetting(values, filename='keyboard.json')
                if not success:
                    continue
            else:
                focus_element = keyboard_setting_window.find_element_with_focus()
                keyboard_setting_window[focus_element.key].Update(event.split(":")[0].upper())
        keyboard_setting_window.close()
        return True

    def openCPUDebug(self) -> bool:
        def cpu_debug_layout():
            return [
                [
                    gui.Text("STATUS: ", size=(8,1), text_color='WHITE'),
                    gui.Text("N", key="N", size=(1,1), text_color='WHITE'),
                    gui.Text("V", key="V", size=(1,1), text_color='WHITE'),
                    gui.Text("B", key="B", size=(1,1), text_color='WHITE'),
                    gui.Text("D", key="D", size=(1,1), text_color='WHITE'),
                    gui.Text("I", key="I", size=(1,1), text_color='WHITE'),
                    gui.Text("Z", key="Z", size=(1,1), text_color='WHITE'),
                ],
                [
                    gui.Text("PC: $0x0000", key="PC", size=(11,1)),
                    gui.Text("A: $0x00", key="A", size=(8,1)),
                    gui.Text("X: $0x00", key="X", size=(8,1)),
                    gui.Text("Y: $0x00", key="Y", size=(8,1)),
                    gui.Text("SP: $0x0000", key="SP", size=(10,1)),
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
                pressed[self.keyboard['SELECT']],pressed[self.keyboard['START']],pressed[self.keyboard['B']],pressed[self.keyboard['A']],
                pressed[self.keyboard['UP']],pressed[self.keyboard['DOWN']],pressed[self.keyboard['LEFT']],pressed[self.keyboard['RIGHT']]
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
            elif event == 'Reset':
                self.console.reset()
            elif event == 'Keyboard':
                success = self.openKeyboardSetting()
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
