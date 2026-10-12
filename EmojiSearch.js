function parseEmojis(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function normalizedQuery(query) {
  return String(query || "").trim().toLowerCase()
}

function keywordText(item) {
  return String((item && item.k) || "").toLowerCase()
}

function filterEmojis(emojis, query, limit) {
  var values = Array.isArray(emojis) ? emojis : []
  var needle = normalizedQuery(query)
  var max = limit === undefined || limit === null ? 1000 : Number(limit)
  if (isNaN(max)) max = 1000
  max = Math.max(0, max)
  if (max === 0) return []

  // Token AND-match: every whitespace-separated word of the query must
  // appear in the keywords, so "material home" finds nf-md-home.
  var tokens = []
  if (needle) {
    var parts = needle.split(" ")
    for (var p = 0; p < parts.length; p++) {
      if (parts[p]) tokens.push(parts[p])
    }
  }

  var out = []

  for (var i = 0; i < values.length; i++) {
    var item = values[i]
    if (!item || !item.e) continue
    var text = null
    var matched = true
    for (var t = 0; t < tokens.length; t++) {
      if (text === null) text = keywordText(item)
      if (text.indexOf(tokens[t]) < 0) {
        matched = false
        break
      }
    }
    if (matched) {
      out.push(item)
      if (out.length >= max) break
    }
  }

  return out
}

function queryTokens(query) {
  var tokens = []
  var parts = normalizedQuery(query).split(" ")
  for (var i = 0; i < parts.length; i++) {
    if (parts[i]) tokens.push(parts[i])
  }
  return tokens
}

// Nerd Fonts spans the BMP and the astral planes (md icons live above
// U+F0000), so decode hex codepoints through surrogate pairs.
function glyphFromHex(hex) {
  var cp = parseInt(String(hex || ""), 16)
  if (!isFinite(cp) || cp <= 0 || cp > 0x10ffff) return ""
  if (cp <= 0xffff) return String.fromCharCode(cp)
  cp -= 0x10000
  return String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp % 0x400))
}

// nerdfonts.tsv rows are: keywords <TAB> name <TAB> hex-codepoint.
function parseTsvLine(line) {
  var f = String(line || "").split("\t")
  if (f.length < 3) return null
  var glyph = glyphFromHex(f[2])
  return glyph ? { e: glyph, n: f[1], k: f[0].toLowerCase() } : null
}

// kaomoji.tsv rows are: tags <TAB> kaomoji-string. Rows feed straight
// into filterEmojis (token-AND over k), so "table flip" matches the tag
// "table flip" as the tokens table+flip.
function parseKaomojiTsv(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var tab = line.indexOf("\t")
    if (tab < 0) continue
    var tags = line.substring(0, tab)
    var str = line.substring(tab + 1)
    if (str) out.push({ e: str, k: tags.toLowerCase(), tags: tags })
  }
  return out
}

// "[tag1, tag2]" for the row's centered, dimmed tag column.
function formatKaomojiTags(tags) {
  var text = String(tags || "")
  return text ? "[" + text.split(" ").join(", ") + "]" : ""
}

// Rows arrive from a single-token grep prefilter; re-check the full
// token-AND here so semantics match the in-memory filterEmojis exactly.
function filterTsvRows(rows, tokens, limit) {
  var max = limit === undefined || limit === null ? 1000 : Number(limit)
  if (isNaN(max) || max < 0) max = 1000
  var out = []
  for (var i = 0; i < rows.length && out.length < max; i++) {
    var item = parseTsvLine(rows[i])
    if (!item) continue
    var matched = true
    for (var t = 0; t < tokens.length; t++) {
      if (item.k.indexOf(tokens[t]) < 0) { matched = false; break }
    }
    if (matched) out.push(item)
  }
  return out
}

// Recents are a small MRU list of { e, k, n?, tags? } persisted as JSON.
// Equality is by glyph string (e) so re-picking bumps an entry to the front.
function normalizeRecent(item) {
  if (!item || item.e === undefined || item.e === null || item.e === "") return null
  var entry = { e: String(item.e), k: String(item.k || "").toLowerCase() }
  if (item.n) entry.n = String(item.n)
  if (item.tags) entry.tags = String(item.tags)
  // Fold name/tags into k so filterEmojis can search them without a
  // separate code path (nerd names, kaomoji tags).
  var extra = ((entry.n || "") + " " + (entry.tags || "")).toLowerCase().trim()
  if (extra && entry.k.indexOf(extra) < 0)
    entry.k = (entry.k ? entry.k + " " : "") + extra
  return entry
}

// Dimmed hint shown beside a Recents glyph: the Nerd Font name, the
// kaomoji tags, or the emoji's own keywords, in that order.
function recentHint(item) {
  if (!item) return ""
  if (item.n) return String(item.n)
  if (item.tags) return formatKaomojiTags(item.tags)
  return String(item.k || "")
}

// Alt+digit hotkeys address the first ten Recents rows: 1–9 then 0.
// Returns the row index, or -1 for anything else. The scan code keeps
// it layout-independent (Shift or a Greek layout change event.key);
// X11/evdev scan codes 10–19 are the digit row 1…0.
function hotkeyIndex(key, scanCode) {
  var digit = -1
  if (scanCode >= 10 && scanCode <= 19) digit = scanCode === 19 ? 0 : scanCode - 9
  else if (key >= 0x30 && key <= 0x39) digit = key - 0x30
  if (digit < 0) return -1
  return digit === 0 ? 9 : digit - 1
}

// Label for row index 0–9 ("1"…"9", "0"); empty past the tenth row.
function hotkeyLabel(index) {
  if (index < 0 || index > 9) return ""
  return index === 9 ? "0" : String(index + 1)
}

function parseRecents(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    if (!Array.isArray(data)) return []
    var out = []
    for (var i = 0; i < data.length; i++) {
      var entry = normalizeRecent(data[i])
      if (entry) out.push(entry)
    }
    return out
  } catch (e) {
    return []
  }
}

function rememberRecent(list, item, limit) {
  var entry = normalizeRecent(item)
  if (!entry) return Array.isArray(list) ? list.slice() : []
  var max = limit === undefined || limit === null ? 48 : Number(limit)
  if (isNaN(max) || max < 0) max = 48
  if (max === 0) return []

  var out = [entry]
  var values = Array.isArray(list) ? list : []
  for (var i = 0; i < values.length; i++) {
    var prev = normalizeRecent(values[i])
    if (!prev || prev.e === entry.e) continue
    out.push(prev)
    if (out.length >= max) break
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    normalizedQuery: normalizedQuery,
    filterEmojis: filterEmojis,
    queryTokens: queryTokens,
    glyphFromHex: glyphFromHex,
    parseKaomojiTsv: parseKaomojiTsv,
    formatKaomojiTags: formatKaomojiTags,
    parseTsvLine: parseTsvLine,
    filterTsvRows: filterTsvRows,
    normalizeRecent: normalizeRecent,
    parseRecents: parseRecents,
    rememberRecent: rememberRecent,
    recentHint: recentHint,
    hotkeyIndex: hotkeyIndex,
    hotkeyLabel: hotkeyLabel
  }
}
