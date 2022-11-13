import PySimpleGUI as gui
from PIL import Image, ImageTk
from numpy import uint16, void
from cartridge import Cartridge
from bus import CPUBus

menu_def = [
    ['File', ['Open File','Exit']],
    ['Debug', ['Hex Viewer',]],
    ['Help', ['About',]],
]
screen_layout = [[gui.Image(key="SCREEN", size=(500,500), background_color='BLACK')]]
utils_layout = [
    [gui.Button('Clock'),gui.Button('Frame'),gui.Button('Reset'),],
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

window = gui.Window('NES Emulator', layout, size=(1024, 500), resizable=True)


cart = None
bus = None

def drawRAM(start_addr: uint16, end_addr: uint16) -> void:
    window['HEX'].Update(bus.cpu.toHex(start=start_addr, end=end_addr))

def drawCPU() -> void:
    window["N"].Update(text_color='RED' if bus.cpu.status & bus.cpu.FLAGS.N > 0 else 'WHITE')
    window["V"].Update(text_color='RED' if bus.cpu.status & bus.cpu.FLAGS.V > 0 else 'WHITE')
    window["-"].Update(text_color='RED' if bus.cpu.status & bus.cpu.FLAGS.U > 0 else 'WHITE')
    window["B"].Update(text_color='RED' if bus.cpu.status & bus.cpu.FLAGS.B > 0 else 'WHITE')
    window["D"].Update(text_color='RED' if bus.cpu.status & bus.cpu.FLAGS.D > 0 else 'WHITE')
    window["I"].Update(text_color='RED' if bus.cpu.status & bus.cpu.FLAGS.I > 0 else 'WHITE')
    window["Z"].Update(text_color='RED' if bus.cpu.status & bus.cpu.FLAGS.Z > 0 else 'WHITE')
    window["PC"].Update("PC: ${PC:04X}".format(PC=bus.cpu.pc))
    window["A"].Update("A: ${a:02X}".format(a=bus.cpu.a))
    window["X"].Update("X: ${x:02X}".format(x=bus.cpu.x))
    window["Y"].Update("Y: ${y:02X}".format(y=bus.cpu.y))
    window["SP"].Update("SP: ${stkp:04X}".format(stkp=bus.cpu.stkp))

def drawCode(delta: int = 10) -> void:
    start, end = max(bus.cpu.pc- delta, 0x0000), bus.cpu.pc + delta
    asm = bus.cpu.toReadable(start, end)
    window['READABLE'].Update("")
    for addr, inst in asm.items():
        window['READABLE'].print(inst, text_color="CYAN" if addr == bus.cpu.pc else 'WHITE')  


while True:
    event, values = window.read()
    if event in (None, 'Exit'):
        break
    elif event == 'Open File':
        filename = gui.popup_get_file('file to open', file_types=(("NES Files","*.nes"),), no_window=True)
        if filename is None or filename == '':
            continue
        cart = Cartridge(filename)
        bus = CPUBus(cart)
        bus.cpu.reset()
        window.TKroot.title('NES Emulator ' + filename)
        drawCPU()
        drawCode()   
    elif event == 'Hex Viewer':
        def openHexViewer() -> void:
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
                    hexcode = bus.cpu.toHex(int(values["START ADDR"], 16), int(values["END ADDR"], 16) )
                    window["HEX"].Update(hexcode)
            window.close()
        
        if cart is None:
            gui.popup("Please load nes file!")
            continue
        openHexViewer()
    elif event == 'Clock':
        if cart is None:
            gui.popup("Please load nes file!")
            continue
        while True:
            bus.clock()
            if bus.cpu.complete():
                break
        while True:
            bus.clock()
            if not bus.cpu.complete():
                break
        drawCPU()
        drawCode()    
        image = ImageTk.PhotoImage(image=Image.fromarray(bus.ppu.getScreen().rgb))
        window['SCREEN'].update(data=image)
    elif event == 'Frame':
        if cart is None:
            gui.popup("Please load nes file!")
            continue
        while True:
            bus.clock()
            if bus.ppu.frame_complete:
                break
        while True:
            bus.clock()
            if bus.cpu.complete():
                break
        bus.ppu.frame_complete = False
        drawCPU()
        drawCode()    
        image = ImageTk.PhotoImage(image=Image.fromarray(bus.ppu.getScreen().rgb))
        window['SCREEN'].update(data=image)
    elif event == 'Reset':
        if cart is None:
            gui.popup("Please load nes file!")
            continue
        bus.reset()
        drawCPU()
        drawCode()   
    elif event == 'About':
        gui.popup('Nes Emulator\nVersion: 0\nAuthor: CreatureOX\n')

window.close()