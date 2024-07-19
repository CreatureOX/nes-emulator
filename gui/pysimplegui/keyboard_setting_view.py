import PySimpleGUI as sg
from gui.pysimplegui.base_view import BaseView
import pygame
import json
import os


class KeyboardSettingWindow(BaseView):
    __MAPPING = {
        '1':pygame.K_1,'2':pygame.K_2,'3':pygame.K_3,'4':pygame.K_4,'5':pygame.K_5,'6':pygame.K_6,'7':pygame.K_7,'8':pygame.K_8,'9':pygame.K_9,'0':pygame.K_0,
        'Q':pygame.K_q,'W':pygame.K_w,'E':pygame.K_e,'R':pygame.K_r,'T':pygame.K_t,'Y':pygame.K_y,'U':pygame.K_u,'I':pygame.K_i,'O':pygame.K_o,'P':pygame.K_p,
        'A':pygame.K_a,'S':pygame.K_s,'D':pygame.K_d,'F':pygame.K_f,'G':pygame.K_g,'H':pygame.K_h,'J':pygame.K_j,'K':pygame.K_k,'L':pygame.K_l,
        'Z':pygame.K_z,'X':pygame.K_x,'C':pygame.K_c,'V':pygame.K_v,'B':pygame.K_b,'N':pygame.K_n,'M':pygame.K_m,
        'UP':pygame.K_UP,'DOWN':pygame.K_DOWN,'LEFT':pygame.K_LEFT,'RIGHT':pygame.K_RIGHT,
    }

    __DEFAULT_KEYMAP = {
        'UP': pygame.K_UP,
        'DOWN': pygame.K_DOWN,
        'LEFT': pygame.K_LEFT,
        'RIGHT': pygame.K_RIGHT,
        'SELECT': pygame.K_c,
        'START': pygame.K_v,
        'B': pygame.K_x,
        'A': pygame.K_z,        
    }

    keyboard_setting_path = "keyboard.json"

    __TITLE = "KEYMAP"

    KEYMAP_EVENT_KEYS = ["-UP-", "-DOWN-", "-LEFT-", "-RIGHT-", "-SELECT-", "-START-", "-B-", "-A-"]

    ARROW_KEY_EVENTS = [
        ("<Up>", "+-UP_pressed-"),
        ("<Down>", "+-DOWN_pressed-"),
        ("<Left>", "+-LEFT_pressed-"),
        ("<Right>", "+-RIGHT_pressed-"),
    ]

    def __init__(self):
        self.__load()
        super().__init__(title = self.__TITLE,
                         finalize = True)
        self._events["APPLY"] = self.__save
            
    def __update_key(self, key, value) -> None:
        self._window[key].update(value)

    def __find_text(self, name: str) -> str:
        return [k for k, v in self.__MAPPING.items() if v == self.__keyboard[name]][0]

    def _layout(self) -> list:
        return [
            [
                sg.Text("↑", size = (2,1)), 
                sg.InputText(
                    default_text = self.__find_text("UP"), 
                    key = "-UP-", 
                    size = (6,1), 
                    enable_events = True), 
                sg.Text("SELECT", size = (7,1)), 
                sg.InputText(
                    default_text = self.__find_text("SELECT"), 
                    key = "-SELECT-", 
                    size = (6,1), 
                    enable_events = True),
            ],
            [
                sg.Text("↓", size = (2,1)), 
                sg.InputText(
                    default_text = self.__find_text("DOWN"), 
                    key = "-DOWN-", 
                    size = (6,1), 
                    enable_events = True), 
                sg.Text("  START", size = (7,1)), 
                sg.InputText(
                    default_text = self.__find_text("START"), 
                    key = "-START-", 
                    size = (6,1), 
                    enable_events = True),
            ],
            [
                sg.Text("←", size = (2,1)), 
                sg.InputText(
                    default_text = self.__find_text("LEFT"), 
                    key = "-LEFT-", 
                    size = (6,1), 
                    enable_events = True), 
                sg.Text("      B", size = (7,1)), 
                sg.InputText(
                    default_text = self.__find_text("B"), 
                    key = "-B-", 
                    size = (6,1), 
                    enable_events = True),
            ],
            [
                sg.Text("→", size = (2,1)), 
                sg.InputText(
                    default_text = self.__find_text("RIGHT"), 
                    key = "-RIGHT-", 
                    size = (6,1), 
                    enable_events = True), 
                sg.Text("      A", size = (7,1)), 
                sg.InputText(
                    default_text = self.__find_text("A"), 
                    key = "-A-", 
                    size = (6,1), 
                    enable_events = True),
            ],
            [sg.Button("Apply", key="APPLY")],
        ]
                
    def __validate(self, values) -> bool:
        setting = [ values[event_key] for event_key in self.KEYMAP_EVENT_KEYS ]
        if len(setting) != len(set(setting)):
            sg.popup('keyboard setting conflict!')
            return False
        for key in setting:
            if key not in self.__MAPPING.keys():
                sg.popup('not support {}!'.format(key))
                return False
        return True
    
    def __save(self, values):
        if not self.__validate(values):
            return
        self.__keyboard = {
            'UP': self.__MAPPING[values['-UP-']],
            'DOWN': self.__MAPPING[values['-DOWN-']],
            'LEFT': self.__MAPPING[values['-LEFT-']],
            'RIGHT': self.__MAPPING[values['-RIGHT-']],
            'SELECT': self.__MAPPING[values['-SELECT-']],
            'START': self.__MAPPING[values['-START-']],
            'B': self.__MAPPING[values['-B-']],
            'A': self.__MAPPING[values['-A-']],
        }
        with open(self.keyboard_setting_path, 'w') as keyboard:
            json.dump(self.__keyboard, keyboard)

    def __load(self) -> dict:
        if not os.path.exists(self.keyboard_setting_path):
            self.__keyboard = self.__DEFAULT_KEYMAP
        with open(self.keyboard_setting_path, 'r') as keyboard:
            self.__keyboard = json.load(keyboard)

    def _after_open(self) -> None:
        for event_key in self.KEYMAP_EVENT_KEYS:
            self._events[event_key] = (
                lambda event_key : lambda values : self.__update_key(event_key, str(values[event_key][-1]).upper())
            )(event_key)

        for key in self.KEYMAP_EVENT_KEYS:
            for arrow_key, event in self.ARROW_KEY_EVENTS:
                event_name = f"{key}{event}"
                event_func = (lambda key, event: lambda values: self.__update_key(key, event[2:-9]))(key, event)
                self._window[key].bind(arrow_key, event)
                self._events[event_name] = event_func
