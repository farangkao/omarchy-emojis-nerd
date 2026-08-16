#!/usr/bin/env bash
# Sanity checks for the two datasets the picker loads.
set -euo pipefail
cd "$(dirname "$0")/.."

jq empty emojis.json nerdfonts.json

EMOJI_COUNT=$(jq 'length' emojis.json)
NERD_COUNT=$(jq 'length' nerdfonts.json)
(( EMOJI_COUNT > 1800 )) || { echo "emojis.json: expected >1800 entries, got $EMOJI_COUNT" >&2; exit 1; }
(( NERD_COUNT > 10000 )) || { echo "nerdfonts.json: expected >10000 entries, got $NERD_COUNT" >&2; exit 1; }

# schema: every entry has string e + k; nerd entries also carry the n name
jq -e 'all(.[]; (.e | type) == "string" and (.k | type) == "string")' emojis.json > /dev/null
jq -e 'all(.[]; (.e | type) == "string" and (.k | type) == "string" and (.n | type) == "string")' nerdfonts.json > /dev/null

# spot checks
jq -e 'any(.[]; .n == "nf-md-home")' nerdfonts.json > /dev/null
jq -e 'any(.[]; .n == "nf-cod-arrow_left")' nerdfonts.json > /dev/null

# search behavior over the real dataset
node <<'EOF'
const assert = require("assert")
const fs = require("fs")
const EmojiSearch = require("./EmojiSearch.js")

const nerd = JSON.parse(fs.readFileSync("nerdfonts.json", "utf8"))
const byName = Object.fromEntries(nerd.map(i => [i.n, i]))

assert.ok(EmojiSearch.filterEmojis(nerd, "house", 1000).length >= 5)
assert.ok(byName["nf-md-home"])
assert.ok(EmojiSearch.filterEmojis(nerd, "material home", 1000).some(i => i.n === "nf-md-home"))
assert.ok(EmojiSearch.filterEmojis(nerd, "arrow left", 1000).some(i => i.n === "nf-cod-arrow_left"))
assert.strictEqual(EmojiSearch.filterEmojis(nerd, "zzznomatch", 1000).length, 0)

console.log("dataset-test: all assertions passed")
EOF
