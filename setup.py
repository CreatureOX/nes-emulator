from setuptools import Command, setup
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
        "nes/mapper/mirror.pyx",
        "nes/mapper/mapping.pyx",
        "nes/mapper/mapper.pyx",
        "nes/mapper/mapper_nrom.pyx",
        "nes/mapper/mapper_mmc1.pyx",
        "nes/mapper/mapper_uxrom.pyx",
        "nes/mapper/mapper_mmc3.pyx",
        "nes/mapper/mapper_ines003.pyx",
        "nes/mapper/mapper_gxrom.pyx",
        "nes/mapper/mapper_factory.pyx",
        "nes/cart/cart.pyx",
        "nes/cart/cart_ines.pyx",
        "nes/cart/cart_nes2.pyx",
        "nes/cart/cart_debug.pyx",
        "nes/file_loader.pyx",
        "nes/bus/bus.pyx",
        "nes/cpu/cpu_registers.pyx",
        "nes/cpu/cpu_op.pyx",
        "nes/cpu/cpu.pyx",
        "nes/cpu/cpu_debug.pyx",
        "nes/ppu/ppu.pyx",
        "nes/ppu/ppu_registers.pyx",
        "nes/ppu/ppu_sprite.pyx",
        "nes/ppu/ppu_debug.pyx",
        "nes/apu/apu_registers.pyx",
        "nes/apu/apu.pyx",
        "nes/console.pyx",
    ], compiler_directives={'language_level' : "3"}, 
    annotate=True),
    include_dirs=[np.get_include()]
)
