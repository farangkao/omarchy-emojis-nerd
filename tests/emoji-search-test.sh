#!/usr/bin/env bash
# Search-logic tests for EmojiSearch.js, run through Node (CommonJS).
set -euo pipefail
cd "$(dirname "$0")/.."

node <<'EOF'
const assert = require("assert")
const EmojiSearch = require("./EmojiSearch.js")

const fixture = [
  { e: "😀", k: "grinning face happy smile" },
  { e: "\uf015", n: "nf-fa-home", k: "nf-fa-home fa-home home fa house fontawesome" },
  { e: "\uf02d", n: "nf-md-home", k: "nf-md-home md-home home md house material" },
]

// parseEmojis: valid arrays pass through, anything else yields []
assert.deepStrictEqual(EmojiSearch.parseEmojis("[]"), [])
assert.deepStrictEqual(EmojiSearch.parseEmojis("not json"), [])
assert.strictEqual(EmojiSearch.parseEmojis(JSON.stringify(fixture)).length, 3)

// single-token search, input order preserved
let out = EmojiSearch.filterEmojis(fixture, "house", 100)
assert.strictEqual(out.length, 2)
assert.strictEqual(out[0].n, "nf-fa-home")

// token AND: every whitespace-separated word must match
out = EmojiSearch.filterEmojis(fixture, "material home", 100)
assert.strictEqual(out.length, 1)
assert.strictEqual(out[0].n, "nf-md-home")
assert.strictEqual(EmojiSearch.filterEmojis(fixture, "house nomatch", 100).length, 0)

// case-insensitive, extra whitespace tolerated
out = EmojiSearch.filterEmojis(fixture, "  MATERIAL   Home ", 100)
assert.strictEqual(out.length, 1)

// empty query matches everything; limit is honored
assert.strictEqual(EmojiSearch.filterEmojis(fixture, "", 100).length, 3)
assert.strictEqual(EmojiSearch.filterEmojis(fixture, "", 2).length, 2)
assert.strictEqual(EmojiSearch.filterEmojis(fixture, "", 0).length, 0)

console.log("emoji-search-test: all assertions passed")
EOF
