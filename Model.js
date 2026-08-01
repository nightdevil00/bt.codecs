function parseCards(raw) {
  var cards = []
  var current = null
  var inProfiles = false
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var trimmed = line.trim()
    if (trimmed === "") continue

    if (/^Card #/.test(trimmed)) {
      if (current) cards.push(current)
      current = {
        name: "",
        driver: "",
        description: "",
        deviceName: "",
        address: "",
        isBluetooth: false,
        activeProfile: "",
        profiles: []
      }
      inProfiles = false
      continue
    }
    if (!current) continue

    var tab1 = line.charAt(0) === "\t"
    var tab2 = tab1 && line.charAt(1) === "\t"

    if (tab1 && !tab2) {
      if (trimmed === "Profiles:") {
        inProfiles = true
        continue
      }
      inProfiles = false
      var colon = trimmed.indexOf(": ")
      if (colon > 0) {
        var key = trimmed.slice(0, colon)
        var val = trimmed.slice(colon + 2).trim()
        if (key === "Name") current.name = val
        else if (key === "Driver") current.driver = val
        else if (key === "Active Profile") current.activeProfile = val
      }
      continue
    }

    if (tab2) {
      if (inProfiles) {
        var prof = parseProfile(trimmed)
        if (prof) current.profiles.push(prof)
      } else {
        var eq = trimmed.indexOf(" = ")
        if (eq > 0) {
          var pkey = trimmed.slice(0, eq)
          var pval = trimmed.slice(eq + 3).trim().replace(/^"|"$/g, "")
          if (pkey === "device.description") current.description = pval
          else if (pkey === "device.name") current.deviceName = pval
          else if (pkey === "api.bluez5.address" || pkey === "bluez5.address") current.address = pval
          else if (pkey === "device.api") current.isBluetooth = pval === "bluez5"
        }
      }
      continue
    }

    inProfiles = false
  }
  if (current) cards.push(current)
  return cards
}

function parseProfile(trimmed) {
  var colon = trimmed.indexOf(": ")
  if (colon < 0) return null
  var name = trimmed.slice(0, colon)
  var rest = trimmed.slice(colon + 2)
  var codec = ""
  var codecMatch = rest.match(/codec ([A-Za-z0-9\-_.]+)/)
  if (codecMatch) codec = codecMatch[1]
  var available = true
  var availMatch = rest.match(/available: (yes|no)/)
  if (availMatch) available = availMatch[1] === "yes"
  return {
    name: name,
    codec: codec,
    available: available,
    label: profileLabel(name, codec, rest),
    description: codecDescription(codec)
  }
}

var CODEC_DESCRIPTIONS = {
  "aac": "High quality",
  "sbc": "Standard",
  "sbc-xq": "Enhanced",
  "aptx": "High quality",
  "aptx-hd": "High-resolution",
  "aptx-ll": "Low latency",
  "aptx-adaptive": "Adaptive",
  "ldac": "High-resolution",
  "lc3": "Efficient",
  "msbc": "Wideband voice",
  "cvsd": "Narrowband voice"
}

function codecDescription(codec) {
  if (!codec) return ""
  var key = String(codec).toLowerCase()
  return CODEC_DESCRIPTIONS[key] || ""
}

function profileLabel(name, codec, rest) {
  if (/^a2dp/.test(name)) return codec !== "" ? codec : "HiFi"
  if (/^headset|^hsp|^hfp/.test(name)) return "Headset" + (codec !== "" ? " \u00b7 " + codec : "")
  var base = String(rest).replace(/\s*\(sinks:.*$/, "").trim()
  return base !== "" ? base : name
}

function bluetoothCards(cards) {
  var out = []
  var list = Array.isArray(cards) ? cards : []
  for (var i = 0; i < list.length; i++) {
    var c = list[i]
    if (!c) continue
    if (!c.isBluetooth && String(c.name || "").indexOf("bluez_card") !== 0) continue
    for (var j = 0; j < c.profiles.length; j++)
      c.profiles[j].active = c.profiles[j].name === c.activeProfile
    out.push(c)
  }
  return out
}

function activeCard(cards) {
  var bt = bluetoothCards(cards)
  for (var i = 0; i < bt.length; i++) {
    if (bt[i].activeProfile && bt[i].activeProfile !== "off") return bt[i]
  }
  return bt.length > 0 ? bt[0] : null
}

function codecShort(card) {
  if (!card) return ""
  var ap = String(card.activeProfile || "")
  if (/^a2dp/.test(ap)) {
    for (var i = 0; i < card.profiles.length; i++)
      if (card.profiles[i].name === ap && card.profiles[i].codec !== "") return card.profiles[i].codec
    return "HiFi"
  }
  if (/^headset|^hsp|^hfp/.test(ap)) return "Headset"
  return ""
}

function buildRows(cards) {
  var rows = []
  var bt = bluetoothCards(cards)
  for (var i = 0; i < bt.length; i++) {
    var c = bt[i]
    rows.push({ kind: "header", text: c.description || c.deviceName || c.name, card: c })
    for (var j = 0; j < c.profiles.length; j++) {
      var p = c.profiles[j]
      if (!p.available || p.name === "off") continue
      rows.push({ kind: "profile", card: c, profile: p })
    }
  }
  return rows
}

if (typeof module !== "undefined") {
  module.exports = {
    parseCards: parseCards,
    parseProfile: parseProfile,
    profileLabel: profileLabel,
    codecDescription: codecDescription,
    bluetoothCards: bluetoothCards,
    activeCard: activeCard,
    codecShort: codecShort,
    buildRows: buildRows
  }
}
