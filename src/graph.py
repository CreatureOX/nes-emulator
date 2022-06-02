from typing import List
from matplotlib import pyplot as plt

from numpy import array, ndarray, uint8, zeros


class Pixel:
    r: uint8
    g: uint8
    b: uint8

    rgb: ndarray

    def __init__(self, r: uint8, g: uint8, b: uint8) -> None:
        self.r, self.g, self.b = r, g, b
        self.rgb = array((r, g, b)).reshape(1, 1, 3)

    def show(self) -> None:
        plt.imshow(self.rgb)
        plt.axis('off')
        plt.show()

class Sprite:
    width: uint8
    height: uint8
    matrix: List[List[Pixel]]

    rgb: ndarray

    def __init__(self, width: uint8, height: uint8) -> None:
        self.width, self.height = width, height
        self.matrix = [[None] * width] * height
        self.rgb = zeros((width, height, 3)).astype(uint8)

    def setPixel(self, x: uint8, y: uint8, pixel: Pixel) -> None:
        self.matrix[x][y] = pixel
        self.rgb[x][y][0], self.rgb[x][y][1], self.rgb[x][y][2] = pixel.r, pixel.g, pixel.b

    def show(self) -> None:
        plt.imshow(self.rgb)
        plt.axis('off')
        plt.show()
  