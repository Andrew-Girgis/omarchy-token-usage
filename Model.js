// Pure helpers, also exercised under Node. Shared shell sinks never receive markup.
function sharedText(value) {
  return String(value).replace(/&/g, "＆").replace(/</g, "＜").replace(/>/g, "＞").slice(0, 500)
}

function compact(value, format) {
  if (value === null || value === undefined || !isFinite(value)) return "—"
  var n = Math.max(0, Number(value))
  var units = [[1e9, "B"], [1e6, "M"], [1e3, "K"]]
  for (var i = 0; i < units.length; i++) {
    if (n >= units[i][0]) return format(n / units[i][0], n >= units[i][0] * 100 ? 0 : 1) + units[i][1]
  }
  return format(n, 0)
}

function timeParts(value) {
  var minutes = Math.floor(Math.max(0, Number(value) || 0) / 60)
  return [Math.floor(minutes / 60), minutes % 60]
}

function maxValue(rows) {
  return Math.max.apply(null, [1].concat(rows.map(function(row) { return row.value || 0 })))
}

function projectRows(rows, byTime) {
  return (rows || []).map(function(row) {
    return {name: row.name, value: byTime ? row.seconds : row.value}
  }).sort(function(a, b) { return b.value - a.value })
}

function timeSegments(time) {
  if (!time) return [0, 0, 0]
  return [Math.max(0, time.agent_seconds - time.overlap_seconds),
          Math.max(0, time.you_seconds - time.overlap_seconds), time.overlap_seconds]
}

if (typeof module !== "undefined") module.exports = {sharedText, compact, timeParts, maxValue, projectRows, timeSegments}
