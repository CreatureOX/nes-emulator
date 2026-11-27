#!/usr/bin/env python3
"""
Cross-platform build script for FanNes
Usage:
    python build.py              # Build for current platform
    python build.py --win        # Build for Windows
    python build.py --mac        # Build for macOS
    python build.py --clean      # Clean build artifacts
"""
import os
import sys
import subprocess
import shutil
import argparse
import glob
import toml

PLATFORM = sys.platform
IS_WINDOWS = PLATFORM.startswith('win')
IS_MAC = PLATFORM.startswith('darwin')

def get_pyinstaller_data_arg():
    """Get platform-specific --add-data argument"""
    if IS_WINDOWS:
        return "nes;nes"
    else:
        return "nes:nes"

def install_dependencies():
    """Install required dependencies"""
    print("Installing dependencies...")
    subprocess.run([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"], check=True)
    subprocess.run([sys.executable, "-m", "pip", "install", "pyinstaller"], check=True)

def build_cython():
    """Build Cython extensions"""
    print("Building Cython extensions...")
    subprocess.run([sys.executable, "setup.py", "build_ext", "--inplace"], check=True)

def build_exe():
    """Build executable using PyInstaller"""
    print(f"Building for {PLATFORM}...")
    
    hidden_imports = [
        "nes.cart.impl.cart_ines",
        "nes.cart.impl.cart_nes2",
        "nes.mapper.impl.mapper_nrom",
        "nes.mapper.impl.mapper_mmc1",
        "nes.mapper.impl.mapper_uxrom",
        "nes.mapper.impl.mapper_ines003",
        "nes.mapper.impl.mapper_mmc3",
        "nes.mapper.impl.mapper_mmc5",
        "nes.mapper.impl.mapper_gxrom",
        "nes.mapper.impl.mapper_axrom",
        "nes.mapper.impl.mapper_colordreams",
        "nes.mapper.impl.mapper_bnrom",
        "nes.mapper.impl.mapper_vrc2a",
        "nes.mapper.impl.mapper_action53",
        "nes.mapper.impl.mapper_cprom",
        "nes.mapper.impl.mapper_mmc2",
        "nes.mapper.impl.mapper_mmc4",
        "nes.mapper.impl.mapper_rambo1",
        "nes.mapper.impl.mapper_fme7",
        "nes.mapper.impl.mapper_078",
        "nes.mapper.impl.mapper_118",
        "nes.mapper.impl.mapper_180",
        "gui.freesimplegui.emulator_view",
        "gui.freesimplegui.base_view",
        "gui.freesimplegui.nes_file_view",
        "gui.freesimplegui.keyboard_setting_view",
        "gui.freesimplegui.keyboard_manager",
        "gui.freesimplegui.audio_output",
        "gui.freesimplegui.cpu_debug_view",
        "gui.freesimplegui.ppu_debug_view",
        "gui.freesimplegui.disassembler_view",
        "pygame",
        "FreeSimpleGUI",
        "PIL",
        "numpy",
        "cv2",
        "toml",
    ]
    
    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--clean",
        "--windowed",
        "--name", "FanNes",
        "--add-data", get_pyinstaller_data_arg(),
    ]
    
    for imp in hidden_imports:
        cmd.extend(["--hidden-import", imp])
    
    cmd.append("nes-emulator.py")
    
    subprocess.run(cmd, check=True)
    
    if IS_MAC:
        create_macos_app_bundle()

def create_macos_app_bundle():
    """Create macOS .app bundle structure"""
    print("Creating macOS app bundle...")
    app_path = "dist/FanNes.app"
    if os.path.exists(app_path):
        shutil.rmtree(app_path)
    
    os.makedirs(f"{app_path}/Contents/MacOS")
    os.makedirs(f"{app_path}/Contents/Resources")
    
    # PyInstaller 6 onedir puts the executable next to _internal; both belong
    # in Contents/MacOS so CFBundleExecutable resolves to a regular file.
    exe_path = "dist/FanNes/FanNes"
    internal_path = "dist/FanNes/_internal"
    for path in (exe_path, internal_path):
        if not os.path.exists(path):
            raise FileNotFoundError(f"Expected PyInstaller output: {path}")
    shutil.move(exe_path, f"{app_path}/Contents/MacOS/FanNes")
    shutil.move(internal_path, f"{app_path}/Contents/MacOS/_internal")
    shutil.rmtree("dist/FanNes")

    # Keep the bundle version in sync with the project metadata.
    version = toml.load("pyproject.toml")["project"]["version"]

    icon_entry = ""
    icon_file = "images/FanNes.icns"
    if os.path.exists(icon_file):
        shutil.copy2(icon_file, f"{app_path}/Contents/Resources/")
        icon_entry = "    <key>CFBundleIconFile</key>\n    <string>FanNes.icns</string>\n"

    # Create Info.plist
    info_plist = f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FanNes</string>
    <key>CFBundleIdentifier</key>
    <string>com.fannes.emulator</string>
    <key>CFBundleName</key>
    <string>FanNes</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>{version}</string>
    <key>CFBundleVersion</key>
    <string>{version}</string>
{icon_entry}    <key>LSMinimumSystemVersion</key>
    <string>10.13</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>'''

    with open(f"{app_path}/Contents/Info.plist", "w") as f:
        f.write(info_plist)
    
    print(f"macOS app bundle created at: {app_path}")

def clean():
    """Clean build artifacts"""
    print("Cleaning build artifacts...")
    
    # The spec and status_register.h are tracked sources, not build products.
    patterns = ["dist", "build", "*.egg-info"]
    
    for pattern in patterns:
        if "*" in pattern:
            for item in glob.glob(pattern):
                if os.path.isdir(item):
                    shutil.rmtree(item)
                else:
                    os.remove(item)
        else:
            if os.path.exists(pattern):
                if os.path.isdir(pattern):
                    shutil.rmtree(pattern)
                else:
                    os.remove(pattern)
    
    # Clean Cython artifacts
    for root, dirs, files in os.walk("nes"):
        for f in files:
            if f.endswith((".pyd", ".so", ".c", ".html")):
                try:
                    os.remove(os.path.join(root, f))
                except:
                    pass

def main():
    parser = argparse.ArgumentParser(description="Build FanNes")
    parser.add_argument("--win", action="store_true", help="Build for Windows")
    parser.add_argument("--mac", action="store_true", help="Build for macOS")
    parser.add_argument("--clean", action="store_true", help="Clean build artifacts")
    parser.add_argument("--deps", action="store_true", help="Install dependencies only")
    args = parser.parse_args()
    
    if args.clean:
        clean()
        return
    
    if args.deps:
        install_dependencies()
        return
    
    # Install deps, build cython, then build exe
    install_dependencies()
    build_cython()
    build_exe()
    
    print("\n=== Build Complete ===")
    print("Output directory: dist/")

if __name__ == "__main__":
    main()
