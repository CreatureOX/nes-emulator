import unittest

from src.bus import Bus


class TestBus(unittest.TestCase):
    def test_write_read(self):
        bus = Bus()
        bus.write(0x00FF, 1)
        self.assertEqual(bus.read(0x00FF, False), 1, "bus read write test failed")

if __name__ == '__main__':
    unittest.main()
    