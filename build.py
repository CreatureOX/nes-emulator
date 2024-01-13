import PyInstaller.__main__

PyInstaller.__main__.run([
    'run.py',
    '--onefile',
    '--name=NES EMULATOR',
    '--windowed',
    '--add-data=keyboard.json;.',
    '--hidden-import=gui',
    '--hidden-import=pyaudio',
    '--hidden-import=mirror',
    '--hidden-import=mapper',
    '--hidden-import=cartridge',
    '--hidden-import=bus',
    '--hidden-import=cpu',
    '--hidden-import=ppu',
    '--hidden-import=apu',
    '--hidden-import=console',
])