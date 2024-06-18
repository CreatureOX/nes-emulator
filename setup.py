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

setup(
    cmdclass={
        "clean": Clean
    },
    ext_modules=cythonize([
        Extension("mirror", sources=["./nes/mirror.pyx"]),
        Extension("mapper", sources=["./nes/mapper.pyx"]),
        Extension("cartridge", sources=["./nes/cartridge.pyx"]),
        Extension("bus", sources=["./nes/bus.pyx"]),
        Extension("cpu_registers", sources=["./nes/cpu_registers.pyx"]),
        Extension("cpu_op", sources=["./nes/cpu_op.pyx"]),
        Extension("cpu", sources=["./nes/cpu.pyx"]),
        Extension("ppu", sources=["./nes/ppu.pyx"]),
        Extension("ppu_registers", sources=["./nes/ppu_registers.pyx"]),
        Extension("ppu_sprite", sources=["./nes/ppu_sprite.pyx"]),
        Extension("ppu_debug", sources=["./nes/ppu_debug.pyx"]),
        Extension("apu", sources=["./nes/apu.pyx"]),
        Extension("console", sources=["./nes/console.pyx"]),
    ], compiler_directives={'language_level' : "3"}, 
    annotate=True),
    include_dirs=[np.get_include()]
)
