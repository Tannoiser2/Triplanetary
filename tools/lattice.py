import numpy as np
from PIL import Image
W_HEX=69.314; ROW=52.094; X0E=58.66; X0O=93.32; Y0=62.5
import os
IMG=os.path.join(os.path.dirname(os.path.abspath(__file__)),'reference','triplanetary-map-a4-starkiel-v1.jpg')
def center(col,row):
    x=(X0O if row&1 else X0E)+col*W_HEX
    return x, Y0+row*ROW
def cells():
    for row in range(66):
        n = 34 if row&1 else 35
        for col in range(n): yield col,row
