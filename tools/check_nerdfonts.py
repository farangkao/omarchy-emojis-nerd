#!/usr/bin/env python3
"""Check for a new Nerd Fonts release and preview glyph changes.

Compares the NF_VERSION pinned in mise.toml against the latest upstream
release and, when they differ, downloads both glyphnames.json files and
reports the added and removed glyphs by codepoint.

Usage:
    python3 tools/check_nerdfonts.py                     # pin vs latest
    python3 tools/check_nerdfonts.py --baseline 3.3.0    # force a baseline

Exits 1 when glyph changes are found, so it can gate automation.
"""
import argparse
import json
import re
import sys
import tomllib
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GLYPHS_URL = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/{tag}/glyphnames.json"
LATEST_URL = "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest"


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "omarchy-emojis-nerd-check"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def pinned_version():
    with open(REPO_ROOT / "mise.toml", "rb") as f:
        config = tomllib.load(f)
    return config["tasks"]["regenerate-dataset"]["env"]["NF_VERSION"]


def glyphs(version):
    """version -> {codepoint hex: primary name}; aliases share a codepoint."""
    data = fetch_json(GLYPHS_URL.format(tag=f"v{version}"))
    out = {}
    for name, meta in data.items():
        if name != "METADATA":
            out.setdefault(meta["code"].lower(), name)
    return out


def main():
    parser = argparse.ArgumentParser(
        description="Check for a new Nerd Fonts release and preview glyph changes"
    )
    parser.add_argument(
        "--baseline",
        help="compare against this version instead of the mise.toml pin",
    )
    args = parser.parse_args()

    latest = re.sub(r"^v", "", fetch_json(LATEST_URL)["tag_name"])
    pinned = re.sub(r"^v", "", args.baseline or pinned_version())

    print(f"pinned: v{pinned}   latest: v{latest}")
    if pinned == latest:
        print("up to date")
        return 0

    old, new = glyphs(pinned), glyphs(latest)
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    print(f"v{pinned} -> v{latest}: +{len(added)} glyphs, -{len(removed)} glyphs, {len(new)} total")
    for code in added[:10]:
        print(f"  + {new[code]} (U+{code.upper()})")
    if len(added) > 10:
        print(f"  ... and {len(added) - 10} more")
    for code in removed[:10]:
        print(f"  - {old[code]} (U+{code.upper()})")

    print(f"""
To update:
  1. Set NF_VERSION = "{latest}" in mise.toml
  2. mise run regenerate-dataset
  3. mise run test && mise run validate
""")
    return 1


if __name__ == "__main__":
    sys.exit(main())
