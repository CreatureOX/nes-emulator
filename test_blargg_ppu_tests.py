import os
from test import run_test

SCREENSHOT_DIR = "./screenshots/blargg_ppu_tests"

if not os.path.exists(SCREENSHOT_DIR):
    os.makedirs(SCREENSHOT_DIR)

run_test(test_rom_path = "./roms/blargg_ppu_tests_2005.09.15b/palette_ram.nes", 
         expect_output = "$01", 
         error_message = "palette_ram FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/palette_ram.jpg")

run_test(test_rom_path = "./roms/blargg_ppu_tests_2005.09.15b/power_up_palette.nes", 
         expect_output = "$01", 
         error_message = "power_up_palette FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/power_up_palette.jpg")

run_test(test_rom_path = "./roms/blargg_ppu_tests_2005.09.15b/sprite_ram.nes", 
         expect_output = "$01", 
         error_message = "sprite_ram FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/sprite_ram.jpg")

run_test(test_rom_path = "./roms/blargg_ppu_tests_2005.09.15b/vbl_clear_time.nes", 
         expect_output = "$01", 
         error_message = "vbl_clear_time FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/vbl_clear_time.jpg")

run_test(test_rom_path = "./roms/blargg_ppu_tests_2005.09.15b/vram_access.nes", 
         expect_output = "$01", 
         error_message = "vram_access FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/vram_access.jpg")
