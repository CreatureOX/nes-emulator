import json
import os
import sys
from pathlib import Path
from threading import Lock


def get_base_path():
    """Get the base path for the application (works in both development and packaged modes)"""
    if getattr(sys, 'frozen', False):
        return Path(sys._MEIPASS)
    return Path(__file__).resolve().parent.parent.parent


class KeyboardManager:
    """Global keyboard config manager, supports real-time loading of latest keyboard config"""
    
    _instance = None
    _lock = Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
        self._initialized = True
        self._keyboard_config = {}
        self._config_path = None
        self._callbacks = []
        self._reload()
    
    @staticmethod
    def get_keyboard_setting_path():
        """Get keyboard config file path"""
        base_path = get_base_path()
        user_config_path = Path.home() / "nes_emulator_keyboard.json"
        if user_config_path.exists():
            return str(user_config_path)
        return str(base_path / "keyboard.json")
    
    def set_config_path(self, path):
        """Set config file path"""
        self._config_path = path
    
    DEFAULT_KEYBOARD = {
        'UP': 273,
        'DOWN': 274,
        'LEFT': 276,
        'RIGHT': 275,
        'SELECT': 306,
        'START': 118,
        'B': 306,
        'A': 122,
    }
    
    def _reload(self):
        """Reload keyboard config from file"""
        path = self._config_path or self.get_keyboard_setting_path()
        try:
            if os.path.exists(path):
                with open(path, 'r') as f:
                    self._keyboard_config = json.load(f)
            else:
                self._keyboard_config = self.DEFAULT_KEYBOARD.copy()
        except Exception as e:
            print(f"[ERROR] Failed to load keyboard config: {e}")
            self._keyboard_config = self.DEFAULT_KEYBOARD.copy()
    
    def get_keyboard(self):
        """Get current keyboard config"""
        return self._keyboard_config.copy()
    
    def set_keyboard(self, keyboard_config):
        """Set and save keyboard config"""
        path = self._config_path or self.get_keyboard_setting_path()
        self._keyboard_config = keyboard_config
        
        try:
            with open(path, 'w') as f:
                json.dump(keyboard_config, f)
            
            # Trigger all registered callback functions
            for callback in self._callbacks:
                try:
                    callback(keyboard_config)
                except Exception as e:
                    print(f"[ERROR] Keyboard callback failed: {e}")
            
            return True
        except Exception as e:
            print(f"[ERROR] Failed to save keyboard config: {e}")
            return False
    
    def register_callback(self, callback):
        """Register callback function for keyboard changes"""
        if callback not in self._callbacks:
            self._callbacks.append(callback)
    
    def unregister_callback(self, callback):
        """Unregister callback function"""
        if callback in self._callbacks:
            self._callbacks.remove(callback)


# Global instance
keyboard_manager = KeyboardManager()