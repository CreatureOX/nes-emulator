import os
from test import run_test

SCREENSHOT_DIR = "./screenshots/sprite_hit_tests"

if not os.path.exists(SCREENSHOT_DIR):
    os.makedirs(SCREENSHOT_DIR)

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/01.basics.nes", 
         expect_output = "SPRITE HIT BASICS PASSED", 
         error_message = "SPRITE HIT BASICS FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/01.basics.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/02.alignment.nes", 
         expect_output = "SPRITE HIT ALIGNMENT PASSED", 
         error_message = "SPRITE HIT ALIGNMENT FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/02.alignment.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/03.corners.nes", 
         expect_output = "SPRITE HIT CORNERS PASSED", 
         error_message = "SPRITE HIT CORNERS FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/03.corners.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/04.flip.nes", 
         expect_output = "SPRITE HIT FLIPPING PASSED", 
         error_message = "SPRITE HIT FLIPPING FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/04.flip.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/05.left_clip.nes", 
         expect_output = "SPRITE HIT LEFT CLIPPING PASSED", 
         error_message = "SPRITE HIT LEFT CLIPPING FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/05.left_clip.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/06.right_edge.nes", 
         expect_output = "SPRITE HIT RIGHT EDGE PASSED", 
         error_message = "SPRITE HIT RIGHT EDGE FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/06.right_edge.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/07.screen_bottom.nes", 
         expect_output = "SPRITE HIT SCREEN BOTTOM PASSED", 
         error_message = "SPRITE HIT SCREEN BOTTOM FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/07.screen_bottom.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/08.double_height.nes", 
         expect_output = "SPRITE HIT DOUBLE HEIGHT PASSED", 
         error_message = "SPRITE HIT DOUBLE HEIGHT FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/08.double_height.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/09.timing_basics.nes", 
         expect_output = "SPRITE HIT TIMING PASSED", 
         error_message = "SPRITE HIT TIMING FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/09.timing_basics.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/10.timing_order.nes", 
         expect_output = "SPRITE HIT ORDER PASSED", 
         error_message = "SPRITE HIT ORDER FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/10.timing_order.jpg")

run_test(test_rom_path = "./roms/sprite_hit_tests_2005.10.05/11.edge_timing.nes", 
         expect_output = "SPRITE HIT EDGE TIMING PASSED", 
         error_message = "SPRITE HIT EDGE TIMING FAILED", 
         screenshot_path = SCREENSHOT_DIR + "/11.edge_timing.jpg")