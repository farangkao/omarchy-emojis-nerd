#!/usr/bin/env python3
"""Convert Nerd Fonts glyphnames.json into the picker's {"e","k"} schema.

To regenerate the dataset when Nerd Fonts ships a new release (or just run
`mise run regenerate-dataset` from the repo root, which pins the version):

    curl -fsSL -o /tmp/glyphnames.json \
      https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.5.0/glyphnames.json
    python3 tools/convert_nerd.py --input /tmp/glyphnames.json
    omarchy restart shell

Alias names sharing one codepoint are merged into a single entry, and the
keyword string matches on nf-prefixed names, dashed/underscored forms,
individual words, and human-readable set names (material, fontawesome, ...).
The primary display name is kept in "n".
"""
import argparse
import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

SET_NAMES = {
    "md": "material",
    "fa": "fontawesome",
    "fae": "fontawesome-extended",
    "cod": "codicons",
    "oct": "octicons",
    "dev": "devicon",
    "seti": "seti",
    "linux": "linux",
    "custom": "custom",
    "ple": "powerline-extra",
    "pl": "powerline",
    "weather": "weather",
    "pom": "pom",
    "iec": "iec",
    "indent": "indentation",
    "indentation": "indentation",
    "extra": "extra",
}


def keywords_for(names):
    words = set()
    for n in names:
        words.add("nf-" + n)
        words.add(n)  # exact dashed/underscored form, e.g. arrow_left
        words.add(n.replace("_", "-"))
        words.add(n.replace("-", " ").replace("_", " "))
        parts = n.replace("-", " ").replace("_", " ").split()
        set_prefix = parts[0]
        words.add(set_prefix)
        if set_prefix in SET_NAMES:
            words.add(SET_NAMES[set_prefix])
        for w in parts[1:]:
            if w:
                words.add(w)
    return " ".join(sorted(words))


def build_entries(data):
    by_code = {}  # code hex -> set of names
    for name, meta in data.items():
        if name == "METADATA":
            continue
        code = meta["code"].lower()
        by_code.setdefault(code, set()).add(name)

    out = []
    for code, names in by_code.items():
        names = sorted(names)
        out.append({
            "e": chr(int(code, 16)),
            "n": "nf-" + names[0],
            "k": keywords_for(names),
        })

    out.sort(key=lambda x: x["n"])
    return out


def main():
    parser = argparse.ArgumentParser(
        description="Convert Nerd Fonts glyphnames.json to the emoji-picker schema"
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
        default=REPO_ROOT / "nerdfonts.json",
        help="where to write the dataset (default: nerdfonts.json at the repo root)",
    )
    args = parser.parse_args()

    with open(args.input) as f:
        data = json.load(f)

    out = build_entries(data)

    with open(args.output, "w") as f:
        json.dump(out, f, ensure_ascii=True, separators=(",", ":"))

    print(f"unique glyphs: {len(out)}")
    # sanity: search test
    hits = [x for x in out if " house " in f" {x['k']} "]
    print(f"'house' matches: {len(hits)}")
    print("first matches:", [(h["n"], h["e"]) for h in hits[:5]])


if __name__ == "__main__":
    main()
