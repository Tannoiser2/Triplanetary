import json
from PIL import Image, ImageDraw
from lattice import *
m=json.load(open('../data/map.json'))
im=Image.open(IMG).convert('RGB'); d=ImageDraw.Draw(im)
def px(q,r):
    row=r; col=q+(r-(r&1))//2
    return center(col,row)
def vec(a): return (a[0]*W_HEX + a[1]*W_HEX/2, a[1]*ROW)
for k,lst in m['gravity'].items():
    q,r=map(int,k.split(',')); x,y=px(q,r)
    for i,g in enumerate(lst):
        vx,vy=vec(g['acc']); off=(i-(len(lst)-1)/2)*8
        col=(0,160,255) if g['weak'] else (255,0,0)
        d.line((x+off-vx*0.25,y+off-vy*0.25,x+off+vx*0.3,y+off+vy*0.3),fill=col,width=4)
        d.ellipse((x+off+vx*0.3-5,y+off+vy*0.3-5,x+off+vx*0.3+5,y+off+vy*0.3+5),fill=col)
for b in m['bodies']:
    x,y=px(*b['hex'])
    for s in b['base_sides']:
        dirs=[(1,0),(1,-1),(0,-1),(-1,0),(-1,1),(0,1)]
        vx,vy=vec(dirs[s]); d.rectangle((x+vx*0.5-6,y+vy*0.5-6,x+vx*0.5+6,y+vy*0.5+6),fill=(255,0,255))
for q,r in m['asteroids']:
    x,y=px(q,r); d.ellipse((x-8,y-8,x+8,y+8),outline=(0,200,0),width=3)
im.resize((1240,1754)).save('/tmp/claude-0/shots/verify.png')
for name,(c0,r0,c1,r1) in {'v_sol':(11,43,20,52),'v_jup':(11,5,23,15),'v_tl':(22,37,31,44)}.items():
    x0,y0=center(c0,r0);x1,y1=center(c1,r1); im.crop((int(x0),int(y0),int(x1),int(y1))).save(f'/tmp/claude-0/shots/{name}.png')
