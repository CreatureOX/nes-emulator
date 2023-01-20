import wrapt
from line_profiler import LineProfiler
import cProfile
import pstats

lp = LineProfiler()
 
def LProfiler():
    @wrapt.decorator
    def wrapper(func, instance, args, kwargs):
        global lp
        lp_wrapper = lp(func)
        res = lp_wrapper(*args, **kwargs)
        lp.print_stats()
        return res
 
    return wrapper

def CProfiler(dump = False, sortby = 'tottime'):
    def wrapper(func):
        def profiled_func(*args, **kwargs):
            profile = cProfile.Profile()
            profile.enable()
            result = func(*args, **kwargs)
            profile.disable()
            ps = pstats.Stats(profile).sort_stats(sortby)
            ps.print_stats()
            if dump:
                ps.dump_stats(func.__name__)
            return result
        return profiled_func
    return wrapper
