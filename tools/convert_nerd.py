#!/usr/bin/env python3
"""Convert Nerd Fonts glyphnames.json into the picker's nerdfonts.tsv.

One line per unique codepoint: keywords <TAB> nf-name <TAB> hex-codepoint.
The hex field keeps the file pure ASCII, and the picker turns it back into
the glyph with a surrogate-pair-aware decode.

Keywords are source-derived only: the nf-prefixed name, the raw name, the
dashed name, and the name's words minus the set prefix. Set labels like
"material" or "fontawesome" are deliberately omitted — they would match
thousands of glyphs at once; narrow by prefix instead ("md home").

To regenerate when Nerd Fonts ships a new release (or just run
`mise run regenerate-dataset` from the repo root):

    curl -fsSL -o /tmp/glyphnames.json \\
      https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.5.0/glyphnames.json
    python3 tools/convert_nerd.py --input /tmp/glyphnames.json

The picker greps the file on every search, so new data applies on the next
search with no shell restart.
"""
import argparse
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def keywords_for(names):
    words = set()
    for n in names:
        words.add("nf-" + n)
        words.add(n)
        words.add(n.replace("_", "-"))
        parts = n.replace("-", " ").replace("_", " ").split()
        for w in parts[1:]:
            if w:
                words.add(w)
    return " ".join(sorted(words))


def build_rows(data):
    by_code = {}  # code hex -> set of names (aliases share a codepoint)
    for name, meta in data.items():
        if name == "METADATA":
            continue
        by_code.setdefault(meta["code"].lower(), set()).add(name)

    rows = []
    for code, names in by_code.items():
        primary = sorted(names)[0]
        rows.append((f"nf-{primary}", f"{keywords_for(names)}\tnf-{primary}\t{code}"))

    rows.sort(key=lambda r: r[0])
    return rows


def main():
    parser = argparse.ArgumentParser(
        description="Convert Nerd Fonts glyphnames.json to the picker's nerdfonts.tsv"
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=REPO_ROOT / "tools" / "glyphnames.json",
        help="path to glyphnames.json downloaded from the nerd-fonts repo",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=REPO_ROOT / "nerdfonts.tsv",
        help="where to write the dataset (default: nerdfonts.tsv at the repo root)",
    )
    args = parser.parse_args()

    with open(args.input) as f:
        data = json.load(f)

    rows = build_rows(data)

    with open(args.output, "w") as f:
        f.write("\n".join(r[1] for r in rows) + "\n")

    print(f"unique glyphs: {len(rows)}")
    # sanity: keyword search test
    hits = sum(1 for _, line in rows if " home " in f" {line.split(chr(9))[0]} ")
    print(f"'home' keyword matches: {hits}")


if __name__ == "__main__":
    main()
