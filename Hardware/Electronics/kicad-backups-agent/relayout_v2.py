import re, json, sys

SRC_BASE = '/Users/iliao/Projects/Pixel-staff/Hardware/Electronics/kicad-backups-agent/kicad_20260801-161122_before-neck.kicad_pcb'
OUT = '/tmp/necked_v2.kicad_pcb'
data = json.load(open('/tmp/fp_data2.json'))
s = open(SRC_BASE).read()

def fb(s, st):
    k = st; d = 0; b = False
    while k < len(s):
        if s[k] == '(':
            d += 1; b = True
        elif s[k] == ')':
            d -= 1
            if b and d == 0:
                return k
        k += 1

# ---- 1. remove mounting holes ----
for ref in ['H1', 'H2', 'H3', 'H4']:
    pm = re.search(r'\(property "Reference" "%s"' % ref, s)
    if not pm:
        continue
    fstart = s.rfind('\n\t(footprint', 0, pm.start())
    fend = fb(s, fstart + 1)
    s = s[:fstart] + s[fend+1:]
print("removed mounting holes")

# ---- 2. geometry ----
XC = 64.0
WIDE_W, NECK_W = 19.0, 12.0
XW0, XW1 = XC-WIDE_W/2, XC+WIDE_W/2
XN0, XN1 = XC-NECK_W/2, XC+NECK_W/2
TAPER = 3.0
Y0 = 30.0
CLR, GG = 0.4, 0.7
COURT_EDGE = 0.15    # courtyard may approach the edge this closely
PAD_EDGE   = 0.5     # copper (pads) must stay this far from the edge

neck_usable_court = NECK_W - 2*COURT_EDGE
wide_usable_court = WIDE_W - 2*COURT_EDGE

placed = {}

def pack(groups, usable, y):
    for g in groups:
        rows = []; cur = []; cw = 0.0
        for r in g:
            w = 2*data[r]['hw']
            add = w if not cur else cw + CLR + w
            if cur and add > usable:
                rows.append(cur); cur = [r]; cw = w
            else:
                cur.append(r); cw = add
        if cur:
            rows.append(cur)
        for row in rows:
            total = sum(2*data[r]['hw'] for r in row) + CLR*(len(row)-1)
            x = XC - total/2.0
            rh = max(2*data[r]['hh'] for r in row)
            rtop = y
            for ref in row:
                d = data[ref]
                placed[ref] = (x + d['hw'], rtop + d['hh'])
                x += 2*d['hw'] + CLR
            y = rtop + rh + CLR
        y += GG - CLR
    return y

# top neck: USB-C only (10.64 courtyard fits 11.7 usable)
y = Y0 + 0.9
y = pack([['J6']], neck_usable_court, y)
YA = y - GG + CLR + 0.3
YB = YA + TAPER

# wide middle
y = YB + 0.5
y = pack([
    ['U1', 'R1', 'R2'], ['F1', 'R7', 'D2'],
    ['U2', 'C2', 'C3'], ['R8', 'C10', 'C11'],
    ['U5', 'L1', 'C7'], ['C9', 'R11', 'R12'],
    ['R13', 'R14', 'C8'], ['U4', 'C4', 'C5'],
    ['C1', 'R3', 'D1'], ['R6', 'R9', 'R10', 'R5'],
    ['U3'],
    ['SW1', 'SW2'], ['SW3'],
    ['U6', 'U7'], ['C6'],
    ['J7'],
], wide_usable_court, y)

YC = y - GG + CLR + 0.3
YD = YC + TAPER

# bottom neck: J8 front / J9 back co-located
jh = data['J8']['hh']
ledy = YD + 0.5 + jh
placed['J8'] = (XC, ledy)
placed['J9'] = (XC, ledy)
Y1 = ledy + jh + 0.9

print("profile Y0=%.2f YA=%.2f YB=%.2f YC=%.2f YD=%.2f Y1=%.2f" % (Y0, YA, YB, YC, YD, Y1))
print("BOARD LENGTH = %.1f mm" % (Y1-Y0))

