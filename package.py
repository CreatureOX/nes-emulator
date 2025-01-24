import os
import PyInstaller.__main__

os.system("python setup.py build_ext --inplace")

PyInstaller.__main__.run([
    'nes-emulator.py',
    # '--onefile',
    '--name=nes-emulator',
    '--add-data=nes;nes',
    '--hidden-import=nes.cart.impl.cart_ines',
    '--hidden-import=nes.cart.impl.cart_nes2',
    '--hidden-import=gui.freesimplegui.emulator_view',
    '--hidden-import=gui.freesimplegui.base_view',
    '--hidden-import=gui.freesimplegui.nes_file_view',
    '--hidden-import=pyexpat',
    '--windowed'
])