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

os.chdir("./src") 

setup(
    cmdclass={
        "clean": Clean
    },
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
