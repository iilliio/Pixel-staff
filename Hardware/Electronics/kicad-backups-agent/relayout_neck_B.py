import re, json

SRC = '/Users/iliao/Projects/Pixel-staff/Hardware/Electronics/kicad/kicad.kicad_pcb'
OUT = '/tmp/necked_B.kicad_pcb'
data = json.load(open('/tmp/fp_data.json'))
s = open(SRC).read()

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

# ---------------- 1. remove mounting-hole footprints ----------------
for ref in ['H1', 'H2', 'H3', 'H4']:
    pm = re.search(r'\(property "Reference" "%s"' % ref, s)
    if not pm:
        print("  (no %s on board)" % ref); continue
    fstart = s.rfind('\n\t(footprint', 0, pm.start())
    fend = fb(s, fstart + 1)
    s = s[:fstart] + s[fend+1:]
    print("removed footprint", ref)

# ---------------- 2. board profile constants ----------------
XC     = 64.0
WIDE_W = 19.0
NECK_W = 12.0
XW0, XW1 = XC - WIDE_W/2, XC + WIDE_W/2      # 54.5 .. 73.5
XN0, XN1 = XC - NECK_W/2, XC + NECK_W/2      # 58.0 .. 70.0
TAPER  = 3.0
EDGE_M = 0.7          # keep courtyards this far inside the copper edge
Y0     = 30.0
CLR, GG = 0.55, 1.1

neck_usable = NECK_W - 2*EDGE_M      # 10.6
wide_usable = WIDE_W - 2*EDGE_M      # 17.6

placed = {}

def pack(groups, usable, y):
    """shelf-pack groups centered on XC starting at y; returns new y"""
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

# ---- top neck: USB-C plus the small USB-side parts that fit in 10.6 mm ----
y = Y0 + 1.4
y = pack([['J6']], neck_usable, y)
YA = y - GG + CLR + 0.4          # end of straight neck
YB = YA + TAPER                  # start of wide section

# ---- wide middle ----
y = YB + 0.8
y = pack([
    ['U1', 'R1', 'R2', 'F1'],
    ['U2', 'C2', 'C3', 'R7', 'D2', 'R8'],
    ['U5', 'L1', 'C7', 'C9'],
    ['C10', 'C11', 'R11', 'R12', 'R13', 'R14'],
    ['U4', 'C4', 'C5', 'C8'],
    ['C1', 'R3', 'R6', 'R9', 'R10', 'R5', 'D1'],
    ['U3'],
    ['SW1', 'SW2', 'SW3'],
    ['U6', 'U7', 'C6'],
    ['J7'],                       # battery on the wide part, just before the neck
], wide_usable, y)

YC = y - GG + CLR + 0.4          # end of wide section
YD = YC + TAPER                  # start of bottom neck

# ---- bottom neck: LED connectors, J8 front + J9 back (co-located) ----
jh = data['J8']['hh']
ledy = YD + 0.8 + jh
placed['J8'] = (XC, ledy)
placed['J9'] = (XC, ledy)
Y1 = ledy + jh + 1.4             # bottom edge

print("\nprofile: Y0=%.2f  neck_end=%.2f  wide=%.2f..%.2f  neck_start=%.2f  Y1=%.2f"
      % (Y0, YA, YB, YC, YD, Y1))
print("BOARD LENGTH = %.1f mm   (necks %.0f mm wide, middle %.0f mm)"
      % (Y1 - Y0, NECK_W, WIDE_W))

# ---------------- 3. validation against the tapered envelope ----------------
def half_width_at(yv):
    """allowed half width of copper edge at a given y"""
    if yv <= YA:  return NECK_W/2
    if yv >= YD:  return NECK_W/2
    if YB <= yv <= YC: return WIDE_W/2
    if YA < yv < YB:
        t = (yv - YA)/TAPER
        return NECK_W/2 + t*(WIDE_W-NECK_W)/2
    t = (YD - yv)/TAPER
    return NECK_W/2 + t*(WIDE_W-NECK_W)/2

def box(r):
    cx, cy = placed[r]; d = data[r]
    return (cx-d['hw'], cy-d['hh'], cx+d['hw'], cy+d['hh'])

ov = []; oob = []
refs = list(placed)
for i in range(len(refs)):
    for j in range(i+1, len(refs)):
        a, b = refs[i], refs[j]
        if {a, b} == {'J8', 'J9'}:
            continue
        A, B = box(a), box(b)
        if min(A[2],B[2])-max(A[0],B[0]) > 0.05 and min(A[3],B[3])-max(A[1],B[1]) > 0.05:
            ov.append((a, b))
for r in refs:
    x0, y0_, x1, y1_ = box(r)
    if y0_ < Y0 + 0.3 or y1_ > Y1 - 0.3:
        oob.append((r, 'ends')); continue
    # check both corners' y against the envelope
    hw_lim = min(half_width_at(y0_), half_width_at(y1_)) - EDGE_M
    if (x1 - XC) > hw_lim + 1e-6 or (XC - x0) > hw_lim + 1e-6:
        oob.append((r, 'width @y%.1f allowed=%.2f actual=%.2f'
                    % (y0_, 2*hw_lim, max(x1-XC, XC-x0)*2)))
print("OVERLAPS:", len(ov), ov)
print("OUTSIDE PROFILE:", len(oob))
for o in oob: print("   ", o)

