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

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/01.basics.nes", 
         expect_output="SPRITE HIT BASICS PASSED", 
         error_message="SPRITE HIT BASICS FAILED", 
         screenshot_path="./screenshots/01.basics.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/02.alignment.nes", 
         expect_output="SPRITE HIT ALIGNMENT PASSED", 
         error_message="SPRITE HIT ALIGNMENT FAILED", 
         screenshot_path="./screenshots/02.alignment.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/03.corners.nes", 
         expect_output="SPRITE HIT CORNERS PASSED", 
         error_message="SPRITE HIT CORNERS FAILED", 
         screenshot_path="./screenshots/03.corners.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/04.flip.nes", 
         expect_output="SPRITE HIT FLIPPING PASSED", 
         error_message="SPRITE HIT FLIPPING FAILED", 
         screenshot_path="./screenshots/04.flip.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/05.left_clip.nes", 
         expect_output="SPRITE HIT LEFT CLIPPING PASSED", 
         error_message="SPRITE HIT LEFT CLIPPING FAILED", 
         screenshot_path="./screenshots/05.left_clip.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/06.right_edge.nes", 
         expect_output="SPRITE HIT RIGHT EDGE PASSED", 
         error_message="SPRITE HIT RIGHT EDGE FAILED", 
         screenshot_path="./screenshots/06.right_edge.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/07.screen_bottom.nes", 
         expect_output="SPRITE HIT SCREEN BOTTOM PASSED", 
         error_message="SPRITE HIT SCREEN BOTTOM FAILED", 
         screenshot_path="./screenshots/07.screen_bottom.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/08.double_height.nes", 
         expect_output="SPRITE HIT DOUBLE HEIGHT PASSED", 
         error_message="SPRITE HIT DOUBLE HEIGHT FAILED", 
         screenshot_path="./screenshots/08.double_height.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/09.timing_basics.nes", 
         expect_output="SPRITE HIT TIMING PASSED", 
         error_message="SPRITE HIT TIMING FAILED", 
         screenshot_path="./screenshots/09.timing_basics.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/10.timing_order.nes", 
         expect_output="SPRITE HIT ORDER PASSED", 
         error_message="SPRITE HIT ORDER FAILED", 
         screenshot_path="./screenshots/10.timing_order.jpg")

run_test(test_rom_path="./roms/sprite_hit_tests_2005.10.05/11.edge_timing.nes", 
         expect_output="SPRITE HIT EDGE TIMING PASSED", 
         error_message="SPRITE HIT EDGE TIMING FAILED", 
         screenshot_path="./screenshots/11.edge_timing.jpg")

run_test(test_rom_path="./roms/sprite_overflow_tests/1.Basics.nes", 
         expect_output="SPRITE OVERFLOW BASICS PASSED", 
         error_message="SPRITE OVERFLOW BASICS FAILED", 
         screenshot_path="./screenshots/1.Basics.jpg")

run_test(test_rom_path="./roms/sprite_overflow_tests/2.Details.nes", 
         expect_output="SPRITE OVERFLOW DETAILS PASSED", 
         error_message="SPRITE OVERFLOW DETAILS FAILED", 
         screenshot_path="./screenshots/2.Details.jpg")

run_test(test_rom_path="./roms/sprite_overflow_tests/3.Timing.nes", 
         expect_output="SPRITE OVERFLOW TIMING PASSED", 
         error_message="SPRITE OVERFLOW TIMING FAILED", 
         screenshot_path="./screenshots/3.Timing.jpg")

run_test(test_rom_path="./roms/sprite_overflow_tests/4.Obscure.nes", 
         expect_output="SPRITE OVERFLOW OBSCURE PASSED", 
         error_message="SPRITE OVERFLOW OBSCURE FAILED", 
         screenshot_path="./screenshots/4.Obscure.jpg")

run_test(test_rom_path="./roms/sprite_overflow_tests/5.Emulator.nes", 
         expect_output="SPRITE OVERFLOW EMULATION PASSED", 
         error_message="SPRITE OVERFLOW EMULATION FAILED", 
         screenshot_path="./screenshots/5.Emulator.jpg")