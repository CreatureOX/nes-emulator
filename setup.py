from setuptools import Command, setup, Extension
from Cython.Build import cythonize
import numpy as np
import os

class Clean(Command):
    description = "Clean cythonized products"
    user_options = [('dir=', None, 'Specify the folder to clean')]

    def initialize_options(self) -> None:
        pass

    def finalize_options(self) -> None:
        pass

    def run(self) -> None:
        walks = os.walk(r'.')
        for dirpath, dirnames, filenames in walks:
            for filename in filenames:
                if filename.endswith(".pyd") \
                    or filename.endswith(".c") \
                    or filename.endswith(".h") \
                    or filename.endswith(".html"):
                    os.remove(dirpath + "\\" + filename)

os.chdir("./nes") 

setup(
    cmdclass={
        "clean": Clean
    },
    ext_modules=cythonize([
        Extension("mirror", sources=["./mirror.pyx"]),
        Extension("mapper", sources=["./mapper.pyx"]),
        Extension("cartridge", sources=["./cartridge.pyx"]),
        Extension("bus", sources=["./bus.pyx"]),
        Extension("cpu", sources=["./cpu.pyx"]),
        Extension("ppu", sources=["./ppu.pyx"]),
        Extension("apu", sources=["./apu.pyx"]),
        Extension("console", sources=["./console.pyx"]),
    ], compiler_directives={'language_level' : "3"}, 
    annotate=True),
    include_dirs=[np.get_include()]
)
