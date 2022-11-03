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
        self.rgb = zeros((height, width, 3)).astype(uint8)

    def setPixel(self, x: uint8, y: uint8, pixel: Pixel) -> None:
        if (x < 0 or x >= self.width) or (y < 0 or y >= self.height):
            return
        self.matrix[y][x] = pixel
        self.rgb[y][x][0], self.rgb[y][x][1], self.rgb[y][x][2] = pixel.r, pixel.g, pixel.b

    def show(self) -> None:
        plt.imshow(self.rgb)
        plt.axis('off')
        plt.show()

    def save(self, name: str) -> None:
        plt.imsave(name, self.rgb)

    def toString(self) -> str:
        string = ""
        for i in range(self.height):
            for j in range(self.width):
                string += "{r} {g} {b}".format(r=self.rgb[i][j][0], g=self.rgb[i][j][1], b=self.rgb[i][j][2])
                string += ","
            string += "\n"
        return string
  