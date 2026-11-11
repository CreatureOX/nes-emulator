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
1. `pip install -r requirements.txt`
2. `python setup.py build_ext --inplace`
3. `python .\nes-emulator.py`

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
      <td></td>
      <td></td>
      <td>AxROM <input type="checkbox" checked></td>
      <td></td>
      <td></td>
      <td></td>
      <td>Color Dreams <input type="checkbox" checked></td>
      <td></td>
      <td></td>
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
      <th>0x2X</th>
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
      <td></td>
      <td></td>
      <td>GxROM <input type="checkbox" checked></td>
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
  </tbody>
</table>

Implemented: 0 (NROM), 1 (MMC1), 2 (UxROM), 3 (CNROM), 4 (MMC3), 7 (AxROM),
11 (Color Dreams), 66 (GxROM). The authoritative list is the `mappers`
registry in `nes/mapper/mapper_factory.pyx`. Adding a board keeps four
places in sync: that registry, the checked cell above, this list, and
`SUPPORTED_MAPPERS` in `tests/rom_scanner.py`. ROMs whose mapper is not
checked above cannot be loaded yet.
