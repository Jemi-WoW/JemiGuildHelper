local _, JGH = ...

-- Guild members' level-ups and maxed professions, for a quick congrats.
local Dings = {}
JGH.Dings = Dings

local PREFIX = "JGHDing"
local PROTO = "1"
local MAXED = 300
local ROSTER_EVERY = 15
local RETRY_FOR = 120
local RELAY_JITTER = 2

-- Grats lines, one picked at random: {name} is their first name, {level} the level, {prof} the profession.
local GRATS_LEVEL = {
  "Gz {name}!",
  "Grats {name}!",
}
local GRATS_MAX_LEVEL = {
  "Gz {name}!",
  "Grats {name}!",
}
local GRATS_PROF = {
  "Gz on 300 {prof}, {name}!",
}

local seenLevel = {}
local shown = {}
local relayed = {}
local pending = {}
local profsReady = false

function Dings.Enabled()
  return JGH.DB().dings ~= false
end

function Dings.SetEnabled(on)
  JGH.DB().dings = on
end

Dings.MIN_LEVEL = 15

-- Level-ups below this stay quiet; professions always show.
function Dings.MinLevel()
  return JGH.DB().dingMinLevel or Dings.MIN_LEVEL
end

local function FirstName(name)
  return name:match("^(%S+)") or name
end

-- What the Grats button says in guild chat.
function Dings.GratsText(d)
  local lines = (d.kind == "P" and GRATS_PROF) or (d.value >= JGH.MaxLevel() and GRATS_MAX_LEVEL) or GRATS_LEVEL
  local fill = {
    name = FirstName(d.name),
    level = d.kind == "L" and tostring(d.value) or "",
    prof = d.kind == "P" and JGH.Crafts.ProfName(d.value) or "",
  }
  return (lines[math.random(#lines)]:gsub("{(%a+)}", function(key) return fill[key] end))
end

function Dings.Text(d)
  if d.kind == "P" then return ("reached %d %s"):format(MAXED, JGH.Crafts.ProfName(d.value)) end
  return ("reached level %d"):format(d.value)
end

-- The same ding can come from a message and the roster, so it shows once; true when it's new.
local function Show(name, kind, value, class)
  local key = name .. "|" .. kind .. "|" .. value
  if shown[key] then return false end
  shown[key] = true
  if kind == "L" then
    seenLevel[name] = math.max(seenLevel[name] or 0, value)
    -- Kept across reloads, so a late message can't bring back a ding already shown.
    local c = JGH.CharDB()
    c.dingLevel = c.dingLevel or {}
    if (c.dingLevel[name] or 0) >= value then return false end
    c.dingLevel[name] = value
  end
  if Dings.Enabled() and name ~= JGH.PlayerName() and (kind ~= "L" or value >= Dings.MinLevel()) then
    JGH.Fire("Ding", { name = name, kind = kind, value = value, class = class })
  end
  return true
end

local function Send(msg)
  if not IsInGuild() then return true end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  return ok and (result == nil or result == true or result == 0)
end

-- Levels often come mid-fight, when sending can be blocked; those retry for a while.
local function Announce(kind, value)
  local _, class = UnitClass("player")
  local msg = table.concat({ PROTO, kind, value, class or "" }, "|")
  if not Send(msg) then pending[#pending + 1] = { msg = msg, at = GetTime() } end
end

-- Members without the addon can't announce, so whoever spots it first tells the rest; the random wait lets one speak for all.
local function Relay(name, level, class)
  local key = name .. "|" .. level
  C_Timer.After(math.random() * RELAY_JITTER, function()
    if relayed[key] then return end
    relayed[key] = true
    Send(table.concat({ PROTO, "R", level, class or "", name }, "|"))
  end)
end

local function Spotted(name, level, class)
  if Show(name, "L", level, class) then Relay(name, level, class) end
end

local function Retry()
  for i = #pending, 1, -1 do
    local p = pending[i]
    if Send(p.msg) or GetTime() - p.at > RETRY_FOR then table.remove(pending, i) end
  end
end

-- Only new 300s count; ones already maxed before the addon was installed stay quiet.
local function CheckProfessions()
  local c = JGH.CharDB()
  c.maxed = c.maxed or {}
  local any = false
  for _, idx in pairs({ GetProfessions() }) do
    local _, _, rank, _, _, _, skillLine = GetProfessionInfo(idx)
    if skillLine and type(rank) == "number" then
      any = true
      if rank >= MAXED and not c.maxed[skillLine] then
        c.maxed[skillLine] = true
        if c.maxedReady then Announce("P", skillLine) end
      end
    end
  end
  if any then c.maxedReady = true end
end

-- Catches members without the addon, from level changes between roster updates.
local function CheckRoster()
  for name, info in pairs(JGH.Roster()) do
    if type(info.level) == "number" and not name:find("-", 1, true) then
      local before = seenLevel[name]
      if not before then
        seenLevel[name] = info.level
      elseif info.level > before then
        seenLevel[name] = info.level
        if info.online then Spotted(name, info.level, info.classFile) end
      end
    end
  end
end

local function OnMessage(_, prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" then return end
  if JGH.IsSecret(text) or JGH.IsSecret(sender) then return end
  local proto, kind, value, class, about = strsplit("|", text)
  value = tonumber(value)
  if proto ~= PROTO or not value then return end
  class = class ~= "" and class or nil
  if kind == "R" then
    if not about or not JGH.IsGuildMember(about) or value <= (seenLevel[about] or 0) or value > JGH.MaxLevel() then return end
    relayed[about .. "|" .. value] = true
    Show(about, "L", value, class)
  elseif kind == "L" or kind == "P" then
    sender = JGH.StripRealm(sender)
    if kind == "L" then relayed[sender .. "|" .. value] = true end
    Show(sender, kind, value, class)
  end
end

-- Grouped or nearby guildies level in front of us, long before the roster catches up.
local function OnUnitLevel(_, unit)
  if type(unit) ~= "string" then return end
  local isPlayer = UnitIsPlayer(unit)
  if JGH.IsSecret(isPlayer) or not isPlayer then return end
  local name, realm = UnitName(unit)
  local level = UnitLevel(unit)
  if JGH.IsSecret(name) or JGH.IsSecret(realm) or JGH.IsSecret(level) or type(level) ~= "number" then return end
  if not name or (realm and realm ~= "") or name == JGH.PlayerName() or not JGH.IsGuildMember(name) then return end
  local before = seenLevel[name]
  if before and level > before then
    local _, class = UnitClass(unit)
    Spotted(name, level, not JGH.IsSecret(class) and class or nil)
  elseif not before then
    seenLevel[name] = level
  end
end

function Dings.Init()
  if C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
  JGH.RegisterEvent("CHAT_MSG_ADDON", OnMessage)
  C_Timer.NewTicker(5, Retry)
  C_Timer.NewTicker(ROSTER_EVERY, JGH.RequestRoster)
  -- Professions load a moment after login; earlier reads come back empty.
  C_Timer.After(10, function()
    profsReady = true
    CheckProfessions()
  end)
end

JGH.RegisterEvent("PLAYER_LEVEL_UP", function(_, level)
  if JGH.IsSecret(level) or type(level) ~= "number" then return end
  Announce("L", level)
end)
JGH.RegisterEvent("SKILL_LINES_CHANGED", function()
  if profsReady then CheckProfessions() end
end)
JGH.On("RosterChanged", CheckRoster)
JGH.RegisterEvent("UNIT_LEVEL", OnUnitLevel)
JGH.RegisterEvent("PLAYER_GUILD_UPDATE", function() wipe(seenLevel) end)
