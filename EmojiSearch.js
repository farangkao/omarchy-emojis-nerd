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

if (typeof module !== "undefined") {
  module.exports = {
    parseEmojis: parseEmojis,
    normalizedQuery: normalizedQuery,
    filterEmojis: filterEmojis
  }
}
