.pragma library

// Mounts mirror the CHANNELS table on sprawlfm.com. Slugs are what the
// persisted state file stores, so renaming one resets a saved selection
// to the first channel rather than breaking.
var list = [
  { slug: "all",  mount: "/sprawl-fm",   name: "ALL FREQUENCIES" },
  { slug: "hard", mount: "/sprawl-hard", name: "SLAG" },
  { slug: "atmo", mount: "/sprawl-atmo", name: "VAPE" },
  { slug: "down", mount: "/sprawl-down", name: "SMOG" },
  { slug: "rave", mount: "/sprawl-rave", name: "RAVE" },
  { slug: "zion", mount: "/sprawl-zion", name: "ZION" },
  { slug: "dark", mount: "/sprawl-dark", name: "DARK" },
  { slug: "code", mount: "/sprawl-code", name: "CODE" }
]

var origin = "https://sprawlfm.com"

function streamUrl(mount) {
  return origin + mount
}

function indexOfSlug(slug) {
  for (var i = 0; i < list.length; i++) {
    if (list[i].slug === slug) return i
  }
  return -1
}

// Icecast collapses `source` to a bare object when exactly one mount is
// live, so every reader has to normalize before iterating.
function sources(payload) {
  if (!payload || !payload.icestats) return []
  var s = payload.icestats.source
  if (!s) return []
  return (Object.prototype.toString.call(s) === "[object Array]") ? s.slice(0, 128) : [s]
}

function sourceForMount(payload, mount) {
  var all = sources(payload)
  for (var i = 0; i < all.length; i++) {
    var url = String(all[i].listenurl || "")
    if (url.length >= mount.length && url.slice(-mount.length) === mount) return all[i]
  }
  return null
}

function titleOf(source) {
  if (!source) return ""
  return String(source.title || source.yp_currently_playing || "").trim().slice(0, 500)
}

function listenersOf(source) {
  if (!source) return -1
  var n = parseInt(source.listeners, 10)
  return isNaN(n) ? -1 : n
}

function descriptionOf(source) {
  if (!source) return ""
  return String(source.server_description || "").trim().slice(0, 500)
}

function genreOf(source) {
  if (!source) return ""
  return String(source.genre || "").trim().slice(0, 200)
}

// Per-widget settings live on the plugin's entry in shell.json's bar layout,
// which is also what `omarchy bar set <id> <key> <value>` writes. Reading them
// straight off the shell config keeps the service authoritative: it does not
// have to wait for a bar widget to mount and push settings down, so startup
// channel resolution has no race with the persisted-channel file load.
function widgetSetting(shellConfig, pluginId, key, fallback) {
  if (!shellConfig || !shellConfig.bar || !shellConfig.bar.layout) return fallback
  var layout = shellConfig.bar.layout
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout[sections[s]]
    if (!entries || entries.length === undefined) continue
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (!entry || entry.id !== pluginId) continue
      var value = entry[key]
      if (value !== undefined && value !== null) return value
    }
  }
  return fallback
}
