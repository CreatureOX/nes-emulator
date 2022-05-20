import unittest

from src.bus import Bus
from src.cpu import CPU6502


class TestCPU(unittest.TestCase):
    def test_connectBus(self):
        bus = Bus()
        cpu = CPU6502()
        cpu.connectBus(bus)

    def test_write_read(self):
        bus = Bus()
        cpu = CPU6502()
        cpu.connectBus(bus)
        cpu.write(0x00FF, 1)
        self.assertEqual(cpu.read(0x00FF), 1, "cpu read write test failed")   

    def test_set_get_flag(self):
        cpu = CPU6502()
        for flag in cpu.FLAGS:
            cpu.setFlag(flag, True)
            self.assertEqual(cpu.getFlag(flag), 1, "set get flag {flag}".format(flag = flag.name))

if __name__ == '__main__':
    unittest.main()
