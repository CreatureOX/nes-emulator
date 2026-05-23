import pygame
import json
from pathlib import Path

pygame.init()

# 1. 显示当前配置
print("=== 当前键位配置 ===")
path = Path(__file__).parent / "keyboard.json"
with open(path) as f:
    current = json.load(f)
print(json.dumps(current, indent=2))

# 2. 测试将配置修改为WASD
print("\n=== 测试模拟 Apply WASD 配置 ===")

MAPPING = {
    '1':pygame.K_1,'2':pygame.K_2,'3':pygame.K_3,'4':pygame.K_4,'5':pygame.K_5,'6':pygame.K_6,'7':pygame.K_7,'8':pygame.K_8,'9':pygame.K_9,'0':pygame.K_0,
    'Q':pygame.K_q,'W':pygame.K_w,'E':pygame.K_e,'R':pygame.K_r,'T':pygame.K_t,'Y':pygame.K_y,'U':pygame.K_u,'I':pygame.K_i,'O':pygame.K_o,'P':pygame.K_p,
    'A':pygame.K_a,'S':pygame.K_s,'D':pygame.K_d,'F':pygame.K_f,'G':pygame.K_g,'H':pygame.K_h,'J':pygame.K_j,'K':pygame.K_k,'L':pygame.K_l,
    'Z':pygame.K_z,'X':pygame.K_x,'C':pygame.K_c,'V':pygame.K_v,'B':pygame.K_b,'N':pygame.K_n,'M':pygame.K_m,
    'UP':pygame.K_UP,'DOWN':pygame.K_DOWN,'LEFT':pygame.K_LEFT,'RIGHT':pygame.K_RIGHT,
}

# 模拟用户输入 WASD
values = {
    '-UP-': 'W',
    '-DOWN-': 'S',
    '-LEFT-': 'A',
    '-RIGHT-': 'D',
    '-SELECT-': 'C',
    '-START-': 'V',
    '-B-': 'X',
    '-A-': 'Z',
}

new_keyboard = {
    'UP': MAPPING[values['-UP-']],
    'DOWN': MAPPING[values['-DOWN-']],
    'LEFT': MAPPING[values['-LEFT-']],
    'RIGHT': MAPPING[values['-RIGHT-']],
    'SELECT': MAPPING[values['-SELECT-']],
    'START': MAPPING[values['-START-']],
    'B': MAPPING[values['-B-']],
    'A': MAPPING[values['-A-']],
}

print("新的配置会是:")
print(json.dumps(new_keyboard, indent=2))

# 3. 保存并读取
print("\n=== 模拟保存并立即读取 ===")
with open(path, 'w') as f:
    json.dump(new_keyboard, f)

with open(path) as f:
    saved = json.load(f)
print("读取到的配置:")
print(json.dumps(saved, indent=2))

# 4. 验证虚拟键码映射
print("\n=== 虚拟键码映射验证 ===")
pygame_to_vk = {
    pygame.K_w: 0x57, pygame.K_s: 0x53, pygame.K_a: 0x41, pygame.K_d: 0x44,
    pygame.K_c: 0x43, pygame.K_v: 0x56, pygame.K_x: 0x58, pygame.K_z: 0x5A,
    pygame.K_UP: 0x26, pygame.K_DOWN: 0x28, pygame.K_LEFT: 0x25, pygame.K_RIGHT: 0x27,
}

for action, key_code in saved.items():
    vk = pygame_to_vk.get(key_code)
    if vk:
        print(f'✓ {action}: code={key_code} -> VK={hex(vk)}')
    else:
        print(f'✗ {action}: code={key_code} -> NOT IN MAP!')
