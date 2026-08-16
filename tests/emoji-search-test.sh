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

// queryTokens
assert.deepStrictEqual(EmojiSearch.queryTokens("  Material   Home "), ["material", "home"])
assert.deepStrictEqual(EmojiSearch.queryTokens(""), [])

// glyphFromHex: BMP, astral (surrogate pair), and invalid input
assert.strictEqual(EmojiSearch.glyphFromHex("f015"), "\uf015")
assert.strictEqual(EmojiSearch.glyphFromHex("f0986"), String.fromCodePoint(0xf0986))
assert.strictEqual(EmojiSearch.glyphFromHex("zzz"), "")
assert.strictEqual(EmojiSearch.glyphFromHex(""), "")

// parseTsvLine: keywords <TAB> name <TAB> hex
const row = EmojiSearch.parseTsvLine("home md-home nf-md-home\tnf-md-home\tf02dc")
assert.strictEqual(row.n, "nf-md-home")
assert.strictEqual(row.e, String.fromCodePoint(0xf02dc))
assert.strictEqual(row.k, "home md-home nf-md-home")
assert.strictEqual(EmojiSearch.parseTsvLine("garbage"), null)
assert.strictEqual(EmojiSearch.parseTsvLine("a\tb"), null)

// filterTsvRows: token AND over keyword field, limit honored
const tsvRows = [
  "home md-home nf-md-home\tnf-md-home\tf02dc",
  "home house fa-home nf-fa-home\tnf-fa-home\tf015",
]
assert.deepStrictEqual(
  EmojiSearch.filterTsvRows(tsvRows, ["md", "home"], 100).map(i => i.n),
  ["nf-md-home"]
)
assert.deepStrictEqual(
  EmojiSearch.filterTsvRows(tsvRows, ["home"], 1).map(i => i.n),
  ["nf-md-home"]
)
assert.deepStrictEqual(EmojiSearch.filterTsvRows(tsvRows, ["nomatch"], 100), [])

console.log("emoji-search-test: all assertions passed")
EOF
