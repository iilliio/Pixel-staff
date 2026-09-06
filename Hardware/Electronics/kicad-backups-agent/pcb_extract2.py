import re, json, math
SRC = '/Users/iliao/Projects/Pixel-staff/Hardware/Electronics/kicad/kicad.kicad_pcb'
src = open(SRC).read()

def blocks(tok, s):
    out = []; idx = 0
    pat = re.compile(r'\(' + tok + r'(?=[\s)])')
    while True:
        m = pat.search(s, idx)
        if not m:
            break
        j = m.start()
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

def krot(x, y, ang):
    """KiCad footprint child -> parent transform (verified against DRC)."""
    a = math.radians(ang); c = math.cos(a); s = math.sin(a)
    return (x*c + y*s, -x*s + y*c)

data = {}
for b in blocks('footprint', src):
    ref = re.search(r'\(property "Reference" "([^"]*)"', b)
    at = re.search(r'\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)', b)
    if not (ref and at):
        continue
    r = ref.group(1)
    ang = float(at.group(3) or 0)

    nets = set()
    for pd in blocks('pad', b):
        nm = re.search(r'\(net \d+ "([^"]*)"', pd)
        if nm:
            nets.add(nm.group(1))

    court = []   # local courtyard pts
    for seg in blocks('fp_line', b) + blocks('fp_rect', b) + blocks('fp_poly', b) \
             + blocks('fp_arc', b) + blocks('fp_circle', b):
        if 'CrtYd' not in seg:
            continue
        pts = [(float(m.group(1)), float(m.group(2)))
               for m in re.finditer(r'\((?:start|end|mid|xy|center) ([-\d.]+) ([-\d.]+)\)', seg)]
        if seg.startswith('(fp_circle'):
            cm = re.search(r'\(center ([-\d.]+) ([-\d.]+)\)', seg)
            em = re.search(r'\(end ([-\d.]+) ([-\d.]+)\)', seg)
            if cm and em:
                cx, cy = float(cm.group(1)), float(cm.group(2))
                ex, ey = float(em.group(1)), float(em.group(2))
                rad = math.hypot(ex-cx, ey-cy)
                pts = [(cx-rad, cy-rad), (cx+rad, cy+rad), (cx-rad, cy+rad), (cx+rad, cy-rad)]
        elif seg.startswith('(fp_rect'):
            if len(pts) >= 2:
                (x1, y1), (x2, y2) = pts[0], pts[1]
                pts = [(x1, y1), (x2, y2), (x1, y2), (x2, y1)]
        court += pts

    pads = []    # local pad corner pts
    for pd in blocks('pad', b):
        m2 = re.search(r'\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)', pd)
        sz = re.search(r'\(size ([-\d.]+) ([-\d.]+)\)', pd)
        if not (m2 and sz):
            continue
        px, py = float(m2.group(1)), float(m2.group(2))
        pang = float(m2.group(3) or 0)
        sx, sy = float(sz.group(1))/2, float(sz.group(2))/2
        for dx, dy in [(-sx,-sy), (sx,-sy), (sx,sy), (-sx,sy)]:
            rx, ry = krot(dx, dy, pang)
            pads.append((px+rx, py+ry))

    def extent(pts):
        if not pts:
            return None
        gx = []; gy = []
        for px, py in pts:
            rx, ry = krot(px, py, ang)
            gx.append(rx); gy.append(ry)
        return min(gx), max(gx), min(gy), max(gy)

    ec = extent(court); ep = extent(pads)
    # union of courtyard and pads = safe body extent
    cand = [e for e in (ec, ep) if e]
    if not cand:
        continue
    x0 = min(e[0] for e in cand); x1 = max(e[1] for e in cand)
    y0 = min(e[2] for e in cand); y1 = max(e[3] for e in cand)

    data[r] = dict(
        rot=ang,
        hw=round((x1-x0)/2, 4), hh=round((y1-y0)/2, 4),
        offx=round((x1+x0)/2, 4), offy=round((y1+y0)/2, 4),
        pad_hw=round((ep[1]-ep[0])/2, 4) if ep else 0,
        pad_hh=round((ep[3]-ep[2])/2, 4) if ep else 0,
        pad_offx=round((ep[1]+ep[0])/2, 4) if ep else 0,
        pad_offy=round((ep[3]+ep[2])/2, 4) if ep else 0,
        nets=sorted(nets))

json.dump(data, open('/tmp/fp_data2.json','w'), indent=0)
print("%-5s %6s %14s %16s" % ("ref", "rot", "extent(WxH)", "offset"))
for r in sorted(data):
    d = data[r]
    print("%-5s %6g  %6.2f x %-6.2f  (%6.2f, %6.2f)"
          % (r, d['rot'], 2*d['hw'], 2*d['hh'], d['offx'], d['offy']))
