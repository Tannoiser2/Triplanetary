"""Genera data/map.json dalla trascrizione della mappa A4 di starkiel.

Sistema di riferimento: reticolo dell'immagine verticale (esagoni a punta in su,
righe dispari spostate a destra, "odd-r"). Coordinate assiali: q = col - (row - row%2)/2, r = row.
Direzioni assiali (E, NE, NW, W, SW, SE) = (1,0) (1,-1) (0,-1) (-1,0) (-1,1) (0,1).
"""
import json, os
from lattice import cells

DIRS = [(1,0),(1,-1),(0,-1),(-1,0),(-1,1),(0,1)]
DNAME = ['E','NE','NW','W','SW','SE']

def ax(col,row):
    return [col - (row - (row & 1)) // 2, row]

# id, nome, (col,row), gravità ('full'|'weak'|None), raggio disco (in unità di apotema), lati con base, colore
BODIES = [
    ('sol','Sol',(15,47),'sol',0.74,[],'#ffb347'),
    ('mercury','Mercurio',(18,51),'full',0.36,['NE','SW'],'#b9876a'),
    ('venus','Venere',(9,51),'full',0.42,DNAME,'#e9c98a'),
    ('terra','Terra',(25,41),'full',0.46,DNAME,'#3f86d8'),
    ('luna','Luna',(28,40),'weak',0.32,DNAME,'#c9ccd6'),
    ('mars','Marte',(6,27),'full',0.40,DNAME,'#d0573a'),
    ('jupiter','Giove',(17,11),'full',0.60,[],'#d9b48a'),
    ('io','Io',(18,13),'weak',0.32,['SW'],'#e6b44a'),
    ('europa','Europa',(17,8),'weak',0.30,[],'#d8dde6'),
    ('ganymede','Ganimede',(20,9),'full',0.36,['E'],'#9a8f84'),
    ('callisto','Callisto',(13,11),'full',0.36,DNAME,'#7b6b5d'),
    ('ceres','Ceres',(10,20),None,0.0,['IN'],'#a59a8a'),
    ('clandestine','Clandestine',(26,21),None,0.0,['IN'],'#8fa7c9'),
]
ASTEROIDS = [(0,17),(1,17),(2,18),(0,19),(1,19),(3,19),(21,19),(6,20),(8,20),(11,20),(23,20),(30,20),(2,21),(4,21),(5,21),(20,21),(28,21),(31,21),(32,21),(33,21),(2,22),(16,22),(19,22),(21,22),(23,22),(24,22),(29,22),(0,23),(1,23),(2,23),(11,23),(13,23),(23,23),(31,23),(2,24),(13,24),(16,24),(17,24),(18,24),(20,24),(30,24),(33,24),(34,24),(11,25),(15,25),(16,25),(19,25),(22,25),(24,25),(26,25),(28,25),(30,25),(31,25),(14,26),(16,26),(19,26),(22,26),(25,26),(28,26),(31,26),(12,27),(16,27),(19,27),(21,27),(22,27),(14,28),(16,28)]
SPECIAL = [(26,20),(27,20),(25,21),(27,21),(26,22),(27,22),(26,23)]

def add(a,b,k=1): return [a[0]+b[0]*k, a[1]+b[1]*k]
def neg(d): return [-d[0], -d[1]]

valid = [ax(c,r) for c,r in cells()]
validset = {tuple(v) for v in valid}
gravity = {}  # "q,r" -> lista di {acc:[x,y], weak:bool, body:id}
def put(h, acc, weak, body):
    if tuple(h) not in validset: return
    gravity.setdefault(f'{h[0]},{h[1]}', []).append({'acc': list(acc), 'weak': weak, 'body': body})

bodies = []
for bid,name,cr,grav,radius,sides,color in BODIES:
    h = ax(*cr)
    b = {'id':bid,'name':name,'hex':h,'gravity':grav or 'none','radius':radius,'color':color,
         'base_sides':[DNAME.index(s) for s in sides if s!='IN'], 'asteroid_base': 'IN' in sides}
    bodies.append(b)
    if grav in ('full','weak'):
        for i,d in enumerate(DIRS):
            put(add(h,d), neg(d), grav=='weak', bid)
    elif grav == 'sol':
        for i,d in enumerate(DIRS):
            # anello interno: freccia doppia (due accelerazioni)
            put(add(h,d), neg(d), False, bid); put(add(h,d), neg(d), False, bid)
            gravity[f'{add(h,d)[0]},{add(h,d)[1]}'][-1]['inner_extra'] = True
            # anello esterno: angoli con una freccia, lati con due frecce divergenti
            put(add(h,d,2), neg(d), False, bid)
            d2 = DIRS[(i+1)%6]
            edge = add(add(h,d), d2)
            put(edge, neg(d), False, bid); put(edge, neg(d2), False, bid)
            gravity[f'{edge[0]},{edge[1]}'][-1]['outer_pair'] = True
            gravity[f'{edge[0]},{edge[1]}'][-2]['outer_pair'] = True
        for d in DIRS:
            for k in (2,):
                gravity[f'{add(h,d,k)[0]},{add(h,d,k)[1]}'][-1]['outer_corner'] = True

out = {
    'source': 'Triplanetary_map_A4_starkiel_v1.jpg (trascrizione a reticolo, verificata a vista)',
    'orientation': 'pointy_odd_r_image; la UI ruota di 90 gradi in senso orario',
    'rows': 66, 'columns_even': 35, 'columns_odd': 34,
    'cells': valid,
    'bodies': bodies,
    'gravity': gravity,
    'asteroids': [ax(c,r) for c,r in ASTEROIDS],
    'special_asteroids': [ax(c,r) for c,r in SPECIAL],
    'jupiter_edge': 'r<0',
    'detector_range_base': 5, 'detector_range_ship': 3,
}
dst = os.path.join(os.path.dirname(__file__), '..', 'data', 'map.json')
json.dump(out, open(dst,'w'), separators=(',',':'))
print('celle', len(valid), 'esagoni gravità', len(gravity), 'asteroidi', len(ASTEROIDS), 'speciali', len(SPECIAL))
