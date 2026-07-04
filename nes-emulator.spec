# -*- mode: python ; coding: utf-8 -*-
import os
import glob

# Get all .pyd files from nes module (Cython extensions)
nes_pyd_files = []
nes_path = 'nes'
for root, dirs, files in os.walk(nes_path):
    for f in files:
        if f.endswith('.pyd'):
            full_path = os.path.join(root, f).replace('\\', '/')
            nes_pyd_files.append((full_path, root.replace('\\', '/')))

# Get only necessary .py files (exclude .pyx, .pxd, .c, .html)
nes_py_files = []
for root, dirs, files in os.walk(nes_path):
    for f in files:
        if f.endswith('.py') and not f.endswith('.pyx'):
            full_path = os.path.join(root, f)
            dest_path = root.replace('\\', '/')
            nes_py_files.append((full_path, dest_path))

# Get GUI .py files
gui_py_files = []
for root, dirs, files in os.walk('gui'):
    for f in files:
        if f.endswith('.py'):
            full_path = os.path.join(root, f)
            dest_path = root.replace('\\', '/')
            gui_py_files.append((full_path, dest_path))

a = Analysis(
    ['nes-emulator.py'],
    pathex=[],
    binaries=nes_pyd_files,
    datas=nes_py_files + gui_py_files + [
        ('keyboard.json', '.'),
        ('pyproject.toml', '.'),
        ('images/icon.png', 'images'),
    ],
    hiddenimports=[
        'nes.cart.impl.cart_ines',
        'nes.cart.impl.cart_nes2',
        'nes.cart.impl.cart_nrom',
        'nes.cart.impl.cart_uxrom',
        'nes.cart.impl.cart_mmc1',
        'nes.cart.impl.cart_mmc3',
        'nes.cart.impl.cart_gxrom',
        'nes.cart.impl.cart_ines003',
        'nes.cpu.cpu',
        'nes.cpu.status_register',
        'nes.cpu.cpu_op',
        'nes.cpu.cpu_state',
        'nes.cpu.cpu_debug',
        'nes.cpu.registers',
        'nes.ppu.ppu',
        'nes.ppu.ppu_state',
        'nes.ppu.ppu_debug',
        'nes.ppu.ppu_sprite',
        'nes.ppu.registers',
        'nes.bus.bus',
        'nes.apu',
        'nes.console',
        'nes.state',
        'nes.mapper.mapper',
        'nes.mapper.mapper_factory',
        'nes.mapper.mapping',
        'nes.mapper.mirror',
        'nes.mapper.impl.mapper_nrom',
        'nes.mapper.impl.mapper_uxrom',
        'nes.mapper.impl.mapper_mmc1',
        'nes.mapper.impl.mapper_mmc3',
        'nes.mapper.impl.mapper_gxrom',
        'nes.mapper.impl.mapper_ines003',
        'nes.cart.cart',
        'nes.cart.cart_state',
        'nes.cart.cart_debug',
        'gui.freesimplegui.emulator_view',
        'gui.freesimplegui.base_view',
        'gui.freesimplegui.nes_file_view',
        'gui.freesimplegui.keyboard_setting_view',
        'gui.freesimplegui.keyboard_manager',
        'gui.freesimplegui.audio_output',
        'gui.freesimplegui.cpu_debug_view',
        'gui.freesimplegui.ppu_debug_view',
        'gui.freesimplegui.disassembler_view',
        'pygame',
        'FreeSimpleGUI',
        'PIL',
        'numpy',
        'cv2',
        'toml',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='FanNes',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='images/icon.png',
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='FanNes',
)