# ---- 3. validation ----
def half_at(yv):
    if yv <= YA or yv >= YD: return NECK_W/2
    if YB <= yv <= YC:       return WIDE_W/2
    if YA < yv < YB:         return NECK_W/2 + (yv-YA)/TAPER*(WIDE_W-NECK_W)/2
    return NECK_W/2 + (YD-yv)/TAPER*(WIDE_W-NECK_W)/2

def court_box(r):
    cx, cy = placed[r]; d = data[r]
    return (cx-d['hw'], cy-d['hh'], cx+d['hw'], cy+d['hh'])

def pad_box(r):
    cx, cy = placed[r]; d = data[r]
    # pad extent relative to the courtyard-centred placement
    pcx = cx - d['offx'] + d['pad_offx']
    pcy = cy - d['offy'] + d['pad_offy']
    return (pcx-d['pad_hw'], pcy-d['pad_hh'], pcx+d['pad_hw'], pcy+d['pad_hh'])

ov = []; edge = []
refs = list(placed)
for i in range(len(refs)):
    for j in range(i+1, len(refs)):
        a, b = refs[i], refs[j]
        if {a, b} == {'J8', 'J9'}:
            continue
        A, B = court_box(a), court_box(b)
        ox = min(A[2],B[2])-max(A[0],B[0]); oy = min(A[3],B[3])-max(A[1],B[1])
        if ox > 0.01 and oy > 0.01:
            ov.append((a, b, round(ox,2), round(oy,2)))
for r in refs:
    x0, y0_, x1, y1_ = pad_box(r)
    lim = min(half_at(y0_), half_at(y1_)) - PAD_EDGE
    if max(x1-XC, XC-x0) > lim + 1e-6:
        edge.append((r, 'pad width %.2f > allowed %.2f' % (2*max(x1-XC, XC-x0), 2*lim)))
    if y0_ < Y0+PAD_EDGE or y1_ > Y1-PAD_EDGE:
        edge.append((r, 'pad past end'))
    cx0, cy0, cx1, cy1 = court_box(r)
    clim = min(half_at(cy0), half_at(cy1)) - COURT_EDGE
    if max(cx1-XC, XC-cx0) > clim + 1e-6:
        edge.append((r, 'courtyard %.2f > allowed %.2f' % (2*max(cx1-XC, XC-cx0), 2*clim)))

print("OVERLAPS:", len(ov))
for o in ov: print("   ", o)
print("EDGE ISSUES:", len(edge))
for e in edge: print("   ", e)
if ov or edge:
    print("\n!! not clean - aborting write")
    sys.exit(1)

# ---- 4. outline ----
m = re.search(r'\n\t\(gr_rect\b', s)
if m:
    st = m.start()+1; en = fb(s, st)
    s = s[:m.start()] + s[en+1:]
for m in list(re.finditer(r'\n\t\(gr_line\b', s))[::-1]:
    st = m.start()+1; en = fb(s, st)
    if 'Edge.Cuts' in s[st:en+1]:
        s = s[:m.start()] + s[en+1:]

pts = [(XN0,Y0),(XN1,Y0),(XN1,YA),(XW1,YB),(XW1,YC),(XN1,YD),
       (XN1,Y1),(XN0,Y1),(XN0,YD),(XW0,YC),(XW0,YB),(XN0,YA)]
lines = []
for i in range(len(pts)):
    x1_, y1__ = pts[i]; x2_, y2__ = pts[(i+1) % len(pts)]
    lines.append('\t(gr_line\n\t\t(start %g %g)\n\t\t(end %g %g)\n'
                 '\t\t(stroke\n\t\t\t(width 0.1)\n\t\t\t(type default)\n\t\t)\n'
                 '\t\t(layer "Edge.Cuts")\n\t\t(uuid "bbbb%04d-1111-2222-3333-444455556666")\n\t)\n'
                 % (x1_, y1__, x2_, y2__, i))
zpos = s.find('\n\t(zone\n')
if zpos < 0: zpos = s.rfind('\n)')
s = s[:zpos+1] + ''.join(lines) + s[zpos+1:]

