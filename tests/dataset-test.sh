#!/usr/bin/env bash
# Sanity checks for the datasets the picker loads: emojis.json in memory,
# nerdfonts.tsv streamed through grep.
set -euo pipefail
cd "$(dirname "$0")/.."

jq empty emojis.json

EMOJI_COUNT=$(jq 'length' emojis.json)
(( EMOJI_COUNT > 1800 )) || { echo "emojis.json: expected >1800 entries, got $EMOJI_COUNT" >&2; exit 1; }
jq -e 'all(.[]; (.e | type) == "string" and (.k | type) == "string")' emojis.json > /dev/null
jq -e 'any(.[]; .e == "😀")' emojis.json > /dev/null

# TSV: one row per glyph, three tab-separated fields, ASCII hex codepoints
TSV_LINES=$(wc -l < nerdfonts.tsv)
(( TSV_LINES > 10000 )) || { echo "nerdfonts.tsv: expected >10000 lines, got $TSV_LINES" >&2; exit 1; }
LC_ALL=C awk -F'\t' 'NF != 3 || $3 !~ /^[0-9a-f]+$/ { exit 1 }' nerdfonts.tsv \
  || { echo "nerdfonts.tsv: malformed row (expected keywords<TAB>name<TAB>hex)" >&2; exit 1; }
LC_ALL=C awk -F'\t' '$2 == "nf-md-home" { found = 1 } END { exit !found }' nerdfonts.tsv \
  || { echo "nerdfonts.tsv: nf-md-home row missing" >&2; exit 1; }
if LC_ALL=C command grep -qP '[^\x00-\x7f]' nerdfonts.tsv; then
  echo "nerdfonts.tsv: expected pure ASCII (hex codepoints, not raw glyphs)" >&2
  exit 1
fi

# Kaomoji TSV: one row per kaomoji, tags <TAB> string, lowercase tags
KAO_LINES=$(wc -l < kaomoji.tsv)
(( KAO_LINES > 1500 )) || { echo "kaomoji.tsv: expected >1500 lines, got $KAO_LINES" >&2; exit 1; }
LC_ALL=C awk -F'\t' 'NF != 2 || $1 !~ /^[a-z0-9 ]*$/ || $2 == "" { exit 1 }' kaomoji.tsv \
  || { echo "kaomoji.tsv: malformed row (expected tags<TAB>string)" >&2; exit 1; }

# search behavior over the real dataset (same token-AND semantics as QML)
node <<'EOF'
const assert = require("assert")
const fs = require("fs")
const EmojiSearch = require("./EmojiSearch.js")

const rows = fs.readFileSync("nerdfonts.tsv", "utf8").split("\n").filter(Boolean)
const byName = Object.fromEntries(rows.map(r => [EmojiSearch.parseTsvLine(r).n, r]))

assert.ok(EmojiSearch.filterTsvRows(rows, ["house"], 1000).length >= 5)
assert.ok(byName["nf-md-home"])
assert.ok(EmojiSearch.filterTsvRows(rows, ["md", "home"], 1000).some(i => i.n === "nf-md-home"))
assert.ok(EmojiSearch.filterTsvRows(rows, ["arrow", "left"], 1000).some(i => i.n === "nf-cod-arrow_left"))
assert.strictEqual(EmojiSearch.filterTsvRows(rows, ["zzznomatch"], 1000).length, 0)
// Set labels are stripped from keywords: "material" only matches glyphs
// genuinely named material, and the glyph is decodable (astral codepoint).
const material = EmojiSearch.filterTsvRows(rows, ["material"], 1000)
assert.strictEqual(material.length, 5)
assert.ok(material.every(i => i.e.length > 0))

// kaomoji.tsv parses whole and searches by tag (token-AND) over the real data
const kaomoji = EmojiSearch.parseKaomojiTsv(fs.readFileSync("kaomoji.tsv", "utf8"))
assert.ok(kaomoji.length > 1500)
assert.ok(kaomoji.every(i => i.e.length > 0 && typeof i.tags === "string"))
assert.ok(EmojiSearch.filterEmojis(kaomoji, "table flip", 1000).length >= 10)
const both = EmojiSearch.filterEmojis(kaomoji, "happy love", 1000)
assert.ok(both.length >= 1 && both.every(i => i.k.includes("happy") && i.k.includes("love")))
assert.ok(EmojiSearch.filterEmojis(kaomoji, "hide wave", 1000).some(i => i.e === "川o･-･)ﾉ"))
assert.strictEqual(EmojiSearch.filterEmojis(kaomoji, "zzznomatch", 1000).length, 0)

console.log("dataset-test: all assertions passed")
EOF
