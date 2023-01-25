from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy as np
import os

os.chdir("./src") 

setup(
    ext_modules=cythonize([
        Extension("mapper", sources=["./mapper.py"]),
        Extension("cartridge", sources=["./cartridge.py"]),
        Extension("bus", sources=["./bus.py"]),
        Extension("cpu", sources=["./cpu.py"]),
        Extension("ppu", sources=["./ppu.py"]),
        Extension("console", sources=["./console.py"]),
    ], compiler_directives={'language_level' : "3"}, 
    annotate=True),
    include_dirs=[np.get_include()]
)
