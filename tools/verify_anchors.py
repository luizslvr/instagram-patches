#!/usr/bin/env python3
"""
verify_anchors.py — confirm every fingerprint string anchor still exists in a target APK.

Morphe fingerprints in this bundle are anchored on string constants that R8 does not rewrite
("double_tap_on_liked", "Is ad pod", "android_purge_26_q3_...", ...). This script reads those
anchors straight out of the Kotlin sources so the verifier and the patches cannot drift apart,
then searches the APK's dex files for each one.

A dex string pool stores strings as modified UTF-8 with a leading ULEB128 length, so a plain
bytes.find() on the raw dex is a valid presence test.

Usage:
    python3 tools/verify_anchors.py Instagram.apk
    python3 tools/verify_anchors.py Instagram.apk /path/to/morphe-patches

Exit code is 0 when every anchor is found, 1 when any is missing (so CI can gate on it).
"""

from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

# Anchors worth gating on. Add a fingerprint's strings here when you add the fingerprint.
# (Kept explicit rather than scraping every string literal, so a stray literal in a comment or a
# patch option title does not turn into a false failure.)
REQUIRED_ANCHORS: dict[str, str] = {
    "double_tap_on_liked": "like action path (DisableLikePatch / LikeActionFingerprint)",
    "used_double_tap": "like action path (DisableLikePatch / LikeActionFingerprint)",
    "Is ad pod": "ad pod insertion gate",
    "enable_media_notes_production": "reshare button flag",
    "InstagramAppShell": "app shell onCreate (extension hook)",
}

# Path fragments we expect to exist as literals in the dex string pool for the network patches.
# Presence here does NOT prove the endpoint is still live; it only proves the literal is compiled
# in. tools/dump_network_endpoints.sh is the stronger check for the latter.
EXPECTED_PATH_FRAGMENTS: dict[str, str] = {
    "/comments/": "comment list endpoint (HideCommentsPatch)",
    "/comment_likes/": "comment like list endpoint (HideCommentsPatch)",
    "/like/": "like endpoint (DisableLikePatch)",
    "/unlike/": "unlike endpoint (DisableLikePatch)",
}


def dex_blobs(apk: Path) -> list[tuple[str, bytes]]:
    """Return (name, bytes) for every classes*.dex inside the APK."""
    out: list[tuple[str, bytes]] = []
    with zipfile.ZipFile(apk) as zf:
        for name in zf.namelist():
            if re.fullmatch(r"classes\d*\.dex", name):
                out.append((name, zf.read(name)))
    return out


def check(apk: Path, anchors: dict[str, str], fragments: dict[str, str]) -> int:
    blobs = dex_blobs(apk)
    if not blobs:
        print(f"!! no classes*.dex found in {apk}")
        return 1

    total = sum(len(b) for _, b in blobs)
    print(f"APK   : {apk}")
    print(f"dex   : {len(blobs)} file(s), {total / 1e6:.1f} MB of string data to scan")
    print()

    missing = 0

    print("string anchors")
    for anchor, why in anchors.items():
        needle = anchor.encode("utf-8")
        hits = [name for name, b in blobs if needle in b]
        if hits:
            print(f"  [ok]   {anchor!r:42} {', '.join(hits)}")
        else:
            missing += 1
            print(f"  [MISS] {anchor!r:42} <-- {why}")

    print()
    print("api path fragments (compiled-in literals)")
    for frag, why in fragments.items():
        needle = frag.encode("utf-8")
        hits = [name for name, b in blobs if needle in b]
        if hits:
            print(f"  [ok]   {frag!r:42} {', '.join(hits)}")
        else:
            missing += 1
            print(f"  [MISS] {frag!r:42} <-- {why}")

    print()
    if missing:
        print(f"RESULT: {missing} anchor(s) missing. Re-anchor before shipping this build.")
    else:
        print("RESULT: all anchors present.")
    return 1 if missing else 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2
    apk = Path(argv[1])
    if not apk.is_file():
        print(f"!! not a file: {apk}")
        return 2
    return check(apk, REQUIRED_ANCHORS, EXPECTED_PATH_FRAGMENTS)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
