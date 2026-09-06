import re, json, math
SRC = '/Users/iliao/Projects/Pixel-staff/Hardware/Electronics/kicad/kicad.kicad_pcb'
src = open(SRC).read()

def blocks(tok, s):
    out = []; idx = 0; pat = '(' + tok + ' '
    while True:
        j = s.find(pat, idx)
        if j < 0:
            break
        k = j; depth = 0; st = False
        while k < len(s):
            c = s[k]
            if c == '(':
                depth += 1; st = True
            elif c == ')':
                depth -= 1
                if st and depth == 0:
                    break
            k += 1
        out.append(s[j:k+1]); idx = k + 1
    return out

def rot(px, py, ang):
    a = math.radians(ang); c = math.cos(a); si = math.sin(a)
    return px*c - py*si, px*si + py*c

data = {}
for b in blocks('footprint', src):
    ref = re.search(r'\(property "Reference" "([^"]*)"', b)
    at = re.search(r'\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)', b)
    if not (ref and at):
        continue
    r = ref.group(1)
    ox, oy, ang = float(at.group(1)), float(at.group(2)), float(at.group(3) or 0)
    nets = set()
    for pd in blocks('pad', b):
        nm = re.search(r'\(net \d+ "([^"]*)"', pd)
        if nm:
            nets.add(nm.group(1))
    pts = []
    cy = [x for x in blocks('fp_poly', b) + blocks('fp_line', b) + blocks('fp_rect', b) if 'CrtYd' in x]
    if cy:
        for seg in cy:
            for mm in re.finditer(r'\((?:start|end|xy) ([-\d.]+) ([-\d.]+)\)', seg):
                pts.append((float(mm.group(1)), float(mm.group(2))))
    else:
        for pd in blocks('pad', b):
            m2 = re.search(r'\(at ([-\d.]+) ([-\d.]+)', pd)
            sz = re.search(r'\(size ([-\d.]+) ([-\d.]+)\)', pd)
            if m2 and sz:
                px, py = float(m2.group(1)), float(m2.group(2))
                sx, sy = float(sz.group(1))/2, float(sz.group(2))/2
                pts += [(px-sx, py-sy), (px+sx, py+sy), (px-sx, py+sy), (px+sx, py-sy)]
    # pad-only extent (copper), useful for narrow-neck sizing
    ppts = []
    for pd in blocks('pad', b):
        m2 = re.search(r'\(at ([-\d.]+) ([-\d.]+)', pd)
        sz = re.search(r'\(size ([-\d.]+) ([-\d.]+)\)', pd)
        if m2 and sz:
            px, py = float(m2.group(1)), float(m2.group(2))
            sx, sy = float(sz.group(1))/2, float(sz.group(2))/2
            ppts += [(px-sx, py-sy), (px+sx, py+sy), (px-sx, py+sy), (px+sx, py-sy)]
    gx = []; gy = []
    for px, py in pts:
        rx, ry = rot(px, py, ang); gx.append(rx); gy.append(ry)
    px_ = []; py_ = []
    for a_, b_ in ppts:
        rx, ry = rot(a_, b_, ang); px_.append(rx); py_.append(ry)
    if gx:
        hw = (max(gx)-min(gx))/2; hh = (max(gy)-min(gy))/2
        cx = (max(gx)+min(gx))/2; cyy = (max(gy)+min(gy))/2
    else:
        hw = hh = cx = cyy = 0
    pad_hw = (max(px_)-min(px_))/2 if px_ else 0
    pad_hh = (max(py_)-min(py_))/2 if py_ else 0
    data[r] = dict(x=round(ox,3), y=round(oy,3), rot=ang,
                   hw=round(hw,3), hh=round(hh,3),
                   offx=round(cx,3), offy=round(cyy,3),
                   pad_hw=round(pad_hw,3), pad_hh=round(pad_hh,3),
                   nets=sorted(nets))
json.dump(data, open('/tmp/fp_data.json','w'), indent=0)
for r in sorted(data):
    d = data[r]
    print("%-5s rot=%-5g court=%5.2fx%-5.2f pads=%5.2fx%-5.2f off=(%.2f,%.2f)" %
          (r, d['rot'], 2*d['hw'], 2*d['hh'], 2*d['pad_hw'], 2*d['pad_hh'], d['offx'], d['offy']))
