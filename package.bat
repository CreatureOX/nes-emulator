@echo off
REM Build script for Windows
REM Usage: package.bat [clean]

if "%1"=="clean" (
    echo Cleaning build artifacts...
    if exist dist rmdir /s /q dist
    if exist build rmdir /s /q build
    if exist nes-emulator.spec del /q nes-emulator.spec
    goto :eof
)

echo Building FanNes for Windows...

REM Download icon if not exists
if not exist images mkdir images
if not exist images/icon.png (
    curl -L -o images/icon.png https://i.postimg.cc/g2sjHRZ0/icon.png
    if not exist images/icon.png (
        echo Failed to download icon!
        exit /b 1
    )
)

REM Install dependencies
pip install -r requirements.txt
pip install pyinstaller

REM Build Cython extensions
python setup.py build_ext --inplace

REM Build EXE using spec file
pyinstaller nes-emulator.spec --clean --noconfirm

echo Build complete! Output in dist\FanNes