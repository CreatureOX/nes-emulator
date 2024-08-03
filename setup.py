from setuptools import Command, setup
from Cython.Build import cythonize
import numpy as np
import os
import glob


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
    name="nes",
    packages=['nes'],
    package_dir={'nes': 'nes'},
    cmdclass = {
        "clean": Clean
    },
    ext_modules = cythonize(glob.glob('nes/**/*.pyx', recursive = True), 
                          compiler_directives = {'language_level' : "3"}, 
                          annotate = True),
    include_dirs = [np.get_include()]
)
