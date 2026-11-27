<h1 align="center">
  FanNes<br/>
  <img src="https://i.postimg.cc/SQ1nwcTW/full-icon.png" width="256"/>
</h1>

| Donkey Kong (World) (Rev A).nes | Legend of Zelda, The (U) (PRG1) [!].nes | Mega Man (USA).nes |
| ------------------------------- | --------------------------------------- | ------------------ |
| <img src="https://i.postimg.cc/d1yJpTLk/Donkey-Kong-(World)-(Rev-A).gif"/> | <img src="https://i.postimg.cc/T33fGsKm/Legend-of-Zelda-The-(U)-(PRG1).gif"/> | <img src="https://i.postimg.cc/qMkdXFXh/Mega-Man-(USA)-nes.gif"/>

## Introduction
A Nes Emulator implemented by Python & Cython

For more details, check `setup.py`

## Installation

Python 3.8 or newer is required (Cython 3 needs 3.8+). A C compiler is
needed to build the Cython extensions. On Windows, the Visual C++ build tools
must include the Windows SDK.

1. Install the Python dependencies:

   ```sh
   pip install -r requirements.txt
   ```

2. Build the Cython extensions in place:

   ```sh
   python setup.py build_ext --inplace
   ```

   If linking fails on Windows with `LNK1158: cannot run rc.exe`, use the
   alternate build script, which skips manifest embedding:

   ```sh
   python build_nomanifest.py build_ext --inplace
   ```

3. Launch the emulator:

   ```sh
   python nes-emulator.py
   ```

The test ROMs live in a git submodule. Only fetch them when you intend to run
the ROM gate:

```sh
git submodule update --init
python tests/launcher.py
```

## Support Mapper
<table border="1">
  <thead>
    <tr>
      <th>&nbsp;</th>
      <th>0</th>
      <th>1</th>
      <th>2</th>
      <th>3</th>
      <th>4</th>
      <th>5</th>
      <th>6</th>
      <th>7</th>
      <th>8</th>
      <th>9</th>
      <th>A</th>
      <th>B</th>
      <th>C</th>
      <th>D</th>
      <th>E</th>
      <th>F</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <th>0x0X</th>
      <td>NROM <input type="checkbox" checked></td>
      <td>MMC1 <input type="checkbox" checked></td>
      <td>UxROM <input type="checkbox" checked></td>
      <td>INES Mapper 003 <input type="checkbox" checked></td>
      <td>MMC3 <input type="checkbox" checked></td>
      <td>MMC5 <input type="checkbox" checked></td>
      <td></td>
      <td>AxROM <input type="checkbox" checked></td>
      <td>MMC2 <input type="checkbox" checked></td>
      <td>MMC4 <input type="checkbox" checked></td>
      <td></td>
      <td>Color Dreams <input type="checkbox" checked></td>
      <td></td>
      <td>CPROM <input type="checkbox" checked></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <th>0x1X</th>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>VRC2a <input type="checkbox" checked></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>Action 53 <input type="checkbox" checked></td>
      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <th>0x2X</th>
      <td></td>
      <td></td>
      <td>BNROM <input type="checkbox" checked></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <th>0x3X</th>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
    </tr>
    <tr>
      <th>0x4X</th>
      <td>RAMBO-1 <input type="checkbox" checked></td>
      <td></td>
      <td>GxROM <input type="checkbox" checked></td>
      <td></td>
      <td></td>
      <td>FME-7 <input type="checkbox" checked></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td></td>
      <td>INES 078 <input type="checkbox" checked></td>
      <td></td>
    </tr>
  </tbody>
</table>

Implemented: 0 (NROM), 1 (MMC1), 2 (UxROM), 3 (CNROM), 4 (MMC3), 5 (MMC5),
7 (AxROM), 9 (MMC2), 10 (MMC4), 11 (Color Dreams), 13 (CPROM), 22 (VRC2a),
28 (Action 53), 34 (BNROM), 64 (RAMBO-1), 66 (GxROM), 69 (FME-7), 78 (Irem
74HC161/32), 118 (TKSROM/TLSROM), 180 (Crazy Climber). The authoritative list
is the `mappers` registry in `nes/mapper/mapper_factory.pyx`; the checked
cells above and this list follow it. The table covers mappers 0-79, so 118
and 180 appear only in this list. `SUPPORTED_MAPPERS` in
`tests/rom_scanner.py` is the frozen ROM gate and still excludes mapper 5.
ROMs whose mapper is not listed here cannot be loaded yet.
