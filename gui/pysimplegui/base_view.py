import PySimpleGUI as sg
from typing import Callable


class BaseView:
    def __init__(self, 
                 title: str, 
                 size: tuple = (None, None), 
                 return_keyboard_events: bool = False,
                 resizable: bool = False, 
                 finalize: bool = False,
                 timeout: int = None):
        self._title = title
        self._size = size
        self._return_keyboard_events = return_keyboard_events
        self._resizable = resizable
        self._finalize = finalize
        self._timeout = timeout
        self._events = {
            'Exit' : self._before_exit
        }

    def _layout(self):
        raise NotImplementedError("_layout: not implemented")

    def _before_exit(self, values = None) -> None:
        pass
        
    def _process_event(self, event_name: str, values) -> None:
        if event_name is None:
            event_name = 'Exit'
        event_action = self._events[event_name]
        if event_action is None:
            return
        event_action(values)

    def process_events(self, values = None) -> None:
        while True:
            event_name, values = self._window.read(timeout = self._timeout)
            self._process_event(event_name, values)
            if event_name in (None, 'Exit'):
                break
        self._window.close()

    def _after_open(self) -> None:
        pass
    
    def open(self, values = None) -> None:
        self._window = sg.Window(title = self._title, 
                                 layout = self._layout(), 
                                 size = self._size, 
                                 return_keyboard_events = self._return_keyboard_events,
                                 resizable = self._resizable, 
                                 finalize = self._finalize)
        self._after_open()
        self.process_events()
