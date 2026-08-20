#!/usr/bin/env python3
"""Convert w33ble/emoticon-data emoticons.json into the picker's kaomoji.tsv.

One line per kaomoji: tags <TAB> kaomoji-string. The upstream `id` field
(UUIDs) is dropped — nothing references it — and tags are joined by single
spaces. Every upstream tag is lowercase [a-z0-9 ] (verified), so the join
is lossless for the picker's token-AND search: query "table flip" matches
the tag "table flip" as tokens table+flip.

The upstream repo has been dormant for years, so there is no release-check
task; this script exists to (re)build the file if ever needed. Downloads
from GitHub by default, or pass --input to convert a local copy.
"""
import argparse
import json
import tempfile
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
UPSTREAM_URL = "https://raw.githubusercontent.com/w33ble/emoticon-data/master/emoticons.json"


def convert(data: dict) -> str:
    lines = []
    for item in data.get("emoticons", []):
        string = item.get("string", "")
        tags = " ".join(t for t in item.get("tags", []) if t)
        if string and "\t" not in string and "\n" not in string:
            lines.append(f"{tags}\t{string}")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, help="local emoticons.json (default: download upstream)")
    parser.add_argument("--output", type=Path, default=REPO_ROOT / "kaomoji.tsv")
    args = parser.parse_args()

    with tempfile.NamedTemporaryFile() as tmp:
        source = args.input
        if source is None:
            source = Path(tmp.name)
            urllib.request.urlretrieve(UPSTREAM_URL, source)
        raw = json.loads(source.read_text(encoding="utf-8"))

    tsv = convert(raw)
    args.output.write_text(tsv, encoding="utf-8")
    print(f"{args.output}: {tsv.count(chr(10))} kaomoji, {len(tsv.encode('utf-8'))} bytes")


if __name__ == "__main__":
    main()
