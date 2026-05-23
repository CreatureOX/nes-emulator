import json
import os
from pathlib import Path
from threading import Lock


class KeyboardManager:
    """全局键位配置管理器，支持实时加载最新的键位配置"""
    
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
        self._callbacks = []  # 键位变化时的回调函数列表
        self._reload()
    
    @staticmethod
    def get_keyboard_setting_path():
        """获取键位配置文件路径"""
        current_dir = Path(__file__).resolve().parent.parent.parent
        return str(current_dir / "keyboard.json")
    
    def set_config_path(self, path):
        """设置配置文件路径"""
        self._config_path = path
    
    def _reload(self):
        """从文件重新加载键位配置"""
        path = self._config_path or self.get_keyboard_setting_path()
        try:
            if os.path.exists(path):
                with open(path, 'r') as f:
                    self._keyboard_config = json.load(f)
        except Exception as e:
            print(f"[ERROR] Failed to load keyboard config: {e}")
    
    def get_keyboard(self):
        """获取当前键位配置（每次都重新读取文件以支持实时更新）"""
        self._reload()
        return self._keyboard_config.copy()
    
    def set_keyboard(self, keyboard_config):
        """设置并保存键位配置"""
        path = self._config_path or self.get_keyboard_setting_path()
        self._keyboard_config = keyboard_config
        
        try:
            with open(path, 'w') as f:
                json.dump(keyboard_config, f)
            
            # 触发所有注册的回调函数
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
        """注册键位变化时的回调函数"""
        if callback not in self._callbacks:
            self._callbacks.append(callback)
    
    def unregister_callback(self, callback):
        """取消注册回调函数"""
        if callback in self._callbacks:
            self._callbacks.remove(callback)


# 全局实例
keyboard_manager = KeyboardManager()
