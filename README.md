# nes-emulator
| Donkey Kong (World) (Rev A).nes | Legend of Zelda, The (U) (PRG1) [!].nes | Mega Man (USA).nes |
| ------------------------------- | --------------------------------------- | ------------------ |
| <img src="images/Donkey%20Kong%20(World)%20(Rev%20A).gif"/> | <img src="images/Legend%20of%20Zelda%2C%20The%20(U)%20(PRG1)%20%5B!%5D.gif"/> | <img src="images/Mega%20Man%20(USA).nes.gif"/>

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
      <td>MMC3</td>
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



