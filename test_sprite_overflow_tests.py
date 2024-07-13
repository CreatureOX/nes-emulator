import os
from test import run_test

SCREENSHOT_DIR = "./screenshots/sprite_overflow_tests"

if not os.path.exists(SCREENSHOT_DIR):
    os.makedirs(SCREENSHOT_DIR)

run_test(test_rom_path = "./roms/sprite_overflow_tests/1.Basics.nes", 
         expect_output = "SPRITE OVERFLOW BASICS PASSED", 
         error_message = "SPRITE OVERFLOW BASICS FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/1.Basics.jpg")

run_test(test_rom_path = "./roms/sprite_overflow_tests/2.Details.nes", 
         expect_output = "SPRITE OVERFLOW DETAILS PASSED", 
         error_message = "SPRITE OVERFLOW DETAILS FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/2.Details.jpg")

run_test(test_rom_path = "./roms/sprite_overflow_tests/3.Timing.nes", 
         expect_output = "SPRITE OVERFLOW TIMING PASSED", 
         error_message = "SPRITE OVERFLOW TIMING FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/3.Timing.jpg")

run_test(test_rom_path = "./roms/sprite_overflow_tests/4.Obscure.nes", 
         expect_output = "SPRITE OVERFLOW OBSCURE PASSED", 
         error_message = "SPRITE OVERFLOW OBSCURE FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/4.Obscure.jpg")

run_test(test_rom_path="./roms/sprite_overflow_tests/5.Emulator.nes", 
         expect_output = "SPRITE OVERFLOW EMULATION PASSED", 
         error_message = "SPRITE OVERFLOW EMULATION FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/5.Emulator.jpg")