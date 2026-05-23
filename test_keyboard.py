import pygame
import json

pygame.init()

# 读取键位配置
with open('keyboard.json') as f:
    keyboard = json.load(f)
    
print('Loaded keyboard config:', keyboard)

# 创建映射表
pygame_to_vk = {
    pygame.K_1: 0x31, pygame.K_2: 0x32, pygame.K_3: 0x33, pygame.K_4: 0x34, pygame.K_5: 0x35,
    pygame.K_6: 0x36, pygame.K_7: 0x37, pygame.K_8: 0x38, pygame.K_9: 0x39, pygame.K_0: 0x30,
    pygame.K_q: 0x51, pygame.K_w: 0x57, pygame.K_e: 0x45, pygame.K_r: 0x52, pygame.K_t: 0x54,
    pygame.K_y: 0x59, pygame.K_u: 0x55, pygame.K_i: 0x49, pygame.K_o: 0x4F, pygame.K_p: 0x50,
    pygame.K_a: 0x41, pygame.K_s: 0x53, pygame.K_d: 0x44, pygame.K_f: 0x46, pygame.K_g: 0x47,
    pygame.K_h: 0x48, pygame.K_j: 0x4A, pygame.K_k: 0x4B, pygame.K_l: 0x4C,
    pygame.K_z: 0x5A, pygame.K_x: 0x58, pygame.K_c: 0x43, pygame.K_v: 0x56, pygame.K_b: 0x42,
    pygame.K_n: 0x4E, pygame.K_m: 0x4D,
    pygame.K_UP: 0x26, pygame.K_DOWN: 0x28, pygame.K_LEFT: 0x25, pygame.K_RIGHT: 0x27,
}

print("\nPygame keycodes:")
print(f"w={pygame.K_w}, s={pygame.K_s}, a={pygame.K_a}, d={pygame.K_d}")
print(f"UP={pygame.K_UP}, DOWN={pygame.K_DOWN}, LEFT={pygame.K_LEFT}, RIGHT={pygame.K_RIGHT}")

# 测试映射
print("\nKey mapping results:")
for action, key_code in keyboard.items():
    vk = pygame_to_vk.get(key_code)
    vk_hex = hex(vk) if vk else "NOT FOUND"
    print(f'{action} (code={key_code}): VK={vk_hex}')