# ---------------- 4. new Edge.Cuts outline ----------------
# remove the old rectangle
m = re.search(r'\n\t\(gr_rect\b', s)
if m:
    st = m.start() + 1; en = fb(s, st)
    s = s[:m.start()] + s[en+1:]
    print("removed old rect outline")

pts = [
    (XN0, Y0), (XN1, Y0),          # top edge
    (XN1, YA), (XW1, YB),          # upper right taper
    (XW1, YC), (XN1, YD),          # lower right taper
    (XN1, Y1), (XN0, Y1),          # bottom edge
    (XN0, YD), (XW0, YC),          # lower left taper
    (XW0, YB), (XN0, YA),          # upper left taper
]
uid = 0
lines = []
for i in range(len(pts)):
    x1_, y1__ = pts[i]
    x2_, y2__ = pts[(i+1) % len(pts)]
    uid += 1
    lines.append(
        '\t(gr_line\n\t\t(start %g %g)\n\t\t(end %g %g)\n'
        '\t\t(stroke\n\t\t\t(width 0.1)\n\t\t\t(type default)\n\t\t)\n'
        '\t\t(layer "Edge.Cuts")\n\t\t(uuid "aaaa%04d-1111-2222-3333-444455556666")\n\t)\n'
        % (x1_, y1__, x2_, y2__, uid))
outline = ''.join(lines)

# insert before the zone (or before final close)
zpos = s.find('\n\t(zone\n')
if zpos < 0:
    zpos = s.rfind('\n)')
s = s[:zpos+1] + outline + s[zpos+1:]
print("inserted %d Edge.Cuts segments" % len(pts))

# ---------------- 5. reshape ground zone to the same profile ----------------
def reshape_zone(s):
    j = s.find('\n\t(zone\n')
    while j >= 0:
        st = j+1; en = fb(s, st); blk = s[st:en+1]
        if '(net_name "-BATT")' in blk:
            pp = blk.find('(polygon'); pe = fb(blk, pp)
            ptstr = ' '.join('(xy %g %g)' % p for p in pts)
            newp = '(polygon\n\t\t\t(pts\n\t\t\t\t%s\n\t\t\t)\n\t\t)' % ptstr
            blk = blk[:pp] + newp + blk[pe+1:]
            while True:
                fp = blk.find('(filled_polygon')
                if fp < 0: break
                fe = fb(blk, fp); ls = blk.rfind('\n', 0, fp)
                blk = blk[:ls] + blk[fe+1:]
            print("reshaped ground zone to profile")
            return s[:st] + blk + s[en+1:]
        j = s.find('\n\t(zone\n', en+1)
    return s
s = reshape_zone(s)

# ---------------- 6. flip J9 to the back ----------------
def flip(s, ref):
    pm = re.search(r'\(property "Reference" "%s"' % ref, s)
    fstart = s.rfind('\n\t(footprint', 0, pm.start()); fst = fstart+1; fend = fb(s, fst)
    blk = s[fst:fend+1]
    if re.search(r'\(footprint "[^"]+"\s*\n\t\t\(layer "B\.Cu"', blk):
        print(ref, "already on back"); return s
    blk = re.sub(r'(\(footprint "[^"]+"\s*\n\t\t\(layer ")F\.Cu(")', r'\1B.Cu\2', blk, count=1)
    m_at = re.search(r'(\n\t\t\(at )([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?(\))', blk)
    ang = float(m_at.group(4)) if m_at.group(4) else 0.0
    nang = (-ang) % 360
    new_at = '\n\t\t(at %s %s%s)' % (m_at.group(2), m_at.group(3), (' %g' % nang) if nang else '')
    blk = blk[:m_at.start()] + new_at + blk[m_at.end():]
    sp = m_at.start() + len(new_at)
    header, body = blk[:sp], blk[sp:]
    def sl(m):
        n = m.group(1)
        n = 'B.'+n[2:] if n.startswith('F.') else ('F.'+n[2:] if n.startswith('B.') else n)
        return '(layer "%s")' % n
    body = re.sub(r'\(layer "(F\.[A-Za-z0-9_]+|B\.[A-Za-z0-9_]+)"\)', sl, body)
    def sls(m):
        toks = re.findall(r'"([^"]+)"', m.group(0)); out = []
        for t in toks:
            out.append('B.'+t[2:] if t.startswith('F.') else ('F.'+t[2:] if t.startswith('B.') else t))
        return '(layers ' + ' '.join('"%s"' % t for t in out) + ')'
    body = re.sub(r'\(layers [^)]*\)', sls, body)
    def nat(m):
        x = m.group(1); yv = float(m.group(2)); a = m.group(3)
        r = '(at %s %g' % (x, -yv)
        if a is not None: r += ' %g' % ((-float(a)) % 360)
        return r + ')'
    body = re.sub(r'\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)', nat, body)
    body = re.sub(r'\((start|end|center|xy|mid) ([-\d.]+) ([-\d.]+)\)',
                  lambda m: '(%s %s %g)' % (m.group(1), m.group(2), -float(m.group(3))), body)
    print("flipped", ref, "to B.Cu")
    return s[:fst] + header + body + s[fend+1:]
s = flip(s, 'J9')

# ---------------- 7. write positions ----------------
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
    if c != 1:
        print("!! at not set for", ref)
    return s[:fst] + nb + s[fend+1:]

for ref, (cx, cy) in placed.items():
    s = set_pos(s, ref, cx, cy)

print("paren balance:", s.count('(') - s.count(')'))
open(OUT, 'w').write(s)
print("wrote", OUT)
