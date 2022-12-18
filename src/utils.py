from numpy import uint16, uint8
import wrapt
from line_profiler import LineProfiler

def set_bit(v: uint8, index: int, bit: uint8) -> uint8:
    mask = uint8(1 << index)
    v &= ~mask
    return v | mask if bit == 1 else v

def get_bit(v: uint8, index: int) -> uint8:
    mask = uint8(1 << index)
    return (v & mask) >> index

def set_bit(v: uint16, index: int, bit: uint16) -> uint16:
    mask = uint16(1 << index)
    v &= ~mask
    return v | mask if bit == 1 else v

def get_bit(v: uint16, index: int) -> uint16:
    mask = uint16(1 << index)
    return (v & mask) >> index

lp = LineProfiler()
 
def profiler():
    @wrapt.decorator
    def wrapper(func, instance, args, kwargs):
        global lp
        lp_wrapper = lp(func)
        res = lp_wrapper(*args, **kwargs)
        lp.print_stats()
        return res
 
    return wrapper