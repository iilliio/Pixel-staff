#!/usr/bin/env python3
import re, uuid, sys

DRY = "--write" not in sys.argv
SCH = "/Users/iliao/Projects/Pixel-staff/Hardware/Electronics/kicad/kicad.kicad_sch"
LIBSYM = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/symbols/Connector.kicad_sym"
ROOT = "55a1363e-3506-4b1f-a7a5-0f5495c7c793"

def nid(): return str(uuid.uuid4())

def balanced_block(text, start):
    depth = 0
    for i in range(start, len(text)):
        if text[i] == '(':
            depth += 1
        elif text[i] == ')':
            depth -= 1
            if depth == 0:
                return text[start:i+1], i+1
    raise ValueError("unbalanced")

def extract_lib_symbol(libtext, name):
    m = re.search(r'\(symbol "' + re.escape(name) + r'"', libtext)
    if not m:
        raise ValueError("symbol not found: " + name)
    blk, _ = balanced_block(libtext, m.start())
    return blk

sch = open(SCH).read()
lib = open(LIBSYM).read()

# --- Build embedded lib_symbols (rename top-level id only) ---
def embed(name):
    blk = extract_lib_symbol(lib, name)
    blk = blk.replace('(symbol "' + name + '"', '(symbol "Connector:' + name + '"', 1)
    return "\t\t" + blk

emb = embed("Conn_01x04_Socket") + "\n" + embed("Conn_01x02_Socket") + "\n"

# --- Remove old instance blocks (BT3,BT4,J1,J2,J3) ---
REMOVE = {"BT3", "BT4", "J1", "J2", "J3"}
removed = []
out = []
i = 0
# iterate top-level symbol instances: pattern "\n\t(symbol\n"
pat = re.compile(r'\n\t\(symbol\n')
pos = 0
result = sch
# We'll rebuild by scanning
chunks = []
last = 0
for m in pat.finditer(sch):
    blk_start = m.start() + 1  # the '\t(' -> '(' is at m.start()+1 (after \n); find '(' index
    paren_idx = sch.index('(', m.start())
    block, end = balanced_block(sch, paren_idx)
    refm = re.search(r'\(property "Reference" "([^"]+)"', block)
    ref = refm.group(1) if refm else "?"
    if ref in REMOVE:
        chunks.append(sch[last:m.start()])  # keep up to before this block's leading \n\t? keep \n
        # skip the block AND its leading "\n\t" so we don't leave blank line+tab
        last = end
        removed.append(ref)
chunks.append(sch[last:])
sch2 = "".join(chunks)

# --- New component instances ---
def inst(ref, lib_id, value, x, y, fp, pins):
    pl = "\n".join(f'\t\t(pin "{n}" (uuid "{nid()}"))' for n in pins)
    return f'''\t(symbol
\t\t(lib_id "{lib_id}")
\t\t(at {x} {y} 0)
\t\t(unit 1)
\t\t(exclude_from_sim no)
\t\t(in_bom yes)
\t\t(on_board yes)
\t\t(dnp no)
\t\t(uuid "{nid()}")
\t\t(property "Reference" "{ref}" (at {x} {y-8} 0) (effects (font (size 1.27 1.27))))
\t\t(property "Value" "{value}" (at {x} {y+8} 0) (effects (font (size 1.27 1.27))))
\t\t(property "Footprint" "{fp}" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(property "Datasheet" "~" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
\t\t(property "Description" "" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (hide yes)))
{pl}
\t\t(instances
\t\t\t(project "kicad"
\t\t\t\t(path "/{ROOT}"
\t\t\t\t\t(reference "{ref}")
\t\t\t\t\t(unit 1)
\t\t\t\t)
\t\t\t)
\t\t)
\t)'''

