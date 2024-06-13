import time
import os
import easyocr
from gui import Emulator
from console import Console
from threading import Thread, Event


reader = easyocr.Reader(['en'])

def _run_ocr(filename: str) -> str:
    with open(filename, 'rb') as file:
        image = file.read()
    results = reader.readtext(image)
    words = [result[1] for result in results]
    return " ".join(words)

emu = Emulator()

def run_test(test_rom_path: str,
             expect_output: str,
             error_message: str,
             wait_seconds: int = 2,
             screenshot_path: str = None,
             keep_screenshot: bool = True) -> None:
    # launch emulator
    emu.console = Console(test_rom_path)
    emu.console.power_up()
    # run
    stop = Event()
    async_run = Thread(target=emu.run, args=(stop,))
    async_run.start()
    time.sleep(wait_seconds)
    stop.set()
    # test
    _, screenshot_path = emu.capture_screenshot(screenshot_path)
    assert _run_ocr(screenshot_path) == expect_output, error_message
    print(f'{test_rom_path} PASSED')
    # clean
    if not keep_screenshot:
        os.remove(screenshot_path)
