# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['nes-emulator.py'],
    pathex=[],
    binaries=[],
    datas=[('nes', 'nes')],
    hiddenimports=['nes.cart.impl.cart_ines', 'nes.cart.impl.cart_nes2', 'gui.freesimplegui.emulator_view', 'gui.freesimplegui.base_view', 'gui.freesimplegui.nes_file_view', 'pyexpat'],
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
    name='nes-emulator',
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
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='nes-emulator',
)
