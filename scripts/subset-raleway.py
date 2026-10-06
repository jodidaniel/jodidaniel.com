#!/usr/bin/env python3
"""Limit the self-hosted Raleway variable font to the weights the site uses.

The site sets Raleway at weight 600 and 700 only. Google ships one variable
font with a wght axis of 100-900; the 100-599 and 701-900 ranges are dead
weight on the wire. This pins the axis to 600-700 (fontTools varLib.instancer,
"limit axis range"). Character coverage (the Latin-1 unicode-range) stays
the same, but the outlines are not byte-identical: the source default weight
is 100, outside 600-700, so fontTools re-bases the font at wght 600 and rounds
outlines to integer units (at most 1/1000 em at 600, 2/1000 at 700; at 700,
123 advance widths differ by 1 unit; the kern table is not byte-identical).

  python3 -m venv /tmp/venv && /tmp/venv/bin/pip install -r scripts/requirements-fonts.txt
  /tmp/venv/bin/python scripts/subset-raleway.py <source.woff2> assets/fonts/raleway-v37-latin-wght600-700.woff2

The source is the upstream file recorded in assets/fonts/SOURCES.txt. The script
refuses any other bytes (sha256 below) and any other fontTools version, so a
re-run on a clean machine yields the vendored file byte for byte. The vendored
output is what the site ships; this script is not part of the Jekyll build.
"""
import hashlib
import sys

from fontTools import version as fonttools_version
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

SOURCE_SHA256 = "b1bef1f03a77a36fc257c5525e32a1dd621bb6f935b743a419da7ed0b18dc8f5"
FONTTOOLS_VERSION = "4.66.0"  # keep in step with scripts/requirements-fonts.txt
WGHT_RANGE = (600, 700)


def main(source, dest):
    if fonttools_version != FONTTOOLS_VERSION:
        sys.exit(f"fontTools {fonttools_version} found, {FONTTOOLS_VERSION} required")
    with open(source, "rb") as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    if digest != SOURCE_SHA256:
        sys.exit(f"{source}: sha256 {digest} is not the recorded source {SOURCE_SHA256}")

    # recalcTimestamp=False keeps head.modified from the source, so the output
    # does not change from one run to the next.
    font = TTFont(source, recalcTimestamp=False)
    before = font.getBestCmap()
    limited = instancer.instantiateVariableFont(font, {"wght": WGHT_RANGE})
    assert limited.getBestCmap() == before, "character coverage changed"
    axis = next(a for a in limited["fvar"].axes if a.axisTag == "wght")
    assert (axis.minValue, axis.maxValue) == tuple(float(v) for v in WGHT_RANGE), "wght axis not limited"
    limited.flavor = "woff2"
    limited.save(dest)
    print(f"wrote {dest}: wght {axis.minValue:g}-{axis.maxValue:g}, {len(before)} characters kept")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
