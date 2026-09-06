# Smaller PCB baseline review

Source: `../kicad/kicad.kicad_pcb` and matching schematic. Checked using installed KiCad 9 CLI and pcbnew API.

- Outline bounding box: 18.1 × 76.776 mm (includes outline stroke).
- 41 footprints; 0 track/via items.
- DRC: 133 unconnected items; 77 violations; 1 schematic parity warning.
- ERC: 34 errors and 70 warnings.

## DRC categories

- lib_footprint_mismatch: 6
- text_height: 1
- silk_over_copper: 31
- silk_overlap: 39

## ERC categories

- warning: lib_symbol_mismatch: 51
- error: pin_not_connected: 2
- error: power_pin_not_driven: 2
- warning: unconnected_wire_endpoint: 3
- warning: pin_to_pin: 14
- warning: multiple_net_names: 1
- error: pin_to_pin: 29
- warning: global_label_dangling: 1
- error: pin_not_driven: 1

## Before routing signoff

- Confirm LED maximum current, copper weight, layer stack and manufacturer rules.
- Investigate U7 input-not-driven and dangling labels/wires.
- Review ESP32 symbol pin electrical types: 29 power-output conflicts involve ground pins.
- Confirm unused USB SBU pins and annotate intentionally unused pins.
- Reconcile J7 schematic/PCB value and modified library items without replacing intentional custom pads.
- Review boost-converter placement, power loops, USB routing and ESP32 antenna keepout against component documentation.

No source design files changed. This is a baseline report, not fabrication approval.
