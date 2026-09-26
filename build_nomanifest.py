"""Build Cython extensions without embedding a manifest.

On this toolchain `link.exe` fails with LNK1158 (cannot run rc.exe) when it
tries to embed a manifest. Disabling manifest embedding avoids rc.exe entirely
while producing identical runtime behaviour for our extension modules.
"""
from setuptools import Command, setup
from setuptools.command.build_ext import build_ext as _build_ext
from Cython.Build import cythonize
import numpy as np
import os
import glob


class build_ext(_build_ext):
    def build_extension(self, ext):
        compiler = self.compiler
        if compiler is not None and hasattr(compiler, "link_shared_object"):
            orig_lso = compiler.link_shared_object

            def patched_link_shared_object(objects, output_filename,
                                           output_dir=None, libraries=None,
                                           library_dirs=None,
                                           runtime_library_dirs=None,
                                           export_symbols=None, debug=False,
                                           extra_preargs=None, extra_postargs=None,
                                           build_temp=None, target_lang=None):
                if extra_postargs is None:
                    extra_postargs = []
                else:
                    extra_postargs = list(extra_postargs)
                # Last /MANIFEST option wins: NO overrides the compiler's
                # default /MANIFEST:EMBED,ID=2 so rc.exe is never invoked.
                extra_postargs.append("/MANIFEST:NO")
                return orig_lso(objects, output_filename, output_dir, libraries,
                                library_dirs, runtime_library_dirs, export_symbols,
                                debug, extra_preargs, extra_postargs,
                                build_temp, target_lang)
            compiler.link_shared_object = patched_link_shared_object

            compiler.link_shared_object = patched_link_shared_object
        _build_ext.build_extension(self, ext)


setup(
    name="nes",
    packages=["nes"],
    package_dir={"nes": "nes"},
    cmdclass={"build_ext": build_ext},
    ext_modules=cythonize(
        glob.glob("nes/**/*.pyx", recursive=True),
        compiler_directives={"language_level": "3"},
        annotate=True,
        include_path=["nes/cpu", "nes/bus", "nes/ppu", "nes/cart",
                      "nes/mapper", "nes/mapper/impl", "nes"],
    ),
    include_dirs=[
        np.get_include(),
        "nes/cpu", "nes/bus", "nes/ppu", "nes/cart",
        "nes/mapper", "nes/mapper/impl", "nes",
    ],
)