# ---- 5. zone ----
j = s.find('\n\t(zone\n')
while j >= 0:
    st = j+1; en = fb(s, st); blk = s[st:en+1]
    if '(net_name "-BATT")' in blk:
        pp = blk.find('(polygon'); pe = fb(blk, pp)
        ptstr = ' '.join('(xy %g %g)' % p for p in pts)
        blk = blk[:pp] + '(polygon\n\t\t\t(pts\n\t\t\t\t%s\n\t\t\t)\n\t\t)' % ptstr + blk[pe+1:]
        while True:
            fp = blk.find('(filled_polygon')
            if fp < 0: break
            fe = fb(blk, fp); ls = blk.rfind('\n', 0, fp)
            blk = blk[:ls] + blk[fe+1:]
        s = s[:st] + blk + s[en+1:]
        break
    j = s.find('\n\t(zone\n', en+1)

# ---- 6. flip J9 ----
def flip(s, ref):
    pm = re.search(r'\(property "Reference" "%s"' % ref, s)
    fstart = s.rfind('\n\t(footprint', 0, pm.start()); fst = fstart+1; fend = fb(s, fst)
    blk = s[fst:fend+1]
    if re.search(r'\(footprint "[^"]+"\s*\n\t\t\(layer "B\.Cu"', blk):
        return s
    blk = re.sub(r'(\(footprint "[^"]+"\s*\n\t\t\(layer ")F\.Cu(")', r'\1B.Cu\2', blk, count=1)
    m_at = re.search(r'(\n\t\t\(at )([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?(\))', blk)
    ang = float(m_at.group(4)) if m_at.group(4) else 0.0
    nang = (-ang) % 360
    new_at = '\n\t\t(at %s %s%s)' % (m_at.group(2), m_at.group(3), (' %g' % nang) if nang else '')
    blk = blk[:m_at.start()] + new_at + blk[m_at.end():]
    sp = m_at.start()+len(new_at); header, body = blk[:sp], blk[sp:]
    def sl(m):
        n = m.group(1)
        n = 'B.'+n[2:] if n.startswith('F.') else ('F.'+n[2:] if n.startswith('B.') else n)
        return '(layer "%s")' % n
    body = re.sub(r'\(layer "(F\.[A-Za-z0-9_]+|B\.[A-Za-z0-9_]+)"\)', sl, body)
    def sls(m):
        toks = re.findall(r'"([^"]+)"', m.group(0))
        return '(layers ' + ' '.join('"%s"' % ('B.'+t[2:] if t.startswith('F.') else ('F.'+t[2:] if t.startswith('B.') else t)) for t in toks) + ')'
    body = re.sub(r'\(layers [^)]*\)', sls, body)
    def nat(m):
        x = m.group(1); yv = float(m.group(2)); a = m.group(3)
        r = '(at %s %g' % (x, -yv)
        if a is not None: r += ' %g' % ((-float(a)) % 360)
        return r + ')'
    body = re.sub(r'\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)', nat, body)
    body = re.sub(r'\((start|end|center|xy|mid) ([-\d.]+) ([-\d.]+)\)',
                  lambda m: '(%s %s %g)' % (m.group(1), m.group(2), -float(m.group(3))), body)
    return s[:fst] + header + body + s[fend+1:]
s = flip(s, 'J9')

# ---- 7. positions ----
def set_pos(s, ref, cx, cy):
    d = data[ref]
    ox = round(cx - d['offx'], 4); oy = round(cy - d['offy'], 4); rot = d['rot']
    pm = re.search(r'\(property "Reference" "%s"' % re.escape(ref), s)
    fstart = s.rfind('\n\t(footprint', 0, pm.start()); fst = fstart+1; fend = fb(s, fst)
    blk = s[fst:fend+1]
    def repl(m):
        if ref == 'J9':
            return '\n\t\t(at %s %s)' % (ox, oy)
        if rot and abs(rot) > 1e-9:
            return '\n\t\t(at %s %s %s)' % (ox, oy, int(rot) if float(rot).is_integer() else rot)
        return '\n\t\t(at %s %s)' % (ox, oy)
    nb, c = re.subn(r'\n\t\t\(at [-\d.]+ [-\d.]+(?: [-\d.]+)?\)', repl, blk, count=1)
    return s[:fst] + nb + s[fend+1:]

for ref, (cx, cy) in placed.items():
    s = set_pos(s, ref, cx, cy)

print("paren balance:", s.count('(')-s.count(')'))
open(OUT, 'w').write(s)
print("wrote", OUT)