def glabel(net, x, y):
    return f'''\t(global_label "{net}"
\t\t(shape input)
\t\t(at {x} {y} 0)
\t\t(fields_autoplaced yes)
\t\t(effects (font (size 1.27 1.27)) (justify left))
\t\t(uuid "{nid()}")
\t\t(property "Intersheetrefs" "${{INTERSHEET_REFS}}" (at {x} {y} 0) (effects (font (size 1.27 1.27)) (justify left) (hide yes)))
\t)'''

def nc(x, y):
    return f'\t(no_connect (at {x} {y}) (uuid "{nid()}"))'

GH = "Connector_JST:JST_GH_BM04B-GHS-TBT_1x04-1MP_P1.25mm_Vertical"
PH2 = "Connector_JST:JST_PH_B2B-PH-K_1x02_P2.00mm_Vertical"
SOT = "Package_TO_SOT_SMD:SOT-23-5"

# Origins snapped to 1.27mm grid so all pin endpoints land on grid.
new_instances = [
    inst("J7", "Connector:Conn_01x02_Socket", "Battery", 40.64, 198.12, PH2, ["1","2"]),
    inst("J8", "Connector:Conn_01x04_Socket", "LED", 80.01, 195.58, GH, ["1","2","3","4"]),
    inst("J9", "Connector:Conn_01x04_Socket", "LED", 114.3, 195.58, GH, ["1","2","3","4"]),
    inst("U7", "Logic_LevelTranslator:SN74LV1T34DBV", "SN74LV1T34DBV", 175.26, 200.66, SOT, ["1","2","3","4","5"]),
]

# pin endpoint -> net labels (rot0, no mirror: sheet=(px+lx, py-ly)); all on 1.27 grid
labels = [
    # J7: pin1(-5.08,0)->+BATT ; pin2(-5.08,-2.54)->-BATT
    ("+BATT", 35.56, 198.12), ("-BATT", 35.56, 200.66),
    # J8: pin1(-5.08,2.54),pin2(-5.08,0),pin3(-5.08,-2.54),pin4(-5.08,-5.08)
    ("-BATT", 74.93, 193.04), ("+5V", 74.93, 195.58), ("LED1", 74.93, 198.12), ("LED2", 74.93, 200.66),
    # J9
    ("-BATT", 109.22, 193.04), ("+5V", 109.22, 195.58), ("LED1", 109.22, 198.12), ("LED2", 109.22, 200.66),
    # U7: pin5 VCC(0,7.62), pin3 GND(0,-7.62), pin2 A(-7.62,0), pin4 Y(7.62,0)
    ("+5V", 175.26, 193.04), ("-BATT", 175.26, 208.28), ("LED Data 2", 167.64, 200.66), ("LED2", 182.88, 200.66),
    # U6 output (pin4 Y) -> LED1
    ("LED1", 76.2, 129.54),
]
new_labels = [glabel(n, x, y) for (n, x, y) in labels]
new_nc = [nc(170.18, 198.12)]  # U7 pin1 NC (-5.08,2.54)

additions = "\n".join(new_instances + new_labels + new_nc) + "\n"

# --- Insert lib symbols after "(lib_symbols\n" ---
sch3 = sch2.replace("\t(lib_symbols\n", "\t(lib_symbols\n" + emb, 1)

# --- Insert additions before "\n\t(sheet_instances" ---
marker = "\n\t(sheet_instances"
idx = sch3.index(marker)
sch4 = sch3[:idx] + "\n" + additions + sch3[idx+1:]

print("removed instances:", removed)
print("added instances: J7,J8,J9,U7")
print("added labels:", len(new_labels), "+ nc:", len(new_nc))
# paren balance check
def balance(t): 
    return t.count('(') - t.count(')')
print("paren balance (orig):", balance(sch), " (new):", balance(sch4))
print("len orig:", len(sch), " len new:", len(sch4))

if DRY:
    print("\n--- DRY RUN, not writing. Sample new instance (J8): ---")
    print(new_instances[1])
    print("\n--- sample embedded lib symbol head ---")
    print(emb[:300])
else:
    open(SCH, "w").write(sch4)
    print("WROTE", SCH)
